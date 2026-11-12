import Foundation

/// Onde fica a cópia da última resposta do servidor (as listas trazem usuário e senha).
public protocol CopyStore {
    /// O conteúdo guardado, ou `nil` se não há nada ou se não deu para ler.
    func read() -> Data?
    func write(_ data: Data)
    func delete()
}

/// Cópia que só existe na memória: para os testes e para a compilação do simulador.
public final class InMemoryCopyStore: CopyStore {
    public var data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }

    public func read() -> Data? { data }
    public func write(_ data: Data) { self.data = data }
    public func delete() { data = nil }
}

/// Cópia num arquivo da área particular do app. No iPhone o arquivo fica criptografado pelo
/// sistema e fora das cópias de segurança (a ativação vale só neste aparelho).
public struct FileCopyStore: CopyStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() -> Data? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    public func write(_ data: Data) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: [.atomic])
        #endif
        #if canImport(Darwin)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        do {
            try target.setResourceValues(values)
        } catch {
            // Sem a marca, a cópia (que traz usuário e senha) iria para as cópias de segurança do
            // aparelho: melhor ficar sem ela (o app pede tudo de novo ao servidor).
            delete()
        }
        #endif
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
