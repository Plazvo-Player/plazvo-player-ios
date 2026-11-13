import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Confere por que um vídeo não abriu, depois que o motor de vídeo disse que deu erro:
/// - link: pede o começo do vídeo ao endereço e olha só a resposta (o corpo não é baixado);
/// - arquivo do aparelho: vê se ele ainda está lá.
///
/// Nada do que passa por aqui é escrito em registros (o endereço pode levar usuário e senha).
public struct PlaybackCheck: PlaybackDiagnosis {
    /// Tempo de espera pela resposta do endereço, em segundos.
    public static let timeout: TimeInterval = 8

    private let userAgent: String
    private let configure: (@Sendable (URLSessionConfiguration) -> Void)?

    /// - Parameters:
    ///   - userAgent: como o app se apresenta ao endereço do vídeo.
    ///   - configure: só os testes usam, para a conferência falar com um servidor de mentira.
    public init(userAgent: String, configure: (@Sendable (URLSessionConfiguration) -> Void)? = nil) {
        self.userAgent = userAgent
        self.configure = configure
    }

    public func failure(of kind: MediaKind, address: String) async -> PlaybackFailure {
        switch kind {
        case .demo:
            return .unknown
        case .file:
            guard let url = URL(string: address), url.isFileURL,
                  FileManager.default.isReadableFile(atPath: url.path)
            else { return .notFound }
            // O arquivo está lá: o que falhou foi a leitura do formato.
            return .format
        case .link:
            return await linkFailure(address)
        }
    }

    /// Como a conferência fala com o endereço: sem guardar nada do que vem (nem cookies, nem
    /// cópia das respostas) e sem mandar cookies.
    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = PlaybackCheck.timeout
        configuration.timeoutIntervalForResource = PlaybackCheck.timeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        return configuration
    }

    private func linkFailure(_ address: String) async -> PlaybackFailure {
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return .network }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = PlaybackCheck.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Como o motor de vídeo pede: o arquivo desde o começo.
        request.setValue("bytes=0-", forHTTPHeaderField: "Range")

        let configuration = PlaybackCheck.sessionConfiguration()
        configure?(configuration)

        // Se quem pediu desiste (o vídeo foi fechado), o pedido ao endereço é cancelado na hora.
        let answer = AnswerOnly()
        let status: Int? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                answer.start(request, configuration: configuration, continuation: continuation)
            }
        } onCancel: {
            answer.cancel()
        }
        guard let status else { return .network }
        if status >= 400 { return .http(status: status) }
        // O endereço respondeu, mas o que veio não é um vídeo que o reprodutor toque.
        return .format
    }
}

/// Fica só com o número da resposta: assim que ela chega, o pedido é cancelado (o corpo, que
/// pode ser um vídeo inteiro ou uma transmissão sem fim, não é baixado).
private final class AnswerOnly: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int?, Never>?
    private var session: URLSession?
    private var finished = false

    /// Faz o pedido. O resultado sai pela `continuation`, uma vez só.
    func start(_ request: URLRequest, configuration: URLSessionConfiguration, continuation: CheckedContinuation<Int?, Never>) {
        lock.lock()
        if finished {
            // Quem pediu já tinha desistido: o pedido nem sai.
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.continuation = continuation
        self.session = session
        lock.unlock()
        session.dataTask(with: request).resume()
    }

    /// Quem pediu desistiu: o pedido é cancelado.
    func cancel() {
        finish(nil)
    }

    /// Entrega o resultado uma vez só e encerra a sessão.
    private func finish(_ status: Int?) {
        lock.lock()
        finished = true
        let waiting = continuation
        continuation = nil
        let used = session
        session = nil
        lock.unlock()
        waiting?.resume(returning: status)
        used?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        completionHandler(.cancel)
        finish((response as? HTTPURLResponse)?.statusCode)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Sem resposta (sem internet, servidor fora do ar, tempo esgotado).
        finish(nil)
    }
}
