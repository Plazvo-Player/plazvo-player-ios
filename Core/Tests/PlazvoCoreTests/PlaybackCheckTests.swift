import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PlazvoCore

@Suite("Conferência de um vídeo que não abriu")
struct PlaybackCheckTests {
    let server = StubServer()

    /// A conferência de verdade, apontada para a internet de mentira.
    private var check: PlaybackCheck {
        PlaybackCheck(userAgent: "PlazvoPlayer/0.2.0 (iOS 18.1)", configure: { $0.protocolClasses = [StubProtocol.self] })
    }

    private func link(_ path: String = "/aulas/aula-3.mkv") -> String {
        "http://usuario:senha@\(server.host):8080\(path)"
    }

    // MARK: - Link

    @Test("link: pede o começo do vídeo, apresentando-se como o app")
    func request() async throws {
        server.willAnswer(.response(status: 404, body: ""))

        _ = await check.failure(of: .link, address: link("/aulas/aula-3.mkv?token=abc"))

        let request = try #require(server.requests.first)
        #expect(server.requests.count == 1)
        #expect(request.method == "GET")
        #expect(request.url.path == "/aulas/aula-3.mkv")
        #expect(request.url.query == "token=abc")
        #expect(request.headers["User-Agent"] == "PlazvoPlayer/0.2.0 (iOS 18.1)")
        #expect(request.headers["Range"] == "bytes=0-")
        #expect(request.body.isEmpty)
    }

    @Test("link: a conferência não guarda nem manda cookies, e não guarda cópia das respostas")
    func keepsNothing() {
        let configuration = PlaybackCheck.sessionConfiguration()
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == PlaybackCheck.timeout)
    }

    @Test("link: quem pediu a conferência desistiu (o vídeo foi fechado): o pedido é cancelado na hora")
    func cancelled() async {
        server.willAnswer(.silence)
        let check = self.check
        let address = link()
        let started = Date()
        let asking = Task { await check.failure(of: .link, address: address) }
        #expect(await eventually { !self.server.requests.isEmpty })

        asking.cancel()

        // Sem o cancelamento, a resposta só viria no fim do tempo de espera (8 segundos).
        #expect(await asking.value == .network)
        #expect(Date().timeIntervalSince(started) < 4)

        // Desistência antes de começar: o pedido nem sai do aparelho.
        let before = server.requests.count
        let late = Task {
            while !Task.isCancelled { await Task.yield() }
            return await check.failure(of: .link, address: address)
        }
        late.cancel()
        #expect(await late.value == .network)
        #expect(server.requests.count == before)
    }

    @Test("link: o servidor respondeu com um número de erro")
    func refused() async {
        for status in [400, 401, 403, 404, 410, 429, 500, 502, 503] {
            server.willAnswer(.response(status: status, body: "erro"))
            #expect(await check.failure(of: .link, address: link()) == .http(status: status), "resposta \(status)")
        }
    }

    @Test("link: o endereço responde, mas o que vem não é um vídeo que o reprodutor toque")
    func answersButDoesNotPlay() async {
        for status in [200, 206] {
            server.willAnswer(.response(status: status, body: "<html>não é um vídeo</html>"))
            #expect(await check.failure(of: .link, address: link()) == .format, "resposta \(status)")
        }
    }

    @Test("link: sem resposta do endereço")
    func noAnswer() async {
        server.willAnswer(.noConnection)
        #expect(await check.failure(of: .link, address: link()) == .network)
        // Servidor que ninguém conhece.
        #expect(await check.failure(of: .link, address: "http://nao-existe.exemplo.test/a.mp4") == .network)
    }

    @Test("link: a conferência não espera o vídeo inteiro chegar")
    func doesNotDownloadTheVideo() async {
        server.willAnswer(.endlessBody(status: 200))
        let started = Date()
        #expect(await check.failure(of: .link, address: link("/ao-vivo.ts")) == .format)
        #expect(Date().timeIntervalSince(started) < 4)

        server.willAnswer(.endlessBody(status: 403))
        #expect(await check.failure(of: .link, address: link("/ao-vivo.ts")) == .http(status: 403))
    }

    @Test("link: o que não é um endereço http ou https nem sai do aparelho")
    func notAnAddress() async {
        #expect(await check.failure(of: .link, address: "") == .network)
        #expect(await check.failure(of: .link, address: "meu video") == .network)
        #expect(await check.failure(of: .link, address: "ftp://\(server.host)/a.mp4") == .network)
        #expect(await check.failure(of: .link, address: "file:///etc/hosts") == .network)
        #expect(server.requests.isEmpty)
    }

    // MARK: - Arquivo e demonstração

    @Test("arquivo: se está lá, o problema é o formato; se sumiu, não foi encontrado")
    func file() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plazvo-teste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("Férias na praia.mp4")
        try Data("não é um vídeo".utf8).write(to: video)

        #expect(await check.failure(of: .file, address: video.absoluteString) == .format)

        try FileManager.default.removeItem(at: video)
        #expect(await check.failure(of: .file, address: video.absoluteString) == .notFound)
        #expect(await check.failure(of: .file, address: "") == .notFound)
        // Um link no lugar de um arquivo não é um arquivo.
        #expect(await check.failure(of: .file, address: link()) == .notFound)
        #expect(server.requests.isEmpty)
    }

    @Test("vídeo de demonstração: não há o que conferir")
    func demo() async {
        #expect(await check.failure(of: .demo, address: "file:///app/demo_video.mp4") == .unknown)
        #expect(server.requests.isEmpty)
    }
}
