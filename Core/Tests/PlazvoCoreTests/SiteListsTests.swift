import Foundation
import Testing
@testable import PlazvoCore

/// O servidor de mentira com um defeito de propósito: o pedido das listas fica sem resposta.
private struct NoPlaylists: SiteApi {
    let site: FakeSite

    func register(_ credentials: DeviceCredentials, platform: String, appVersion: String) async -> ApiResult<Void> {
        await site.register(credentials, platform: platform, appVersion: appVersion)
    }

    func playlists(deviceId: String, secret: String) async -> ApiResult<PlaylistsAnswer> { .unavailable }

    func activateWithCode(deviceId: String, secret: String, code: String) async -> ApiResult<CodeAnswer> {
        await site.activateWithCode(deviceId: deviceId, secret: secret, code: code)
    }

    func unlink(deviceId: String, secret: String) async -> ApiResult<UnlinkAnswer> {
        await site.unlink(deviceId: deviceId, secret: secret)
    }

    func ping() async -> ApiResult<Void> { await site.ping() }
}

/// Espera (no máximo 5 s) até a condição valer. Devolve se valeu.
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<2_500 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    return await condition()
}

@MainActor
@Suite("Situação do aparelho no servidor")
struct SiteListsTests {
    let bench = Bench()

    // MARK: - Consulta

    @Test("primeira consulta: o aparelho se apresenta ao servidor e ainda não está ativo")
    func firstSync() async throws {
        #expect(bench.state == SiteListsState())

        await bench.lists.sync()

        #expect(await bench.site.calls == ["register", "playlists"])
        #expect(bench.state == SiteListsState(status: .inactive, partner: false))
        let credentials = try bench.identity.credentials()
        let device = try #require(await bench.site.devices[credentials.id])
        #expect(device.key == credentials.key)
        #expect(device.secret == credentials.secret)
        #expect(device.platform == "ios")
        #expect(device.appVersion == "0.1.0")
        #expect(bench.copy.data == nil)
    }

    @Test("aparelho ativo: as listas chegam na ordem do servidor e ficam guardadas")
    func activeDevice() async {
        await bench.activateAll([serverList, linkList], partner: true)

        await bench.lists.sync()

        #expect(bench.state.status == .active)
        #expect(bench.state.playlists.map(\.id) == [7, 9])
        #expect(bench.state.playlists.map(\.kind) == [.server, .link])
        #expect(bench.state.expiresAt == parseServerTime("2027-10-02T22:40:23Z"))
        #expect(bench.state.partner == true)
        #expect(bench.state.problem == nil)
        #expect(!bench.state.syncing)
        #expect(bench.copy.data != nil)
        #expect(bench.lists.isActive())
        #expect(bench.lists.playlist(id: 9)?.name == "Sala")
        #expect(bench.lists.playlist(id: 1) == nil)
    }

    @Test("a tela nunca vê um estado pela metade: a consulta ativa chega de uma vez")
    func stateChangesAtOnce() async {
        await bench.activateAll([serverList])

        await bench.lists.sync()

        // "consultando" → ativo com as listas (ainda consultando) → fim da consulta.
        #expect(bench.changes.map(\.syncing) == [true, true, false])
        #expect(bench.changes.map(\.status) == [.unknown, .active, .active])
        #expect(bench.changes.map(\.playlists.count) == [0, 1, 1])
    }

    @Test("servidor fora do ar: o app abre com a cópia guardada e avisa que não atualizou")
    func offlineWithCopy() async {
        await bench.activateAll([serverList])
        await bench.lists.sync()
        await bench.site.setDown(true)
        bench.reopen()

        await bench.lists.sync()

        #expect(bench.state.status == .active)
        #expect(bench.state.playlists.map(\.id) == [7])
        #expect(bench.state.problem == .offline)
        #expect(bench.copy.data != nil)
    }

    @Test("servidor fora do ar e nada guardado: só o aviso")
    func offlineWithoutCopy() async {
        await bench.site.setDown(true)

        await bench.lists.sync()

        #expect(bench.state == SiteListsState(status: .unknown, problem: .offline))
        #expect(await bench.site.calls == ["register"])
    }

