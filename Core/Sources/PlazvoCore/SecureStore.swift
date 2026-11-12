import Foundation

/// O cofre não pôde ser usado (o número é o código de erro do sistema).
public struct SecureStoreError: Error, Equatable {
    public let status: Int32

    public init(status: Int32) {
        self.status = status
    }
}

/// Um lugar seguro para um valor só (a identidade do aparelho).
public protocol SecureStore {
    /// O valor guardado, ou `nil` se não há nada guardado. Lança se o cofre não pôde ser lido:
    /// quem chama não pode tratar isso como "vazio".
    func read() throws -> Data?

    func write(_ data: Data) throws
}

/// Cofre que só existe na memória: para os testes e para a compilação do simulador.
public final class InMemorySecureStore: SecureStore {
    public var data: Data?
    /// Com valor, toda leitura falha com este erro (cofre ilegível).
    public var readFailure: SecureStoreError?
    /// Com valor, toda gravação falha com este erro.
    public var writeFailure: SecureStoreError?

    public init(data: Data? = nil) {
        self.data = data
    }

    public func read() throws -> Data? {
        if let readFailure { throw readFailure }
        return data
    }

    public func write(_ data: Data) throws {
        if let writeFailure { throw writeFailure }
        self.data = data
    }
}

#if canImport(Security)
import Security

/// O cofre do iPhone (Keychain). O valor fica só neste aparelho: não vai para outro por cópia de
/// segurança nem pelo iCloud.
public struct KeychainStore: SecureStore {
    private let service: String
    private let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() throws -> Data? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecureStoreError(status: status)
        }
        return data
    }

    public func write(_ data: Data) throws {
        let changes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(itemQuery as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = itemQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecureStoreError(status: status) }
    }
}
#endif
