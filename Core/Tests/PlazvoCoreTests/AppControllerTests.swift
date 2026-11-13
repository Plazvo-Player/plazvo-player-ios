import Foundation
import Testing
@testable import PlazvoCore

/// A área de transferência de mentira: guarda o que o app mandou copiar.
final class TestClipboard {
    var texts: [String] = []
}

/// Guarda os motores de vídeo criados, um por vídeo aberto.
@MainActor
final class EngineBox {
    var engines: [FakeEngine] = []
}

/// Tudo o que um teste das telas precisa, já ligado: servidor de mentira, cofre, lógica, vídeo de
/// mentira e o controle das telas, com um relógio que o teste escolhe.
@MainActor
final class AppBench {
    let clock: TestClock
    let site: FakeSite
    let secure = InMemorySecureStore()
    let clipboard = TestClipboard()
    let identity: DeviceIdentityStore
    let lists: SiteLists
    /// Onde a lista de vídeos recentes fica guardada.
    let recentsCopy: InMemoryCopyStore
    let recents: RecentMediaStore
    let access = FakeAccess()
    let diagnosis = FakeDiagnosis()
    let app: AppController
    private(set) var changes: [AppState] = []

    /// - Parameters:
    ///   - storedRecents: o que a lista de recentes já traz guardado.
    ///   - automaticEngine: o motor de vídeo de mentira abre e anda sozinho.
    init(
        now: String = "2026-10-05T19:00:00Z",
        random: RandomSource = predictableRandom(),
        noticeSeconds: Double? = nil,
        storedRecents: Data? = nil,
        automaticEngine: Bool = false
    ) {
        let clock = TestClock(now)
        let clipboard = self.clipboard
        self.clock = clock
        site = FakeSite(now: { clock.now })
        identity = DeviceIdentityStore(store: secure, random: random)
        lists = SiteLists(api: site, identityStore: identity, copy: InMemoryCopyStore(), platform: "ios", appVersion: "0.1.0", now: { clock.now })
        recentsCopy = InMemoryCopyStore(data: storedRecents)
        recents = RecentMediaStore(storage: recentsCopy, now: { clock.now })
        let box = EngineBox()
        let playback = PlaybackParts(
            makeEngine: {
                let engine = FakeEngine()
                engine.automatic = automaticEngine
                box.engines.append(engine)
                return engine
            },
            access: access,
            diagnosis: diagnosis,
            tickSeconds: nil
        )
        engineBox = box
        app = AppController(
            identityStore: identity,
            siteLists: lists,
            recentMedia: recents,
            playback: playback,
            copyText: { clipboard.texts.append($0) },
            noticeSeconds: noticeSeconds
        )
        app.onChange = { [unowned self] in self.changes.append($0) }
    }

    private let engineBox: EngineBox

    /// O motor do vídeo aberto por último.
    var engine: FakeEngine? { engineBox.engines.last }
    var engineCount: Int { engineBox.engines.count }

    var state: AppState { app.state }

    func forgetChanges() {
        changes = []
    }
}

@MainActor
@Suite("Telas: o que está por trás delas")
struct AppControllerTests {
    let bench = AppBench()

    // MARK: - Abertura

    @Test("abrir o app: cria o ID e a chave, consulta o servidor e mostra que o aparelho não está ativo")
    func start() async throws {
        #expect(bench.state == AppState())

        await bench.app.start()

        let identity = try #require(bench.state.identity)
        #expect(DeviceIdGenerator.isValidId(identity.id))
        #expect(DeviceIdGenerator.isValidKey(identity.key))
        #expect(bench.state.site == SiteListsState(status: .inactive, partner: false))
        #expect(bench.state.screen == .home)
        #expect(bench.state.dialog == nil)
        #expect(await bench.site.calls == ["register", "playlists"])

        // Só a primeira chamada faz efeito.
        await bench.app.start()
        #expect(await bench.site.calls == ["register", "playlists"])
    }

    @Test("cofre que não pôde ser lido: a tela fica sem o ID e o Recarregar tenta de novo")
    func unreadableVault() async {
        bench.secure.readFailure = SecureStoreError(status: -25308)

        await bench.app.start()

        #expect(bench.state.identity == nil)
        #expect(bench.state.site.problem == .offline)
        #expect(await bench.site.calls.isEmpty)
        // Sem ID não há o que copiar.
        bench.app.copy(.id)
        #expect(bench.clipboard.texts.isEmpty)
        #expect(bench.state.notice == nil)

        bench.secure.readFailure = nil
        await bench.app.reload()

        #expect(bench.state.identity != nil)
        #expect(bench.state.site.status == .inactive)
        #expect(bench.state.site.problem == nil)
    }

