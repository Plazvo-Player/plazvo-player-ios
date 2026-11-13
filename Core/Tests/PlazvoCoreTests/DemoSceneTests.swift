import Foundation
import Testing
@testable import PlazvoCore

@MainActor
@Suite("Cenas do simulador (fotos das telas)")
struct DemoSceneTests {
    let utc = TimeZone(secondsFromGMT: 0)!

    /// Abre o app numa cena, como a compilação do simulador faz (com o vídeo de mentira, que abre
    /// e anda sozinho).
    private func open(_ scene: DemoScene) async -> AppBench {
        let now = parseServerTime("2026-11-12T14:30:00Z")!
        let bench = AppBench(
            now: "2026-11-12T14:30:00Z",
            random: DemoScene.exampleRandom(),
            storedRecents: scene.storedRecents(now: now),
            automaticEngine: true
        )
        await scene.prepare(bench.site, now: bench.clock.now)
        await bench.app.start()
        await scene.play(on: bench.app, demoTitle: "Big Buck Bunny (trecho)", patience: 5)
        return bench
    }

    @Test("a linha de comando escolhe a cena e se a tela fica deitada")
    func request() {
        let launch = ["PlazvoPlayer", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        #expect(DemoRequest(arguments: launch) == DemoRequest(arguments: []))
        #expect(DemoRequest(arguments: launch).scene == nil)
        #expect(!DemoRequest(arguments: launch).landscape)

        let account = DemoRequest(arguments: launch + ["-PlazvoCena", "conta", "-PlazvoDeitado", "sim"])
        #expect(account.scene == .account)
        #expect(account.landscape)

        #expect(DemoRequest(arguments: ["-PlazvoCena", "nao-existe"]).scene == nil)
        #expect(DemoRequest(arguments: ["-PlazvoCena"]).scene == nil)
        for scene in DemoScene.allCases {
            #expect(DemoRequest(arguments: ["-PlazvoCena", scene.rawValue]).scene == scene)
        }
    }

    @Test("só as cenas que terminam com um campo à espera do usuário esperam pelo teclado")
    func scenesWithKeyboard() {
        #expect(DemoScene.allCases.filter(\.showsKeyboard) == [.code, .wrongCode, .link, .wrongLink])
    }

    @Test("só as cenas do reprodutor terminam com um vídeo aberto")
    func scenesWithPlayer() async {
        #expect(DemoScene.allCases.filter(\.showsPlayer) == [.player, .playerProblem])
        for scene in DemoScene.allCases {
            let bench = await open(scene)
            #expect((bench.state.playing != nil) == scene.showsPlayer, "cena \(scene.rawValue)")
        }
    }

    @Test("a hora das fotos é 14:30 do dia, no fuso do aparelho")
    func photoTime() {
        let night = parseServerTime("2026-11-12T02:10:45Z")!
        #expect(DemoScene.photoTime(on: night, timeZone: utc) == parseServerTime("2026-11-12T14:30:00Z"))
        // Em São Paulo, às 02:10 de Greenwich ainda é o dia 11 (23:10).
        let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!
        #expect(DemoScene.photoTime(on: night, timeZone: saoPaulo) == parseServerTime("2026-11-11T17:30:00Z"))
        #expect(ClockFormatter.timeText(DemoScene.photoTime(timeZone: saoPaulo), timeZone: saoPaulo) == "02:30 PM")
    }

    @Test("o ID e a chave das fotos são os do desenho, e a chave nova é sorteada de verdade")
    func exampleIdentity() async throws {
        let bench = await open(.home)
        #expect(bench.state.identity == DeviceIdentity(id: "7c:2e:9a:41:d0:b6", key: "483920"))

        bench.app.openNewKeyDialog()
        await bench.app.confirmNewKey()

        let after = try #require(bench.state.identity)
        #expect(after.id == "7c:2e:9a:41:d0:b6")
        #expect(after.key != "483920")
        #expect(DeviceIdGenerator.isValidKey(after.key))
    }

    @Test("cenas do aparelho ainda não ativo: tela inicial, Conta e as caixas")
    func inactiveScenes() async {
        let home = await open(.home)
        #expect(home.state.screen == .home)
        #expect(home.state.dialog == nil)
        #expect(home.state.site.status == .inactive)

        let account = await open(.account)
        #expect(account.state.screen == .account)
        #expect(account.state.dialog == nil)

        let code = await open(.code)
        #expect(code.state.screen == .account)
        #expect(code.state.dialog == .code)
        #expect(code.state.codeResult == nil)
        #expect(DemoScene.code.typedCode == DemoScene.exampleCode)
        #expect(await code.site.calls == ["register", "playlists"])

        let newKey = await open(.newKey)
        #expect(newKey.state.screen == .home)
        #expect(newKey.state.dialog == .newKey)
        #expect(DemoScene.newKey.typedCode.isEmpty)
    }

    @Test("cena do código errado: a caixa fica aberta com o aviso de código inválido")
    func wrongCodeScene() async {
        let bench = await open(.wrongCode)
        #expect(bench.state.screen == .account)
        #expect(bench.state.dialog == .code)
        #expect(bench.state.codeResult == .failed(.invalid, status: 404))
        #expect(DemoScene.wrongCode.typedCode == DemoScene.unknownCode)
    }

    @Test("cena depois de ativar: o código de exemplo ativa por 365 dias e a Conta mostra até quando")
    func activatedScene() async {
        let bench = await open(.activated)
        #expect(bench.state.screen == .account)
        #expect(bench.state.dialog == nil)
        #expect(bench.state.codeResult == .activated(days: 365))
        #expect(bench.state.site.status == .active)
        #expect(ScreenTexts.activeUntil(bench.state.site, datePattern: "dd/MM/yyyy", timeZone: utc)
            == TextRef("playlists_active_until", ["12/11/2027"]))
    }