    @Test("cópia guardada não vale depois do fim da ativação")
    func copyExpires() async {
        await bench.activateAll([serverList], expiresAt: "2026-10-06T00:00:00Z")
        await bench.lists.sync()
        #expect(bench.state.status == .active)
        await bench.site.setDown(true)
        bench.clock.set("2026-10-06T00:00:01Z")
        bench.reopen()

        await bench.lists.sync()

        #expect(bench.state.status == .unknown)
        #expect(bench.state.playlists.isEmpty)
        #expect(bench.state.problem == .offline)
        #expect(bench.copy.data == nil)
    }

    @Test("ativação vence com o app aberto e sem internet: as listas saem")
    func expiresWhileOpen() async {
        await bench.activateAll([serverList], expiresAt: "2026-10-06T00:00:00Z")
        await bench.lists.sync()
        await bench.site.setDown(true)
        bench.clock.set("2026-10-06T00:00:00Z")

        bench.lists.dropIfExpired()

        #expect(bench.state.status == .inactive)
        #expect(bench.state.playlists.isEmpty)
        // A data fica: a tela inicial avisa que venceu.
        #expect(bench.state.expiresAt == parseServerTime("2026-10-06T00:00:00Z"))
        #expect(await eventually { bench.copy.data == nil })
    }

    @Test("ativação vence com o app aberto: a lista já não abre, mesmo sem a tela conferir antes")
    func expiredListDoesNotOpen() async {
        await bench.activateAll([serverList], expiresAt: "2026-10-06T00:00:00Z")
        await bench.lists.sync()
        bench.clock.set("2026-10-07T00:00:00Z")

        #expect(bench.lists.playlist(id: 7) == nil)
        #expect(!bench.lists.isActive())
    }

    @Test("ativação vencida descoberta numa consulta que falhou: as listas saem e o aviso fica")
    func expiredDuringFailedSync() async {
        await bench.activateAll([serverList], expiresAt: "2026-10-06T00:00:00Z")
        await bench.lists.sync()
        await bench.site.setDown(true)
        bench.clock.set("2026-10-06T12:00:00Z")

        await bench.lists.sync()

        #expect(bench.state.status == .inactive)
        #expect(bench.state.playlists.isEmpty)
        #expect(bench.state.problem == .offline)
        #expect(bench.copy.data == nil)
    }

    @Test("relógio do aparelho adiantado não esconde as listas que o servidor acabou de entregar")
    func deviceClockAhead() async {
        // O servidor diz que são 19h de 05/10/2026 e que a ativação vai até 2027; o aparelho acha que é 2030.
        await bench.activateAll([serverList])
        let device = TestClock("2030-01-01T00:00:00Z")
        let server = bench.clock
        let lists = SiteLists(api: bench.site, identityStore: bench.identity, copy: bench.copy, platform: "ios", appVersion: "0.1.0", now: { device.now })
        _ = server

        await lists.sync()

        #expect(lists.state.status == .active)
        #expect(lists.isActive())
        #expect(lists.playlist(id: 7) != nil)
    }

    @Test("resposta ativa com a data de fim já passada conta como não ativa")
    func activeButExpired() async {
        await bench.activateAll([serverList], expiresAt: "2026-10-05T18:59:59Z")

        await bench.lists.sync()

        #expect(bench.state.status == .inactive)
        #expect(bench.state.playlists.isEmpty)
        #expect(bench.state.expiresAt == parseServerTime("2026-10-05T18:59:59Z"))
        #expect(bench.copy.data == nil)
    }

    @Test("o servidor desativou o aparelho: as listas e a cópia saem dele")
    func deactivated() async {
        await bench.activateAll([serverList])
        await bench.lists.sync()
        await bench.site.setSetup { $0.active = false }

        await bench.lists.sync()

        #expect(bench.state == SiteListsState(status: .inactive, partner: false))
        #expect(bench.copy.data == nil)
    }

    @Test("aparelho bloqueado: as listas e a cópia saem dele")
    func blocked() async {
        await bench.activateAll([serverList])
        await bench.lists.sync()
        await bench.site.setSetup { $0.blocked = true }

        await bench.lists.sync()

        #expect(bench.state == SiteListsState(status: .blocked))
        #expect(bench.copy.data == nil)
    }