    // MARK: - Telas e caixas

    @Test("Conta e Voltar: a seta fecha primeiro a caixa aberta e depois volta à tela inicial")
    func navigation() async {
        await bench.app.start()

        bench.app.openAccount()
        #expect(bench.state.screen == .account)

        bench.app.openCodeDialog()
        #expect(bench.state.dialog == .code)
        bench.app.back()
        #expect(bench.state.dialog == nil)
        #expect(bench.state.screen == .account)

        bench.app.back()
        #expect(bench.state.screen == .home)

        bench.app.openNewKeyDialog()
        #expect(bench.state.dialog == .newKey)
        bench.app.closeDialog()
        #expect(bench.state.dialog == nil)
    }

    // MARK: - Mídia e vídeo

    @Test("Mídia e Abrir link: a seta volta uma tela de cada vez")
    func mediaNavigation() async {
        await bench.app.start()
        #expect(bench.state.recents.isEmpty)
        #expect(bench.state.playing == nil)
        #expect(bench.app.player == nil)

        bench.app.openMedia()
        #expect(bench.state.screen == .media)
        bench.app.openLinkScreen()
        #expect(bench.state.screen == .openLink)

        bench.app.back()
        #expect(bench.state.screen == .media)
        bench.app.back()
        #expect(bench.state.screen == .home)
        // Mídia e Conta voltam direto para a tela inicial.
        bench.app.openMedia()
        bench.app.openAccount()
        bench.app.back()
        #expect(bench.state.screen == .home)
    }

    @Test("vídeo de demonstração: abre o reprodutor por cima da Mídia; voltar fecha o vídeo e fica na Mídia")
    func demoVideo() async throws {
        await bench.app.start()
        bench.app.openMedia()

        bench.app.playDemo(title: "Big Buck Bunny (trecho)")

        let request = PlaybackRequest(kind: .demo, uri: "", title: "Big Buck Bunny (trecho)")
        #expect(bench.state.playing == request)
        #expect(bench.state.screen == .media)
        let player = try #require(bench.app.player)
        #expect(player.request == request)
        #expect(player.state.title == "Big Buck Bunny (trecho)")
        let engine = try #require(bench.engine)
        #expect(engine.calls == ["open \(FakeAccess.demoAddress) @0"])

        bench.app.back()

        #expect(bench.state.playing == nil)
        #expect(bench.app.player == nil)
        #expect(bench.state.screen == .media)
        #expect(engine.calls == ["open \(FakeAccess.demoAddress) @0", "stop"])
        #expect(bench.access.closes == 1)
        // O vídeo de demonstração não entra nos recentes.
        #expect(bench.state.recents.isEmpty)
    }

    @Test("abrir link: o endereço é conferido, o vídeo abre e, depois dele, voltar leva para a Mídia")
    func openLink() async throws {
        await bench.app.start()
        bench.app.openMedia()
        bench.app.openLinkScreen()
        #expect(bench.app.lastLink.isEmpty)

        let opened = bench.app.openLink("  exemplo.com/aulas/aula 3.mkv ")

        #expect(opened)
        #expect(bench.state.playing == PlaybackRequest(kind: .link, uri: "http://exemplo.com/aulas/aula%203.mkv", title: "aula 3.mkv"))
        #expect(bench.state.screen == .media)
        #expect(!bench.state.linkInvalid)
        #expect(bench.app.lastLink == "http://exemplo.com/aulas/aula%203.mkv")
        #expect(bench.engine?.calls == ["open http://exemplo.com/aulas/aula%203.mkv @0"])

        bench.app.closePlayer()
        #expect(bench.state.playing == nil)
        #expect(bench.state.screen == .media)
    }

    @Test("abrir link com endereço que não vale: a tela avisa, nada abre, e mexer no campo tira o aviso")
    func openInvalidLink() async {
        await bench.app.start()
        bench.app.openMedia()
        bench.app.openLinkScreen()

        let opened = bench.app.openLink("meu video")

        #expect(!opened)
        #expect(bench.state.linkInvalid)
        #expect(bench.state.screen == .openLink)
        #expect(bench.state.playing == nil)
        #expect(bench.app.player == nil)
        #expect(bench.engineCount == 0)
        #expect(bench.app.lastLink.isEmpty)

        bench.app.linkEdited()
        #expect(!bench.state.linkInvalid)

        // O aviso de uma tentativa anterior não volta quando a tela abre de novo.
        bench.app.openLink("ftp://exemplo.com/a.mp4")
        #expect(bench.state.linkInvalid)
        bench.app.back()
        bench.app.openLinkScreen()
        #expect(!bench.state.linkInvalid)
    }

