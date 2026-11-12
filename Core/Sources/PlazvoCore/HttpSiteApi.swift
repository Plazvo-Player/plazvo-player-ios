import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A API do servidor pela internet.
///
/// Nada do que passa por aqui é escrito em registros: o segredo do aparelho vai no corpo do
/// registro e num cabeçalho, nunca no endereço, e as listas trazem usuário e senha.
public struct HttpSiteApi: SiteApi {
    /// Tempo de espera por uma resposta, em segundos (o contrato da API pede 15).
    public static let requestTimeout: TimeInterval = 15

    /// As respostas da API são pequenas; mais que isto é resposta estranha e não é lida.
    public static let maxAnswerBytes = 512 * 1024

    private let baseURL: String
    private let userAgent: String
    private let session: URLSession

    /// - Parameters:
    ///   - baseURL: endereço da API, sem a barra do fim (ex.: `https://servidor/v1`).
    ///   - userAgent: como o app se apresenta (ex.: `PlazvoPlayer/0.1.0 (ios)`).
    ///   - session: só os testes passam uma; o app usa a própria, sem cache nem cookies.
    public init(baseURL: String, userAgent: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.session = session ?? HttpSiteApi.makeSession()
    }

    /// Sessão sem cache, sem cookies e que não segue redirecionamento.
    public static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout * 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    public func register(_ credentials: DeviceCredentials, platform: String, appVersion: String) async -> ApiResult<Void> {
        let body = [
            "device_id": credentials.id,
            "key": credentials.key,
            "secret": credentials.secret,
            "platform": platform,
            "app_version": appVersion,
        ]
        return await call("POST", "/device/register", body: body) { _ in }
    }

    public func playlists(deviceId: String, secret: String) async -> ApiResult<PlaylistsAnswer> {
        await call("GET", "/device/playlists", headers: deviceHeaders(deviceId, secret), parse: parsePlaylistsAnswer)
    }

    public func activateWithCode(deviceId: String, secret: String, code: String) async -> ApiResult<CodeAnswer> {
        // O código vai no corpo, nunca no endereço: endereço cai em registro de servidor.
        await call("POST", "/device/activate-code", headers: deviceHeaders(deviceId, secret), body: ["code": code], parse: parseCodeAnswer)
    }

    public func unlink(deviceId: String, secret: String) async -> ApiResult<UnlinkAnswer> {
        await call("POST", "/device/unlink", headers: deviceHeaders(deviceId, secret), body: [:], parse: parseUnlinkAnswer)
    }

    public func ping() async -> ApiResult<Void> {
        await call("GET", "/ping") { _ in }
    }

    private func deviceHeaders(_ deviceId: String, _ secret: String) -> [String: String] {
        ["X-Device-Id": deviceId, "X-Device-Secret": secret]
    }

    private func call<Value: Sendable>(
        _ method: String,
        _ path: String,
        headers: [String: String] = [:],
        body: [String: String]? = nil,
        parse: (String) throws -> Value
    ) async -> ApiResult<Value> {
        guard let url = URL(string: baseURL + path) else { return .unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = HttpSiteApi.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body {
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { return .unavailable }
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        guard let (data, response) = await send(request), let http = response as? HTTPURLResponse else {
            return .unavailable
        }
        guard data.count <= HttpSiteApi.maxAnswerBytes else { return .unavailable }
        let text = String(decoding: data, as: UTF8.self)

        switch http.statusCode {
        case 200:
            // Resposta 200 que não é o que o contrato diz (por exemplo, a página de uma rede Wi-Fi)
            // conta como falta de resposta.
            guard let value = try? parse(text) else { return .unavailable }
            return .ok(value)
        case 400...499:
            return .refused(status: http.statusCode, error: errorName(text))
        default:
            return .unavailable
        }
    }

    /// Faz o pedido. `nil` quando não houve resposta (sem internet, tempo esgotado…).
    private func send(_ request: URLRequest) async -> (Data, URLResponse)? {
        await withCheckedContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if error == nil, let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            task.resume()
        }
    }

    /// O nome do motivo de uma recusa (`"error"` no corpo JSON), ou `nil` se não há ou não dá para ler.
    private func errorName(_ text: String) -> String? {
        guard let fields = try? JSONValue.parse(text).fields, let name = fields.text("error"), !name.isEmpty else {
            return nil
        }
        return name
    }
}

/// A API não redireciona; seguir um redirecionamento levaria o segredo do aparelho para outro lugar.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