    @Test("segredo recusado pelo servidor: avisa e não insiste")
    func secretRefused() async throws {
        await bench.lists.sync()
        // Outro aparelho com o mesmo ID e outro segredo: o cofre foi trocado.
        let impostor = InMemorySecureStore()
        let other = DeviceIdentityStore(store: impostor, random: predictableRandom())
        let same = try other.credentials()
        #expect(same.id == (try bench.deviceId()))
        try other.rotateKey()
        let stolen = DeviceCredentials(id: same.id, key: same.key, secret: String(repeating: "0", count: 64))
        #expect(await isRefused(bench.site.register(stolen, platform: "ios", appVersion: "0.1.0"), status: 401))

        await bench.site.setRefuseWith(401)
        await bench.lists.sync()

        #expect(bench.state.problem == .refused)
        #expect(bench.state.problemStatus == nil)
        #expect(await bench.site.calls.suffix(1) == ["register"])
    }

    @Test("chamadas demais: avisa e fica com as listas que já tinha")
    func tooManyAttempts() async {
        await bench.activateAll([serverList])
        await bench.lists.sync()
        await bench.site.setRefuseWith(429)

        await bench.lists.sync()

        #expect(bench.state.status == .active)
        #expect(bench.state.playlists.map(\.id) == [7])
        #expect(bench.state.problem == .tooManyAttempts)
        #expect(bench.copy.data != nil)
    }

    @Test("pedido recusado por outro motivo: o número da resposta vai para o aviso")
    func rejected() async {
        await bench.site.setRefuseWith(418)

        await bench.lists.sync()

        #expect(bench.state == SiteListsState(status: .unknown, problem: .rejected, problemStatus: 418))
    }

    @Test("o aviso de uma consulta que falhou some na consulta seguinte que dá certo")
    func problemClears() async {
        await bench.site.setDown(true)
        await bench.lists.sync()
        #expect(bench.state.problem == .offline)
        await bench.site.setDown(false)

        await bench.lists.sync()

        #expect(bench.state == SiteListsState(status: .inactive, partner: false))
    }

    @Test("chave nova chega ao servidor na consulta seguinte e o segredo continua o mesmo")
    func newKeyReachesServer() async throws {
        await bench.lists.sync()
        let before = try bench.identity.credentials()

        try bench.identity.rotateKey()
        await bench.lists.sync()

        let after = try bench.identity.credentials()
        let device = try #require(await bench.site.devices[before.id])
        #expect(after.key != before.key)
        #expect(device.key == after.key)
        #expect(device.secret == before.secret)
        #expect(await bench.site.devices.count == 1)
        #expect(bench.state.problem == nil)
    }

    @Test("consulta em andamento: a tela sabe, e os pedidos repetidos viram uma consulta só")
    func repeatedRequestsBecomeOne() async {
        await bench.site.hold()
        let first = Task { await bench.lists.sync() }
        #expect(await eventually { await bench.site.waitingCalls == 1 })
        #expect(bench.state.syncing)

        let second = Task { await bench.lists.sync() }
        let third = Task { await bench.lists.sync() }
        let fourth = Task { await bench.lists.sync() }
        await bench.site.release()
        _ = await (first.value, second.value, third.value, fourth.value)

        // A consulta que estava em andamento e mais uma, pelos três pedidos que chegaram durante ela.
        #expect(await bench.site.calls == ["register", "playlists", "register", "playlists"])
        #expect(!bench.state.syncing)
    }

    @Test("chave trocada com uma consulta em andamento chega ao servidor logo depois")
    func keyChangedDuringSync() async throws {
        await bench.site.hold()
        let first = Task { await bench.lists.sync() }
        #expect(await eventually { await bench.site.waitingCalls == 1 })

        try bench.identity.rotateKey()
        let second = Task { await bench.lists.sync() }
        await bench.site.release()
        _ = await (first.value, second.value)

        let credentials = try bench.identity.credentials()
        #expect(await bench.site.devices[credentials.id]?.key == credentials.key)
    }

    @Test("consulta ao abrir o app: acontece uma vez só")
    func startupSyncOnce() async {
        bench.lists.syncAtStartup()
        bench.lists.syncAtStartup()
        bench.lists.syncAtStartup()

        #expect(await eventually { bench.state.status == .inactive })
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(await bench.site.calls == ["register", "playlists"])
    }

