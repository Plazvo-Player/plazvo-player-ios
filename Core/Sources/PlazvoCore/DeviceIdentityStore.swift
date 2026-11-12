import Foundation

/// Guarda o ID, a chave e o segredo deste aparelho no cofre. Use uma única instância por app.
///
/// Duas regras que não podem sair daqui:
/// - cofre que não pôde ser lido não é trocado por uma identidade nova (seria outro aparelho, sem
///   a ativação): a leitura falha e nada é criado;
/// - identidade que não ficou guardada não é usada (ninguém ativa um aparelho que some ao fechar).
@MainActor
public final class DeviceIdentityStore {
    /// Não deu para ler ou gravar a identidade no cofre.
    public struct StorageFailure: Error, Equatable {
        public init() {}
    }

    private struct Stored: Codable, Equatable {
        var id: String
        var key: String
        var secret: String

        var isValid: Bool {
            DeviceIdGenerator.isValidId(id) && DeviceIdGenerator.isValidKey(key) && DeviceIdGenerator.isValidSecret(secret)
        }
    }

    private let store: SecureStore
    private let random: RandomSource
    private var stored: Stored?

    /// O ID e a chave para a tela; `nil` até `ensureCreated()` dar certo.
    public private(set) var identity: DeviceIdentity? {
        didSet {
            if identity != oldValue { onChange?(identity) }
        }
    }

    /// Chamado quando o ID ou a chave mudam.
    public var onChange: ((DeviceIdentity?) -> Void)?

    public init(store: SecureStore, random: RandomSource = .system) {
        self.store = store
        self.random = random
    }

    /// Cria o ID, a chave e o segredo na primeira abertura. Nas seguintes, só lê o que está guardado.
    @discardableResult
    public func ensureCreated() throws -> DeviceIdentity {
        if let stored { return DeviceIdentity(id: stored.id, key: stored.key) }

        let data: Data?
        do {
            data = try store.read()
        } catch {
            throw StorageFailure()
        }

        if let data, let saved = try? JSONDecoder().decode(Stored.self, from: data), saved.isValid {
            adopt(saved)
            return DeviceIdentity(id: saved.id, key: saved.key)
        }

        // Nada guardado (ou o que havia não tem o formato de uma identidade): aparelho novo.
        let fresh = Stored(
            id: DeviceIdGenerator.newId(random),
            key: DeviceIdGenerator.newKey(random),
            secret: DeviceIdGenerator.newSecret(random)
        )
        try save(fresh)
        adopt(fresh)
        return DeviceIdentity(id: fresh.id, key: fresh.key)
    }

    /// Troca a chave por uma nova. O ID e o segredo continuam os mesmos.
    public func rotateKey() throws {
        try ensureCreated()
        guard var next = stored else { throw StorageFailure() }
        var key = DeviceIdGenerator.newKey(random)
        while key == next.key {
            key = DeviceIdGenerator.newKey(random)
        }
        next.key = key
        try save(next)
        adopt(next)
    }

    /// O que o app apresenta ao servidor: ID, chave e segredo (criando-os se ainda não existem).
    public func credentials() throws -> DeviceCredentials {
        try ensureCreated()
        guard let stored else { throw StorageFailure() }
        return DeviceCredentials(id: stored.id, key: stored.key, secret: stored.secret)
    }

    private func save(_ value: Stored) throws {
        do {
            try store.write(try JSONEncoder().encode(value))
        } catch {
            throw StorageFailure()
        }
    }

    private func adopt(_ value: Stored) {
        stored = value
        identity = DeviceIdentity(id: value.id, key: value.key)
    }
}
