import Foundation
import Testing
@testable import PlazvoCore

@MainActor
@Suite("Identidade do aparelho")
struct DeviceIdentityTests {
    @Test("o ID, a chave e o segredo saem nos formatos do app Android")
    func formats() {
        for seed in UInt64(1)...50 {
            let random = predictableRandom(seed: seed)
            let id = DeviceIdGenerator.newId(random)
            let key = DeviceIdGenerator.newKey(random)
            let secret = DeviceIdGenerator.newSecret(random)
            #expect(id.count == 17)
            #expect(DeviceIdGenerator.isValidId(id), "ID fora do formato: \(id)")
            #expect(DeviceIdGenerator.isValidKey(key), "chave fora do formato: \(key)")
            #expect(Int(key)! >= 100_000 && Int(key)! <= 999_999)
            #expect(DeviceIdGenerator.isValidSecret(secret))
        }
    }

    @Test("o gerador do sistema também respeita os formatos, e não se repete")
    func systemRandom() {
        let first = DeviceIdGenerator.newSecret()
        let second = DeviceIdGenerator.newSecret()
        #expect(DeviceIdGenerator.isValidSecret(first))
        #expect(first != second)
        #expect(DeviceIdGenerator.isValidId(DeviceIdGenerator.newId()))
        #expect(DeviceIdGenerator.isValidKey(DeviceIdGenerator.newKey()))
    }

    @Test("formatos que não valem são recusados")
    func invalidFormats() {
        #expect(!DeviceIdGenerator.isValidId("7C:2E:9A:41:D0:B6"))
        #expect(!DeviceIdGenerator.isValidId("7c:2e:9a:41:d0"))
        #expect(!DeviceIdGenerator.isValidId("7c2e9a41d0b6"))
        #expect(!DeviceIdGenerator.isValidKey("012345"))
        #expect(!DeviceIdGenerator.isValidKey("12345"))
        #expect(!DeviceIdGenerator.isValidKey("12a456"))
        #expect(!DeviceIdGenerator.isValidSecret(String(repeating: "g", count: 64)))
        #expect(!DeviceIdGenerator.isValidSecret(String(repeating: "a", count: 63)))
    }

    @Test("primeira abertura cria e guarda; as seguintes leem a mesma identidade")
    func createsOnceAndKeeps() throws {
        let secure = InMemorySecureStore()
        let first = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 3))
        #expect(first.identity == nil)
        let created = try first.ensureCreated()
        #expect(first.identity == created)
        #expect(secure.data != nil)
        let credentials = try first.credentials()

        // O app fecha e abre (ou é reinstalado com o cofre no lugar): outro sorteio, mesma identidade.
        let second = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 99))
        #expect(try second.ensureCreated() == created)
        #expect(try second.credentials() == credentials)
    }

    @Test("nova chave troca só a chave e fica guardada")
    func rotateKey() throws {
        let secure = InMemorySecureStore()
        let store = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 5))
        let before = try store.credentials()
        var seen: [DeviceIdentity?] = []
        store.onChange = { seen.append($0) }

        try store.rotateKey()

        let after = try store.credentials()
        #expect(after.id == before.id)
        #expect(after.secret == before.secret)
        #expect(after.key != before.key)
        #expect(DeviceIdGenerator.isValidKey(after.key))
        #expect(seen == [DeviceIdentity(id: after.id, key: after.key)])
        let reopened = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 6))
        #expect(try reopened.credentials() == after)
    }

    @Test("cofre que não pôde ser lido não é trocado por uma identidade nova")
    func unreadableStoreIsNotReplaced() throws {
        let secure = InMemorySecureStore()
        let original = try DeviceIdentityStore(store: secure, random: predictableRandom(seed: 7)).credentials()
        let saved = secure.data

        secure.readFailure = SecureStoreError(status: -25308)
        let store = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 8))
        #expect(throws: DeviceIdentityStore.StorageFailure.self) { try store.ensureCreated() }
        #expect(throws: DeviceIdentityStore.StorageFailure.self) { try store.credentials() }
        #expect(throws: DeviceIdentityStore.StorageFailure.self) { try store.rotateKey() }
        #expect(store.identity == nil)
        #expect(secure.data == saved, "o cofre foi mexido")

        // O cofre voltou a abrir: é a identidade de antes, não uma nova.
        secure.readFailure = nil
        #expect(try store.credentials() == original)
    }

    @Test("identidade que não ficou guardada não é usada")
    func unsavedIdentityIsNotUsed() throws {
        let secure = InMemorySecureStore()
        secure.writeFailure = SecureStoreError(status: -25299)
        let store = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 9))
        #expect(throws: DeviceIdentityStore.StorageFailure.self) { try store.ensureCreated() }
        #expect(store.identity == nil)
        #expect(secure.data == nil)

        // A chave nova que não ficou guardada também não vale: continua a de antes.
        secure.writeFailure = nil
        let before = try store.credentials()
        secure.writeFailure = SecureStoreError(status: -25299)
        #expect(throws: DeviceIdentityStore.StorageFailure.self) { try store.rotateKey() }
        #expect(try store.credentials() == before)
    }

    @Test("o que está no cofre e não é uma identidade é trocado por uma nova")
    func malformedContentIsReplaced() throws {
        for content in ["", "{}", "isto não é JSON", "{\"id\":\"x\",\"key\":\"1\",\"secret\":\"y\"}"] {
            let secure = InMemorySecureStore(data: Data(content.utf8))
            let store = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 11))
            let created = try store.credentials()
            #expect(DeviceIdGenerator.isValidId(created.id))
            #expect(DeviceIdGenerator.isValidSecret(created.secret))
            let reopened = DeviceIdentityStore(store: secure, random: predictableRandom(seed: 12))
            #expect(try reopened.credentials() == created)
        }
    }

    @Test("o segredo não aparece em texto nenhum da identidade")
    func secretIsNotPrinted() throws {
        let credentials = try DeviceIdentityStore(store: InMemorySecureStore(), random: predictableRandom(seed: 13)).credentials()
        var dumped = ""
        dump(credentials, to: &dumped)
        for text in ["\(credentials)", String(describing: credentials), String(reflecting: credentials), dumped] {
            #expect(!text.contains(credentials.secret))
            #expect(!text.contains(credentials.key))
        }
    }

    @Test("o segredo não aparece ao mostrar o que o guardador da identidade tem dentro")
    func storedSecretIsNotPrinted() throws {
        let store = DeviceIdentityStore(store: InMemorySecureStore(), random: predictableRandom(seed: 13))
        let secret = try store.credentials().secret
        var dumped = ""
        dump(store, to: &dumped)
        // O mostrador chegou até o que está guardado (o ID aparece), mas não ao segredo.
        #expect(dumped.contains(try store.credentials().id))
        #expect(!dumped.contains(secret))
    }
}