    @Test("o link que tocou não volta para o campo; o que não abriu volta, para corrigir")
    func lastLinkOnlyAfterAFailure() async throws {
        await bench.app.start()
        let secret = "http://usuario:senha@exemplo.com:8080/a.mp4"

        // Não abriu: o endereço fica para o usuário corrigir.
        bench.diagnosis.willAnswer(.network)
        bench.app.openLink(secret)
        try #require(bench.engine).emit(.failed)
        #expect(await eventually { self.bench.app.player?.state.problem != nil })
        bench.app.closePlayer()
        #expect(bench.app.lastLink == secret)
        #expect(bench.state.recents.isEmpty)

        // Abriu, mas nem chegou a tocar (o usuário saiu antes): também fica.
        bench.app.openLink(secret)
        try #require(bench.engine).emit(.opening)
        bench.app.closePlayer()
        #expect(bench.app.lastLink == secret)

        // Tocou: está nos recentes (só com o nome e o servidor à mostra) e sai do campo.
        bench.app.openLink(secret)
        try #require(bench.engine).startPlaying()
        #expect(bench.app.lastLink == secret)
        bench.app.closePlayer()
        #expect(bench.app.lastLink.isEmpty)
        #expect(bench.state.recents.map(\.title) == ["a.mp4"])

        // Outro link tentado depois, sem tocar, e um vídeo que toca no lugar dele: o link tentado fica.
        bench.app.openLink("http://exemplo.com/outro.mp4")
        bench.app.playDemo(title: "Demonstração")
        try #require(bench.engine).startPlaying(durationMs: 21_600)
        bench.app.closePlayer()
        #expect(bench.app.lastLink == "http://exemplo.com/outro.mp4")
    }

    @Test("um vídeo novo no lugar de um link que tocou: o endereço do link também sai do campo")
    func lastLinkClearedWhenReplaced() async throws {
        await bench.app.start()
        bench.app.openLink("http://usuario:senha@exemplo.com:8080/a.mp4")
        try #require(bench.engine).startPlaying()

        bench.app.playDemo(title: "Demonstração")

        #expect(bench.app.lastLink.isEmpty)
    }

    @Test("o mesmo link aberto de novo por cima dele mesmo: vale a tentativa nova")
    func sameLinkOpenedOverItself() async throws {
        await bench.app.start()
        let link = "http://usuario:senha@exemplo.com:8080/a.mp4"
        bench.app.openLink(link)
        try #require(bench.engine).startPlaying()

        // A tentativa nova ainda não tocou: o endereço fica, para corrigir se ela falhar.
        bench.app.openLink(link)
        #expect(bench.app.lastLink == link)
        #expect(bench.engineCount == 2)

        // E some quando ela toca e o vídeo é fechado.
        try #require(bench.engine).startPlaying()
        bench.app.closePlayer()
        #expect(bench.app.lastLink.isEmpty)
    }

    @Test("Limpar os recentes apaga também o último link tentado")
    func clearingRecentsForgetsTheLastLink() async {
        await bench.app.start()
        bench.app.openLink("http://usuario:senha@exemplo.com:8080/a.mp4")
        bench.app.closePlayer()
        #expect(!bench.app.lastLink.isEmpty)

        bench.app.clearRecents()

        #expect(bench.app.lastLink.isEmpty)
    }

    @Test("o último link tentado fica fora do estado das telas")
    func lastLinkStaysOutOfState() async {
        await bench.app.start()
        bench.app.openLink("http://usuario:senha@exemplo.com:8080/a.mp4")
        #expect(bench.app.lastLink == "http://usuario:senha@exemplo.com:8080/a.mp4")
        var dumped = ""
        dump(bench.state, to: &dumped)
        #expect(!"\(bench.state)".contains("senha"))
        #expect(!String(reflecting: bench.state).contains("senha"))
        #expect(!dumped.contains("senha"))
        #expect(!dumped.contains("exemplo.com"))
    }

