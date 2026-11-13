// O que o PlazvoCore só tem no Mac/iPhone (por depender de bibliotecas da Apple), imitado para a
// conferência dos tipos fora de um Mac.
import Foundation
import PlazvoCore

public struct KeychainStore: SecureStore {
    public init(service: String, account: String) {}
    public func read() throws -> Data? { nil }
    public func write(_ data: Data) throws {}
    public func delete() throws {}
}
