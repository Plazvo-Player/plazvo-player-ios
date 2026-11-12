import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PlazvoCore

/// A internet de mentira: os pedidos que o `HttpSiteApi` faz chegam aqui em vez de sair do
/// aparelho. Cada teste tem o seu servidor, com um endereço só dele.
final class StubServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data

        var json: [String: String] {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: String] ?? [:]
        }
    }

    enum Answer: Sendable {
        case response(status: Int, body: String, headers: [String: String] = [:])
        case noConnection
    }

    private static let lock = NSLock()
    private static var servers: [String: StubServer] = [:]

    let host = "t\(UUID().uuidString.lowercased().prefix(12)).exemplo.test"
    private let own = NSLock()
    private var received: [Request] = []
    private var answers: [Answer] = []

    init() {
        StubServer.lock.lock()
        StubServer.servers[host] = self
        StubServer.lock.unlock()
    }

    deinit {
        StubServer.lock.lock()
        StubServer.servers[host] = nil
        StubServer.lock.unlock()
    }

    static func named(_ host: String) -> StubServer? {
        lock.lock()
        defer { lock.unlock() }
        return servers[host]
    }

    /// A API de verdade, apontada para este servidor de mentira.
    var api: HttpSiteApi {
        HttpSiteApi(
            baseURL: "https://\(host)/v1",
            userAgent: "PlazvoPlayer/0.1.0 (ios)",
            session: HttpSiteApi.makeSession(protocolClasses: [StubProtocol.self])
        )
    }

    /// As próximas respostas, na ordem (sem resposta combinada, o servidor responde 200 `{}`).
    func willAnswer(_ next: Answer...) {
        own.lock()
        answers.append(contentsOf: next)
        own.unlock()
    }

    var requests: [Request] {
        own.lock()
        defer { own.unlock() }
        return received
    }

    fileprivate func handle(_ request: Request) -> Answer {
        own.lock()
        defer { own.unlock() }
        received.append(request)
        return answers.isEmpty ? .response(status: 200, body: "{}") : answers.removeFirst()
    }
}