    @Test("arquivo do aparelho: abre, entra nos recentes quando abre de verdade, e reabre de onde parou")
    func fileAndRecents() async throws {
        await bench.app.start()
        bench.app.openMedia()
        let access = Data([4, 2])

        bench.app.playFile(uri: "file:///videos/F%C3%A9rias.mp4", title: "Férias.mp4", access: access)

        let request = PlaybackRequest(kind: .file, uri: "file:///videos/F%C3%A9rias.mp4", title: "Férias.mp4", access: access)
        #expect(bench.state.playing == request)
        #expect(bench.access.asked == [request])
        #expect(bench.state.recents.isEmpty)

        let engine = try #require(bench.engine)
        engine.startPlaying(durationMs: 600_000)
        #expect(bench.state.recents.map(\.title) == ["Férias.mp4"])
        engine.advance(to: 125_000)
        bench.app.closePlayer()

        let recent = try #require(bench.state.recents.first)
        #expect(recent.positionMs == 125_000)
        #expect(recent.durationMs == 600_000)
        #expect(recent.access == access)

        // Tocar no recente: outro motor, o mesmo pedido, do ponto guardado.
        bench.app.openRecent(recent)

        #expect(bench.engineCount == 2)
        #expect(bench.state.playing == request)
        #expect(bench.engine?.calls == ["open file:///videos/F%C3%A9rias.mp4 @125000"])
    }

    @Test("um vídeo novo com outro aberto: o anterior é fechado antes")
    func newVideoClosesThePrevious() async throws {
        await bench.app.start()
        bench.app.playDemo(title: "Demonstração")
        let first = try #require(bench.engine)
        let firstPlayer = try #require(bench.app.player)

        bench.app.openLink("http://exemplo.com/a.mp4")

        #expect(first.calls.last == "stop")
        #expect(bench.engineCount == 2)
        #expect(bench.app.player !== firstPlayer)
        #expect(bench.state.playing?.kind == .link)
        #expect(bench.access.closes == 1)
    }

    @Test("recentes: a lista guardada aparece ao abrir o app, e Limpar esvazia")
    func recents() async throws {
        let stored = try JSONEncoder().encode(DemoScene.exampleRecents(now: parseServerTime("2026-11-12T17:30:00Z")!))
        let bench = AppBench(storedRecents: stored)
        #expect(bench.state.recents.map(\.title) == ["Aniversário da Ana.mp4", "aula-de-violao-03.mkv", "passeio-na-praia.mov"])

        bench.app.clearRecents()

        #expect(bench.state.recents.isEmpty)
        #expect(bench.recentsCopy.data == nil)
    }

    @Test("voltar: primeiro a caixa aberta, depois o vídeo, depois a tela")
    func backOrder() async {
        await bench.app.start()
        bench.app.openMedia()
        bench.app.playDemo(title: "Demonstração")

        bench.app.back()
        #expect(bench.state.playing == nil)
        #expect(bench.state.screen == .media)
        bench.app.back()
        #expect(bench.state.screen == .home)
        // Sem vídeo aberto, fechar o reprodutor não faz nada.
        bench.forgetChanges()
        bench.app.closePlayer()
        #expect(bench.changes.isEmpty)
    }

    @Test("vídeo que não abre: a falha aparece no reprodutor, e Voltar sai dele")
    func failedVideo() async throws {
        let bench = AppBench(automaticEngine: true)
        bench.diagnosis.willAnswer(.http(status: 404))
        await bench.app.start()
        bench.app.openMedia()
        bench.app.openLinkScreen()

        bench.app.openLink(DemoScene.deadLink)

        let player = try #require(bench.app.player)
        #expect(await eventually { player.state.problem != nil })
        #expect(player.state.problem == PlaybackProblem(message: TextRef("player_error_http", ["404"]), code: 2004))
        #expect(bench.state.recents.isEmpty)

        bench.app.closePlayer()
        #expect(bench.state.playing == nil)
        #expect(bench.state.screen == .media)
        // O endereço fica guardado para o usuário corrigir.
        #expect(bench.app.lastLink == DemoScene.deadLink)
    }

    // MARK: - Código de ativação

