import Foundation
import Testing
@testable import PlazvoCore

@MainActor
@Suite("Cenas do simulador (fotos das telas)")
struct DemoSceneTests {
    let utc = TimeZone(secondsFromGMT: 0)!

    /// Abre o app numa cena, como a compilação do simulador faz.
    private func open(_ scene: DemoScene) async -> AppBench {
        let bench = AppBench(now: "2026-11-12T14:30:00Z", random: DemoScene.exampleRandom())
        await scene.prepare(bench.site, now: bench.clock.now)
        await bench.app.start()
        await scene.play(on: bench.app)
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

    @Test("cena do copiado: a chave de exemplo vai para a área de transferência e o aviso fica na tela")
    func copiedScene() async {
        let bench = await open(.copied)
        #expect(bench.clipboard.texts == ["483920"])
        #expect(bench.state.copied == .key)
        #expect(bench.state.notice == Notice(TextRef("device_key_copied"), done: true))
    }
}