final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = StubServer.named(url.host ?? "") else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let received = StubServer.Request(
            method: request.httpMethod ?? "",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: StubProtocol.body(of: request)
        )
        switch server.handle(received) {
        case .noConnection:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .response(let status, let body, let headers):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// O corpo do pedido (conforme o sistema, ele chega pronto ou como um fluxo a ler).
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

extension ApiResult {
    var value: Value? {
        if case .ok(let value) = self { return value }
        return nil
    }

    var refusedStatus: Int? {
        if case .refused(let status, _) = self { return status }
        return nil
    }

    var refusedError: String? {
        if case .refused(_, let error) = self { return error }
        return nil
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

@Suite("Conversa com o servidor (HTTP)")
struct HttpSiteApiTests {
    let server = StubServer()
    let credentials = DeviceCredentials(
        id: "7c:2e:9a:41:d0:b6",
        key: "483920",
        secret: String(repeating: "ab", count: 32)
    )

    /// O segredo (e o código de ativação) nunca vão no endereço: endereço cai em registro de servidor.
    private func addressIsClean(_ request: StubServer.Request, code: String? = nil) -> Bool {
        let address = request.url.absoluteString
        if address.contains(credentials.secret) || address.contains("?") { return false }
        if let code, address.contains(code) { return false }
        return true
    }

    // MARK: - Os pedidos

    @Test("registro: o ID, a chave, o segredo, a plataforma e a versão vão no corpo, por HTTPS")
    func register() async throws {
        let result = await server.api.register(credentials, platform: "ios", appVersion: "0.1.0")

        #expect(result.value != nil)
        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://\(server.host)/v1/device/register")
        #expect(request.json == [
            "device_id": "7c:2e:9a:41:d0:b6",
            "key": "483920",
            "secret": credentials.secret,
            "platform": "ios",
            "app_version": "0.1.0",
        ])
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["User-Agent"] == "PlazvoPlayer/0.1.0 (ios)")
        #expect(request.headers["X-Device-Secret"] == nil)
        #expect(addressIsClean(request))
    }

    @Test("situação do aparelho: o ID e o segredo vão nos cabeçalhos, e a resposta é lida pelo contrato")
    func playlists() async throws {
        server.willAnswer(.response(status: 200, body: """
        {"active": true, "expires_at": "2027-11-13T02:59:59Z", "server_time": "2026-11-12T17:30:00Z", "partner": true,
         "playlists": [{"id": 7, "name": "Casa", "type": "xtream", "url": "http://servidor.exemplo:8080", "username": "u", "password": "p"}]}
        """))

        let result = await server.api.playlists(deviceId: credentials.id, secret: credentials.secret)

        let answer = try #require(result.value)
        #expect(answer.active)
        #expect(answer.expiresAt == parseServerTime("2027-11-13T02:59:59Z"))
        #expect(answer.serverTime == parseServerTime("2026-11-12T17:30:00Z"))
        #expect(answer.partner == true)
        #expect(answer.playlists.map(\.id) == [7])
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://\(server.host)/v1/device/playlists")
        #expect(request.headers["X-Device-Id"] == "7c:2e:9a:41:d0:b6")
        #expect(request.headers["X-Device-Secret"] == credentials.secret)
        #expect(request.body.isEmpty)
        #expect(addressIsClean(request))
    }

    @Test("código de ativação: vai no corpo, com o ID e o segredo nos cabeçalhos")
    func activateWithCode() async throws {
        server.willAnswer(.response(status: 200, body: #"{"ok": true, "active": true, "days": 30}"#))

        let result = await server.api.activateWithCode(deviceId: credentials.id, secret: credentials.secret, code: "ABCDEFGHJKMN")

        #expect(result.value == CodeAnswer(days: 30))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://\(server.host)/v1/device/activate-code")
        #expect(request.json == ["code": "ABCDEFGHJKMN"])
        #expect(request.headers["X-Device-Id"] == "7c:2e:9a:41:d0:b6")
        #expect(request.headers["X-Device-Secret"] == credentials.secret)
        #expect(addressIsClean(request, code: "ABCDEFGHJKMN"))
    }

    @Test("desconectar do painel: um pedido com o corpo vazio")
    func unlink() async throws {
        server.willAnswer(.response(status: 200, body: #"{"ok": true, "unlinked": true, "partner": false}"#))

        let result = await server.api.unlink(deviceId: credentials.id, secret: credentials.secret)

        #expect(result.value == UnlinkAnswer(unlinked: true))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://\(server.host)/v1/device/unlink")
        #expect(String(decoding: request.body, as: UTF8.self) == "{}")
        #expect(request.headers["X-Device-Secret"] == credentials.secret)
        #expect(addressIsClean(request))
    }

    @Test("ping: não leva nada do aparelho")
    func ping() async throws {
        let result = await server.api.ping()

        #expect(result.value != nil)
        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://\(server.host)/v1/ping")
        #expect(request.headers["X-Device-Id"] == nil)
        #expect(request.headers["X-Device-Secret"] == nil)
        #expect(request.body.isEmpty)
    }

    // MARK: - As respostas

    @Test("recusa (4xx): o número e o nome do motivo chegam à lógica")
    func refused() async {
        server.willAnswer(
            .response(status: 404, body: #"{"error": "invalid_code"}"#),
            .response(status: 409, body: #"{"error": "no_credits", "detail": "x"}"#),
            .response(status: 403, body: #"{"error": "device_blocked"}"#),
            .response(status: 429, body: "Too Many Requests"),
            .response(status: 401, body: #"{"error": ""}"#),
            .response(status: 400, body: "")
        )
        let api = server.api
        func send() async -> ApiResult<CodeAnswer> {
            await api.activateWithCode(deviceId: credentials.id, secret: credentials.secret, code: "ABCDEFGHJKMN")
        }

        let invalid = await send()
        #expect(invalid.refusedStatus == 404)
        #expect(invalid.refusedError == "invalid_code")
        let noCredits = await send()
        #expect(noCredits.refusedStatus == 409)
        #expect(noCredits.refusedError == "no_credits")
        let blocked = await send()
        #expect(blocked.refusedStatus == 403)
        #expect(blocked.refusedError == "device_blocked")
        // Recusa sem um motivo que dê para ler: só o número.
        let tooMany = await send()
        #expect(tooMany.refusedStatus == 429)
        #expect(tooMany.refusedError == nil)
        let emptyName = await send()
        #expect(emptyName.refusedStatus == 401)
        #expect(emptyName.refusedError == nil)
        let emptyBody = await send()
        #expect(emptyBody.refusedStatus == 400)
        #expect(emptyBody.refusedError == nil)
    }

    @Test("sem resposta que sirva: sem internet, servidor reiniciando e resposta que não é do contrato")
    func unavailable() async {
        server.willAnswer(
            .noConnection,
            .response(status: 500, body: #"{"error": "server_error"}"#),
            .response(status: 502, body: "<html>Bad Gateway</html>"),
            // A página de entrada de uma rede Wi-Fi responde 200 com outra coisa.
            .response(status: 200, body: "<html>Entre na rede</html>"),
            .response(status: 200, body: #"{"playlists": []}"#),
            .response(status: 200, body: #"{"active": true, "expires_at": "amanhã"}"#),
            .response(status: 204, body: "")
        )
        let api = server.api

        for _ in 0..<7 {
            let result = await api.playlists(deviceId: credentials.id, secret: credentials.secret)
            #expect(result.isUnavailable)
        }
        #expect(server.requests.count == 7)
    }

    @Test("redirecionamento: a resposta não é aceita (o segredo não vai atrás de outro endereço)")
    func redirectAnswer() async {
        server.willAnswer(
            .response(status: 301, body: "", headers: ["Location": "https://outro.exemplo.test/v1/device/playlists"]),
            .response(status: 302, body: "", headers: ["Location": "https://outro.exemplo.test/v1/device/register"])
        )
        let api = server.api

        #expect(await api.playlists(deviceId: credentials.id, secret: credentials.secret).isUnavailable)
        #expect(await api.register(credentials, platform: "ios", appVersion: "0.1.0").isUnavailable)
        // Nada foi pedido a outro endereço.
        #expect(server.requests.count == 2)
    }

    @Test("a sessão do app recusa seguir qualquer redirecionamento")
    func noRedirects() async throws {
        let session = HttpSiteApi.makeSession(protocolClasses: [StubProtocol.self])
        let delegate = try #require(session.delegate as? NoRedirects)
        let here = try #require(URL(string: "https://\(server.host)/v1/device/playlists"))
        let there = try #require(URL(string: "https://outro.exemplo.test/v1/device/playlists"))
        let response = try #require(HTTPURLResponse(url: here, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": there.absoluteString]))
        let task = session.dataTask(with: here)

        let followed: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: there)) { request in
                continuation.resume(returning: request)
            }
        }

        #expect(followed == nil)
        task.cancel()
        #expect(server.requests.isEmpty)
    }

    @Test("resposta grande demais não é lida")
    func tooLarge() async {
        let limit = HttpSiteApi.maxAnswerBytes
        server.willAnswer(
            .response(status: 200, body: String(repeating: " ", count: limit)),
            .response(status: 200, body: String(repeating: " ", count: limit + 1)),
            .response(status: 404, body: String(repeating: " ", count: limit + 1))
        )
        let api = server.api

        #expect(await api.ping().value != nil)
        #expect(await api.ping().isUnavailable)
        #expect(await api.ping().isUnavailable)
    }

    @Test("endereço da API que não é um endereço: sem resposta, e nada sai do aparelho")
    func badBaseAddress() async {
        let api = HttpSiteApi(
            baseURL: "isto não é um endereço",
            userAgent: "PlazvoPlayer/0.1.0 (ios)",
            session: HttpSiteApi.makeSession(protocolClasses: [StubProtocol.self])
        )

        #expect(await api.ping().isUnavailable)
        #expect(server.requests.isEmpty)
    }

    @Test("a sessão do app não guarda respostas nem cookies")
    func sessionKeepsNothing() async throws {
        server.willAnswer(.response(status: 200, body: "{}", headers: ["Set-Cookie": "visita=1; Path=/"]))
        let api = server.api

        _ = await api.ping()
        _ = await api.ping()

        #expect(server.requests.count == 2)
        #expect(server.requests[1].headers["Cookie"] == nil)
        let configuration = HttpSiteApi.makeSession().configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == HttpSiteApi.requestTimeout)
    }
}