    @Test("código aceito: a caixa fecha, o aparelho fica ativo e a Conta sabe por quantos dias")
    func codeAccepted() async {
        await bench.site.addCode("ABCD-EFGH-JKMN", days: 30)
        await bench.app.start()
        bench.app.openAccount()
        bench.app.openCodeDialog()
        bench.forgetChanges()

        await bench.app.activateWithCode("ABCDEFGHJKMN")

        #expect(bench.state.dialog == nil)
        #expect(bench.state.screen == .account)
        #expect(bench.state.codeResult == .activated(days: 30))
        #expect(!bench.state.activating)
        #expect(bench.state.site.status == .active)
        #expect(bench.state.site.expiresAt == parseServerTime("2026-11-04T19:00:00Z"))
        // Durante o pedido a tela sabe que há um código a caminho, e o fim chega de uma vez só.
        #expect(bench.changes.first?.activating == true)
        #expect(!bench.changes.contains { !$0.activating && $0.codeResult != nil && $0.dialog == .code })
    }

    @Test("código comum e, com o app ainda aberto, o aparelho entra numa parceria: a Conta deixa de falar em dias")
    func codeThenSponsorship() async {
        await bench.site.addCode("ABCD-EFGH-JKMN", days: 30)
        await bench.app.start()
        bench.app.openAccount()
        bench.app.openCodeDialog()
        await bench.app.activateWithCode("ABCDEFGHJKMN")
        #expect(bench.state.codeResult == .activated(days: 30))
        #expect(ScreenTexts.activated(days: 30, sponsored: bench.state.site.sponsored) == TextRef("code_activated_days.other", ["30"]))

        // O aparelho passa a ser de uma parceria, e o usuário toca em Recarregar.
        await bench.site.setSetup { $0.sponsored = true }
        await bench.app.reload()

        #expect(bench.state.site.sponsored)
        #expect(ScreenTexts.activeUntil(bench.state.site, datePattern: "dd/MM/yyyy") == TextRef("playlists_active_partner"))
        // O resultado do código continua guardado, mas a linha dele na Conta já não diz os dias.
        #expect(bench.state.codeResult == .activated(days: 30))
        #expect(ScreenTexts.activated(days: 30, sponsored: bench.state.site.sponsored) == TextRef("code_activated"))
    }

    @Test("código recusado: a caixa continua aberta com o motivo; fechar a caixa descarta o aviso")
    func codeRefused() async {
        await bench.app.start()
        bench.app.openAccount()
        bench.app.openCodeDialog()

        await bench.app.activateWithCode("ZZZZZZZZZZZZ")

        #expect(bench.state.dialog == .code)
        #expect(bench.state.codeResult == .failed(.invalid, status: 404))
        #expect(!bench.state.activating)
        #expect(bench.state.site.status == .inactive)

        bench.app.closeDialog()
        #expect(bench.state.dialog == nil)
        #expect(bench.state.codeResult == nil)
    }

    @Test("caixa fechada no meio do pedido: o aviso da falha não volta quando a caixa abre de novo")
    func codeDialogClosedWhileSending() async {
        await bench.app.start()
        bench.app.openCodeDialog()
        await bench.site.hold()
        let sending = Task { await bench.app.activateWithCode("ZZZZZZZZZZZZ") }
        #expect(await eventually { bench.state.activating })

        bench.app.closeDialog()
        await bench.site.release()
        await sending.value

        #expect(bench.state.dialog == nil)
        #expect(bench.state.codeResult == .failed(.invalid, status: 404))
        bench.app.openCodeDialog()
        #expect(bench.state.codeResult == nil)
    }

    @Test("um código por vez: o segundo toque em Ativar não vira um segundo pedido")
    func oneCodeAtATime() async {
        await bench.site.addCode("ABCDEFGHJKMN", days: 30)
        await bench.app.start()
        bench.app.openCodeDialog()
        await bench.site.hold()
        let first = Task { await bench.app.activateWithCode("ABCDEFGHJKMN") }
        #expect(await eventually { bench.state.activating })

        await bench.app.activateWithCode("ABCDEFGHJKMN")
        await bench.site.release()
        await first.value

        #expect(await bench.site.calls.filter { $0 == "activate-code" }.count == 1)
        #expect(bench.state.codeResult == .activated(days: 30))
    }

    // MARK: - Nova chave

    @Test("nova chave: a chave muda, o ID não, e a chave nova chega ao servidor")
    func newKey() async throws {
        await bench.app.start()
        let before = try #require(bench.state.identity)
        bench.app.openNewKeyDialog()

        await bench.app.confirmNewKey()

        let after = try #require(bench.state.identity)
        #expect(bench.state.dialog == nil)
        #expect(after.id == before.id)
        #expect(after.key != before.key)
        #expect(DeviceIdGenerator.isValidKey(after.key))
        #expect(await bench.site.devices[after.id]?.key == after.key)
        #expect(bench.state.notice == nil)
    }