    @Test("cenas do aparelho ativo: sem listas, com parceiro (Desconectar), vencendo e vencido")
    func activeScenes() async {
        let active = await open(.active)
        #expect(active.state.site.status == .active)
        #expect(active.state.site.partner == false)
        #expect(ScreenTexts.status(active.state.site) == TextRef("playlists_empty"))
        #expect(Validity.warning(active.state.site, now: active.clock.now) == nil)

        let unlink = await open(.unlink)
        #expect(unlink.state.dialog == .unlink)
        #expect(unlink.state.site.status == .active)
        #expect(unlink.state.site.partner == true)
        #expect(unlink.state.unlinkResult == nil)

        let expiring = await open(.expiring)
        #expect(expiring.state.site.status == .active)
        #expect(Validity.warning(expiring.state.site, now: expiring.clock.now) == .week)

        let expired = await open(.expired)
        #expect(expired.state.site.status == .inactive)
        #expect(Validity.warning(expired.state.site, now: expired.clock.now) == .expired)
    }

    @Test("cenas sem conexão e bloqueado")
    func troubleScenes() async {
        let offline = await open(.offline)
        #expect(offline.state.site.status == .unknown)
        #expect(offline.state.site.problem == .offline)
        #expect(offline.state.identity != nil)

        let blocked = await open(.blocked)
        #expect(blocked.state.site.status == .blocked)
    }

    @Test("cenas da Mídia: sem recentes e com os três recentes do desenho")
    func mediaScenes() async {
        let media = await open(.media)
        #expect(media.state.screen == .media)
        #expect(media.state.recents.isEmpty)
        #expect(media.state.playing == nil)

        let recents = await open(.mediaRecents)
        #expect(recents.state.screen == .media)
        #expect(recents.state.recents.map(\.title) == ["Aniversário da Ana.mp4", "aula-de-violao-03.mkv", "passeio-na-praia.mov"])
        let pattern = "%1$@ de %2$@"
        #expect(recents.state.recents.map { ScreenTexts.recentProgress($0, pattern: pattern) } == ["12:34 de 48:10", "1:02:03", "3:05 de 5:40"])
        #expect(recents.state.recents.map { ScreenTexts.recentSource($0) } == [
            TextRef("media_recent_file"), TextRef("media_recent_link", ["exemplo.com"]), TextRef("media_recent_file"),
        ])
        // Só a cena dos recentes começa com vídeos guardados.
        let now = parseServerTime("2026-11-12T14:30:00Z")!
        #expect(DemoScene.allCases.filter { $0.storedRecents(now: now) != nil } == [.mediaRecents])
    }

    @Test("cenas do link: o endereço de exemplo digitado e o endereço que não vale")
    func linkScenes() async {
        let link = await open(.link)
        #expect(link.state.screen == .openLink)
        #expect(!link.state.linkInvalid)
        #expect(link.state.playing == nil)
        #expect(DemoScene.link.typedLink == "http://exemplo.com/video.mp4")
        #expect(VideoLink.normalize(DemoScene.link.typedLink) == "http://exemplo.com/video.mp4")

        let wrong = await open(.wrongLink)
        #expect(wrong.state.screen == .openLink)
        #expect(wrong.state.linkInvalid)
        #expect(wrong.state.playing == nil)
        #expect(DemoScene.wrongLink.typedLink == "meu video")
        #expect(DemoScene.home.typedLink.isEmpty)
    }

    @Test("cena do reprodutor: o vídeo de demonstração parado aos 9 segundos, com os controles na tela")
    func playerScene() async throws {
        let bench = await open(.player)
        #expect(bench.state.screen == .media)
        #expect(bench.state.playing == PlaybackRequest(kind: .demo, uri: "", title: "Big Buck Bunny (trecho)"))
        let player = try #require(bench.app.player)
        #expect(player.state.status == .paused)
        #expect(player.state.positionMs == 9_000)
        #expect(player.state.durationMs == 21_600)
        #expect(player.state.controlsVisible)
        #expect(player.state.problem == nil)
        #expect(ScreenTexts.playerTime(positionMs: player.state.positionMs, durationMs: player.state.durationMs) == "0:09 · 0:22")
        let engine = try #require(bench.engine)
        #expect(engine.calls == ["open \(FakeAccess.demoAddress) @0", "seek 9000", "pause", "seek 9000"])
        #expect(!engine.isPlaying)
    }

    @Test("cena do vídeo que não abriu: o link que ninguém atende dá a mensagem de falta de conexão")
    func playerProblemScene() async throws {
        let bench = await open(.playerProblem)
        #expect(bench.state.screen == .media)
        #expect(bench.state.playing?.kind == .link)
        #expect(bench.state.playing?.title == "aula-de-violao-03.mkv")
        let player = try #require(bench.app.player)
        #expect(player.state.problem == PlaybackProblem(message: TextRef("player_error_network"), code: 2001))
        // O endereço da cena fica no próprio aparelho: o pedido não sai para a internet.
        #expect(VideoLink.host(DemoScene.deadLink) == "127.0.0.1")
        #expect(bench.diagnosis.asked == [FakeDiagnosis.Question(kind: .link, address: DemoScene.deadLink)])
    }

    @Test("cena do copiado: a chave de exemplo vai para a área de transferência e o aviso fica na tela")
    func copiedScene() async {
        let bench = await open(.copied)
        #expect(bench.clipboard.texts == ["483920"])
        #expect(bench.state.copied == .key)
        #expect(bench.state.notice == Notice(TextRef("device_key_copied"), done: true))
    }
}
