import Foundation
import Testing
@testable import PlazvoCore

/// A área de transferência de mentira: guarda o que o app mandou copiar.
final class TestClipboard {
    var texts: [String] = []
}

/// Tudo o que um teste das telas precisa, já ligado: servidor de mentira, cofre, lógica e o
/// controle das telas, com um relógio que o teste escolhe.
@MainActor
final class AppBench {
    let clock: TestClock
    let site: FakeSite
    let secure = InMemorySecureStore()
    let clipboard = TestClipboard()
    let identity: DeviceIdentityStore
    let lists: SiteLists
    let app: AppController
    private(set) var changes: [AppState] = []

    init(now: String = "2026-10-05T19:00:00Z", random: RandomSource = predictableRandom(), noticeSeconds: Double? = nil) {
        let clock = TestClock(now)
        let clipboard = self.clipboard
        self.clock = clock
        site = FakeSite(now: { clock.now })
        identity = DeviceIdentityStore(store: secure, random: random)
        lists = SiteLists(api: site, identityStore: identity, copy: InMemoryCopyStore(), platform: "ios", appVersion: "0.1.0", now: { clock.now })
        app = AppController(identityStore: identity, siteLists: lists, copyText: { clipboard.texts.append($0) }, noticeSeconds: noticeSeconds)
        app.onChange = { [unowned self] in self.changes.append($0) }
    }

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