    @Test("nova chave que o cofre não grava: a chave continua a mesma e a tela avisa")
    func newKeyNotSaved() async throws {
        await bench.app.start()
        let before = try #require(bench.state.identity)
        let calls = await bench.site.calls
        bench.secure.writeFailure = SecureStoreError(status: -25299)
        bench.app.openNewKeyDialog()

        await bench.app.confirmNewKey()

        #expect(bench.state.dialog == nil)
        #expect(bench.state.identity == before)
        #expect(bench.state.notice == Notice(TextRef("new_key_failed"), done: false))
        // Nada novo foi dito ao servidor.
        #expect(await bench.site.calls == calls)
    }

    @Test("nova chave: o segundo toque seguido no botão não troca a chave outra vez")
    func newKeyTappedTwice() async throws {
        await bench.app.start()
        bench.app.openNewKeyDialog()
        await bench.app.confirmNewKey()
        let first = try #require(bench.state.identity)
        let calls = await bench.site.calls

        // O segundo toque chega com a caixa já fechada.
        await bench.app.confirmNewKey()

        #expect(bench.state.identity == first)
        #expect(await bench.site.calls == calls)
        #expect(bench.state.notice == nil)
    }

    // MARK: - Desconectar do painel

    @Test("desconectar do painel: o aparelho sai do painel e a caixa mostra o resultado até ser fechada")
    func unlink() async throws {
        await bench.app.start()
        let id = try #require(bench.state.identity?.id)
        await bench.site.change(id) { device in
            device.active = true
            device.expiresAt = "2027-10-02T22:40:23Z"
            device.partner = true
        }
        await bench.app.reload()
        #expect(bench.state.site.partner == true)
        bench.app.openUnlinkDialog()
        bench.forgetChanges()

        await bench.app.unlink()

        #expect(bench.state.unlinkResult == .unlinked)
        #expect(!bench.state.unlinking)
        #expect(bench.state.dialog == .unlink)
        #expect(bench.state.site.partner == false)
        #expect(bench.state.site.status == .active)
        #expect(bench.changes.first?.unlinking == true)

        bench.app.closeDialog()
        #expect(bench.state.dialog == nil)
        #expect(bench.state.unlinkResult == nil)
    }

    @Test("desconectar sem resposta do servidor: a caixa diz que não deu, e abrir de novo começa do zero")
    func unlinkOffline() async {
        await bench.app.start()
        await bench.site.setDown(true)
        bench.app.openUnlinkDialog()

        await bench.app.unlink()

        #expect(bench.state.unlinkResult == .failed(.offline, status: nil))
        bench.app.openUnlinkDialog()
        #expect(bench.state.unlinkResult == nil)
        #expect(bench.state.dialog == .unlink)
    }

    // MARK: - Copiar

    @Test("copiar: só o ID ou a chave vão para a área de transferência, e a tela mostra qual foi")
    func copy() async throws {
        await bench.app.start()
        let credentials = try bench.identity.credentials()

        bench.app.copy(.key)
        #expect(bench.clipboard.texts == [credentials.key])
        #expect(bench.state.copied == .key)
        #expect(bench.state.notice == Notice(TextRef("device_key_copied"), done: true))

        bench.app.copy(.id)
        #expect(bench.clipboard.texts == [credentials.key, credentials.id])
        #expect(bench.state.copied == .id)
        #expect(bench.state.notice == Notice(TextRef("device_id_copied"), done: true))

        // O segredo do aparelho nunca sai por aqui.
        #expect(!bench.clipboard.texts.contains { $0.contains(credentials.secret) })
    }

    @Test("o aviso de copiado some sozinho, e o botão volta a mostrar os dois quadradinhos")
    func noticeEnds() async {
        let bench = AppBench(noticeSeconds: 0.05)
        await bench.app.start()

        bench.app.copy(.id)
        #expect(bench.state.notice != nil)

        #expect(await eventually { bench.state.notice == nil && bench.state.copied == nil })
    }

    @Test("copiar de novo antes de o aviso sumir: vale o tempo do último toque")
    func noticeRestarts() async throws {
        let bench = AppBench(noticeSeconds: 2)
        await bench.app.start()

        bench.app.copy(.id)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        bench.app.copy(.key)
        try await Task.sleep(nanoseconds: 1_200_000_000)

        // O fim do primeiro aviso (aos 2 s) não apaga o segundo.
        #expect(bench.state.copied == .key)
        #expect(await eventually { bench.state.notice == nil })
    }
}