    @Test("cofre que não abre: a consulta falha como falta de conexão e nada vai ao servidor")
    func identityUnavailable() async {
        bench.secure.readFailure = SecureStoreError(status: -25308)

        await bench.lists.sync()

        #expect(bench.state == SiteListsState(status: .unknown, problem: .offline))
        #expect(await bench.site.calls.isEmpty)
        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .failed(.offline, status: nil))
        #expect(await bench.lists.unlink() == .failed(.offline, status: nil))
        #expect(await bench.site.calls.isEmpty)
    }

    // MARK: - Código de ativação

    @Test("código de ativação: o aparelho se registra, manda o código e fica ativo sem lista")
    func activationCode() async throws {
        await bench.site.addCode("ABCD-EFGH-JKMN", days: 30)

        let result = await bench.lists.activateWithCode("ABCDEFGHJKMN")

        #expect(result == .activated(days: 30))
        // Sem consulta antes: o registro vai na frente.
        #expect(await bench.site.calls == ["register", "activate-code", "playlists"])
        #expect(bench.state.status == .active)
        #expect(bench.state.playlists.isEmpty)
        #expect(bench.state.expiresAt == parseServerTime("2026-11-04T19:00:00Z"))
        #expect(!bench.state.syncing)
        #expect(bench.copy.data != nil)
    }

    @Test("código de ativação recusado: cada motivo do servidor vira o aviso certo")
    func activationCodeRefused() async throws {
        await bench.site.addCode("DESLIGADO001", disabled: true)
        await bench.site.addCode("ESGOTADO0001", uses: 0)
        await bench.site.addCode("SEMCREDITO01", noCredits: true)
        await bench.site.addCode("BOMCODIGO001")

        #expect(await bench.lists.activateWithCode("NAOEXISTE001") == .failed(.invalid, status: 404))
        #expect(await bench.lists.activateWithCode("DESLIGADO001") == .failed(.unavailable, status: 410))
        #expect(await bench.lists.activateWithCode("ESGOTADO0001") == .failed(.unavailable, status: 410))
        #expect(await bench.lists.activateWithCode("SEMCREDITO01") == .failed(.noCredits, status: 409))
        #expect(bench.state.status != .active)

        // Aparelho cuidado por um parceiro: só ele ativa.
        let id = try bench.deviceId()
        await bench.site.change(id) { $0.partner = true }
        #expect(await bench.lists.activateWithCode("BOMCODIGO001") == .failed(.managed, status: 409))
        await bench.site.change(id) { $0.partner = false }

        // Aparelho já ativo: o código não soma tempo.
        await bench.site.change(id) { $0.active = true; $0.expiresAt = "2027-01-01T00:00:00Z" }
        #expect(await bench.lists.activateWithCode("BOMCODIGO001") == .failed(.alreadyActive, status: 409))

        // Formato errado (o app não manda, mas o servidor recusa): número da resposta no aviso.
        #expect(await bench.lists.activateWithCode("CURTO") == .failed(.rejected, status: 400))
    }

    @Test("código de ativação: o mesmo aparelho não usa o mesmo código duas vezes")
    func activationCodeUsedTwice() async throws {
        await bench.site.addCode("ABCDEFGHJKMN", days: 1)
        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .activated(days: 1))
        let id = try bench.deviceId()
        await bench.site.change(id) { $0.active = false }

        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .failed(.used, status: 409))
    }

    @Test("código de ativação: servidor fora do ar, segredo recusado e tentativas demais")
    func activationCodeFailures() async {
        await bench.site.addCode("ABCDEFGHJKMN")

        await bench.site.setDown(true)
        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .failed(.offline, status: nil))
        await bench.site.setDown(false)

        await bench.site.setRefuseWith(401)
        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .failed(.refused, status: 401))

        await bench.site.setRefuseWith(429)
        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .failed(.tooManyAttempts, status: 429))

        await bench.site.setRefuseWith(500 - 77)
        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .failed(.rejected, status: 423))
        #expect(!bench.state.syncing)
        #expect(bench.state.status != .active)
    }

    @Test("código de ativação: aparelho bloqueado sai do ar como numa consulta comum")
    func activationCodeBlocked() async throws {
        await bench.activateAll([serverList])
        await bench.lists.sync()
        await bench.site.setSetup(nil)
        await bench.site.change(try bench.deviceId()) { $0.blocked = true }

        #expect(await bench.lists.activateWithCode("ABCDEFGHJKMN") == .failed(.rejected, status: 403))

        #expect(bench.state == SiteListsState(status: .blocked))
        #expect(bench.copy.data == nil)
    }

    // MARK: - Parceria ("Ativo por parceiro")

    @Test("parceria: a situação diz que a ativação é de parceria, e a cópia guardada também")
    func sponsored() async {
        await bench.activateAll([serverList], expiresAt: "2026-11-30T02:59:59Z", partner: true, sponsored: true)

        await bench.lists.sync()

        #expect(bench.state.status == .active)
        #expect(bench.state.sponsored)
        #expect(bench.state.partner == true)
        // A data continua valendo para saber se o aparelho está ativo.
        #expect(bench.state.expiresAt == parseServerTime("2026-11-30T02:59:59Z"))

        // Fechou e abriu sem internet: a cópia guardada traz a parceria.
        await bench.site.setDown(true)
        bench.reopen()
        await bench.lists.sync()
        #expect(bench.state.status == .active)
        #expect(bench.state.sponsored)
        #expect(bench.state.problem == .offline)
    }

    @Test("ativação comum de um aparelho cuidado por um parceiro não é ativação de parceria")
    func managedIsNotSponsored() async {
        await bench.activateAll(partner: true)

        await bench.lists.sync()

        #expect(bench.state.partner == true)
        #expect(!bench.state.sponsored)
    }

    @Test("parceria que parou: o servidor volta a mandar falso, e a cópia guardada acompanha")
    func sponsorshipEnded() async {
        await bench.activateAll(expiresAt: "2026-11-30T02:59:59Z", sponsored: true)
        await bench.lists.sync()
        #expect(bench.state.sponsored)

        await bench.activateAll(expiresAt: "2026-11-30T02:59:59Z")
        await bench.lists.sync()
        #expect(bench.state.status == .active)
        #expect(!bench.state.sponsored)

        await bench.site.setDown(true)
        bench.reopen()
        await bench.lists.sync()
        #expect(bench.state.status == .active)
        #expect(!bench.state.sponsored)
    }

    @Test("parceria sem falar com o servidor: vence na data, como qualquer ativação")
    func sponsoredExpiresOffline() async {
        await bench.activateAll([serverList], expiresAt: "2026-11-30T02:59:59Z", sponsored: true)
        await bench.lists.sync()
        await bench.site.setDown(true)

        bench.clock.set("2026-11-30T02:59:58Z")
        #expect(bench.lists.isActive())
        #expect(bench.state.sponsored)

        bench.clock.set("2026-11-30T02:59:59Z")
        #expect(!bench.lists.isActive())
        #expect(bench.state.status == .inactive)
        #expect(!bench.state.sponsored)
        #expect(bench.state.playlists.isEmpty)
        // A data fica: a tela inicial avisa que venceu.
        #expect(bench.state.expiresAt == parseServerTime("2026-11-30T02:59:59Z"))
        #expect(Validity.warning(bench.state, now: bench.clock.now) == .expired)
    }

    @Test("parceria: painel antigo não manda o campo, e tudo fica como antes")
    func sponsoredOldPanel() async {
        await bench.activateAll(sponsored: true)
        await bench.site.setOldPanel(true)

        await bench.lists.sync()

        #expect(bench.state.status == .active)
        #expect(!bench.state.sponsored)
    }

    @Test("parceria: aparelho desativado ou bloqueado deixa de ser de parceria")
    func sponsoredOnlyWhileActive() async {
        await bench.activateAll(sponsored: true)
        await bench.lists.sync()
        #expect(bench.state.sponsored)

        await bench.site.setSetup { $0.active = false }
        await bench.lists.sync()
        #expect(bench.state == SiteListsState(status: .inactive, partner: false))

        await bench.activateAll(sponsored: true)
        await bench.lists.sync()
        #expect(bench.state.sponsored)

        await bench.site.setSetup { $0.blocked = true }
        await bench.lists.sync()
        #expect(bench.state == SiteListsState(status: .blocked))
    }

    @Test("código de uma parceria: o aparelho fica ativo por parceria e o resultado não fala em dias")
    func sponsoredCode() async {
        await bench.site.addCode("PARC-ERIA-2026", days: 20, sponsored: true)

        let result = await bench.lists.activateWithCode("PARCERIA2026")

        #expect(result == .activated(days: nil))
        #expect(bench.state.status == .active)
        #expect(bench.state.sponsored)
        #expect(bench.state.expiresAt == parseServerTime("2026-10-25T19:00:00Z"))
    }

    @Test("código de uma parceria aceito e a consulta seguinte sem resposta: o resultado já não fala em dias")
    func sponsoredCodeWithoutRefresh() async {
        await bench.site.addCode("PARCERIA2026", days: 20, sponsored: true)
        let clock = bench.clock
        let lists = SiteLists(
            api: NoPlaylists(site: bench.site), identityStore: bench.identity, copy: bench.copy,
            platform: "ios", appVersion: "0.1.0", now: { clock.now }
        )

        let result = await lists.activateWithCode("PARCERIA2026")

        #expect(result == .activated(days: nil))
        // A situação só muda com a resposta das listas.
        #expect(lists.state.status == .unknown)
        #expect(!lists.state.sponsored)
        #expect(lists.state.problem == .offline)
    }

    @Test("código aceito sem o campo da parceria, mas a situação nova é de parceria: sem os dias")
    func codeThenSponsoredState() async {
        await bench.site.addCode("ABCDEFGHJKMN", days: 30)
        // A parceria aparece só na situação (o pedido das listas), não na resposta do código.
        await bench.site.setSetup { if $0.active { $0.sponsored = true } }

        let result = await bench.lists.activateWithCode("ABCDEFGHJKMN")

        #expect(result == .activated(days: nil))
        #expect(bench.state.sponsored)
    }

    @Test("código comum depois da parceria: o resultado volta a dizer os dias")
    func plainCodeKeepsDays() async {
        await bench.site.addCode("ABCDEFGHJKMN", days: 30, sponsored: false)

        let result = await bench.lists.activateWithCode("ABCDEFGHJKMN")

        #expect(result == .activated(days: 30))
        #expect(!bench.state.sponsored)
    }

    // MARK: - Desconectar do painel

    @Test("desconectar do painel: o aparelho se registra, pede para sair e a situação nova vem do servidor")
    func unlink() async {
        await bench.activateAll([serverList], partner: true)
        await bench.lists.sync()
        #expect(bench.state.partner == true)
        // Depois do pedido, o servidor é quem diz que não há mais parceiro.
        await bench.site.setSetup { $0.active = true; $0.expiresAt = "2027-10-02T22:40:23Z"; $0.playlists = [serverList] }

        let result = await bench.lists.unlink()

        #expect(result == .unlinked)
        #expect(await bench.site.calls.suffix(3) == ["register", "unlink", "playlists"])
        #expect(bench.state.partner == false)
        // As listas e a ativação continuam.
        #expect(bench.state.status == .active)
        #expect(bench.state.playlists.map(\.id) == [7])
        #expect(!bench.state.syncing)
    }

    @Test("desconectar do painel: aparelho que não estava em nenhum painel")
    func unlinkNotLinked() async {
        #expect(await bench.lists.unlink() == .notLinked)
        #expect(bench.state == SiteListsState(status: .inactive, partner: false))
    }

    @Test("desconectar do painel: painel antigo, servidor fora do ar, segredo recusado, tentativas demais e bloqueio")
    func unlinkFailures() async throws {
        await bench.activateAll([serverList], partner: true)
        await bench.lists.sync()

        await bench.site.setOldPanel(true)
        #expect(await bench.lists.unlink() == .failed(.unavailable, status: 404))
        await bench.site.setOldPanel(false)

        await bench.site.setDown(true)
        #expect(await bench.lists.unlink() == .failed(.offline, status: nil))
        await bench.site.setDown(false)

        await bench.site.setRefuseWith(401)
        #expect(await bench.lists.unlink() == .failed(.refused, status: 401))
        await bench.site.setRefuseWith(429)
        #expect(await bench.lists.unlink() == .failed(.tooManyAttempts, status: 429))
        await bench.site.setRefuseWith(418)
        #expect(await bench.lists.unlink() == .failed(.rejected, status: 418))
        await bench.site.setRefuseWith(nil)
        #expect(bench.state.status == .active)
        #expect(bench.state.partner == true)

        await bench.site.setSetup(nil)
        await bench.site.change(try bench.deviceId()) { $0.blocked = true }
        #expect(await bench.lists.unlink() == .failed(.rejected, status: 403))
        #expect(bench.state == SiteListsState(status: .blocked))
        #expect(bench.copy.data == nil)
    }

    @Test("o servidor responde? (só um ping, sem nada do aparelho)")
    func ping() async {
        #expect(await bench.lists.ping())
        await bench.site.setDown(true)
        #expect(await !bench.lists.ping())
        #expect(await bench.site.calls == ["ping", "ping"])
        #expect(await bench.site.devices.isEmpty)
    }

    private func isRefused<Value>(_ result: ApiResult<Value>, status: Int) -> Bool {
        if case .refused(let got, _) = result { return got == status }
        return false
    }
}
