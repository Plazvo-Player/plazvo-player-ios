import Foundation

/// Situação deste aparelho no servidor.
public enum SiteStatus: Equatable, Sendable {
    /// Ainda não houve resposta do servidor (nem há cópia guardada que sirva).
    case unknown
    /// Ativado: as listas valem.
    case active
    /// Não ativado, ou a ativação venceu.
    case inactive
    /// Bloqueado pelo administrador.
    case blocked
}

/// Por que a última tentativa de falar com o servidor não deu certo.
public enum SyncProblem: Equatable, Sendable {
    /// Sem internet, tempo esgotado ou servidor fora do ar.
    case offline
    /// O servidor não aceitou o segredo deste aparelho: só o suporte resolve.
    case refused
    /// Chamadas demais em pouco tempo.
    case tooManyAttempts
    /// O servidor recusou o pedido por outro motivo (ver o número da resposta).
    case rejected
}

/// Por que um código de ativação não ativou o aparelho.
public enum CodeProblem: Equatable, Sendable {
    /// O servidor não conhece esse código.
    case invalid
    /// O código existe, mas foi desligado, venceu ou já foi usado o máximo de vezes.
    case unavailable
    /// Este aparelho já usou esse código.
    case used
    /// O aparelho já está ativo: o código não soma tempo.
    case alreadyActive
    /// O aparelho é cuidado por um parceiro: só ele ativa.
    case managed
    /// Quem gerou o código está sem créditos agora: o código continua valendo.
    case noCredits
    /// Tentativas demais em pouco tempo.
    case tooManyAttempts
    /// Sem internet, tempo esgotado ou servidor fora do ar.
    case offline
    /// O servidor não aceitou o segredo deste aparelho: só o suporte resolve.
    case refused
    /// O servidor recusou por outro motivo (ver o número da resposta).
    case rejected
}

/// Resultado de um código de ativação enviado ao servidor.
public enum CodeResult: Equatable, Sendable {
    /// O aparelho ficou ativo; `days` é por quantos dias, quando o servidor informa.
    case activated(days: Int?)
    case failed(CodeProblem, status: Int?)
}

/// Por que o aparelho não saiu do painel (botão "Desconectar do painel").
public enum UnlinkProblem: Equatable, Sendable {
    /// Sem internet, tempo esgotado ou servidor fora do ar.
    case offline
    /// O servidor ainda não tem essa opção (painel antigo): responde 404.
    case unavailable
    /// Tentativas demais em pouco tempo.
    case tooManyAttempts
    /// O servidor não aceitou o segredo deste aparelho.
    case refused
    /// O servidor recusou por outro motivo (ver o número da resposta).
    case rejected
}

/// Resultado do pedido de sair do painel.
public enum UnlinkResult: Equatable, Sendable {
    /// O aparelho saiu do painel do parceiro que cuidava dele.
    case unlinked
    /// O aparelho não estava no painel de nenhum parceiro: nada mudou.
    case notLinked
    case failed(UnlinkProblem, status: Int?)
}

/// O que as telas mostram sobre o aparelho e as listas dele.
public struct SiteListsState: Equatable, Sendable {
    public var status: SiteStatus = .unknown
    public var playlists: [SitePlaylist] = []
    /// Fim da ativação, quando o servidor informou. Com `.inactive`, é a data em que a ativação
    /// venceu (ou `nil` se o aparelho nunca foi ativado ou não se sabe).
    public var expiresAt: Date?
    /// Há uma consulta ao servidor em andamento.
    public var syncing = false
    /// Falha da última consulta, ou `nil` se ela deu certo (ou ainda não houve).
    public var problem: SyncProblem?
    /// Número da resposta do servidor, para o caso `.rejected`.
    public var problemStatus: Int?
    /// Um parceiro cuida deste aparelho pelo painel. `nil`: o servidor não disse ou ainda não respondeu.
    public var partner: Bool?

    public init(
        status: SiteStatus = .unknown,
        playlists: [SitePlaylist] = [],
        expiresAt: Date? = nil,
        syncing: Bool = false,
        problem: SyncProblem? = nil,
        problemStatus: Int? = nil,
        partner: Bool? = nil
    ) {
        self.status = status
        self.playlists = playlists
        self.expiresAt = expiresAt
        self.syncing = syncing
        self.problem = problem
        self.problemStatus = problemStatus
        self.partner = partner
    }
}

/// A situação do aparelho no servidor e as listas vinculadas a ele.
///
/// Consulta o servidor (registro do aparelho + pedido das listas) ao abrir o app e quando o
/// usuário pede, nunca em laço. A última resposta fica guardada no aparelho: se o servidor não
/// responder, o app continua com ela até o fim da ativação. Use uma única instância por app.
@MainActor
public final class SiteLists {
    /// A situação atual. Muda sempre de uma vez só (as telas nunca veem um estado pela metade).
    public private(set) var state = SiteListsState() {
        didSet {
            if state != oldValue { onChange?(state) }
        }
    }

    /// Chamado a cada mudança da situação.
    public var onChange: ((SiteListsState) -> Void)?

    private let api: any SiteApi
    private let identityStore: DeviceIdentityStore
    private let copy: any CopyStore
    private let platform: String
    private let appVersion: String
    private let now: () -> Date

    private var copyLoaded = false
    private var syncRequested = false
    private var startupSyncStarted = false

    /// O último trabalho da fila: os pedidos ao servidor correm um de cada vez, na ordem.
    private var tail: Task<Void, Never>?

    // Diferença entre o relógio do servidor e o do aparelho, medida na última resposta. Com ela,
    // um aparelho com a data errada não esconde listas que o servidor acabou de dizer que valem.
    private var clockOffset: TimeInterval = 0

    public init(
        api: any SiteApi,
        identityStore: DeviceIdentityStore,
        copy: any CopyStore,
        platform: String,
        appVersion: String,
        now: @escaping () -> Date = { Date() }
    ) {
        self.api = api
        self.identityStore = identityStore
        self.copy = copy
        self.platform = platform
        self.appVersion = appVersion
        self.now = now
    }

    /// Consulta feita ao abrir o app. Só a primeira chamada faz efeito.
    public func syncAtStartup() {
        guard !startupSyncStarted else { return }
        startupSyncStarted = true
        Task { await sync() }
    }

    /// Consulta o servidor agora (botão Recarregar, chave nova). Os pedidos que chegam com uma
    /// consulta em andamento viram uma consulta só, feita logo depois dela: assim a chave trocada
    /// no meio do caminho sempre chega ao servidor.
    public func sync() async {
        syncRequested = true
        await exclusive { [self] in
            // Outro pedido, que estava na fila junto com este, já fez a consulta.
            guard syncRequested else { return }
            syncRequested = false
            loadCopyIfNeeded()
            update { $0.syncing = true; $0.problem = nil; $0.problemStatus = nil }
            let outcome: Outcome
            if let credentials = try? identityStore.credentials() {
                outcome = await talkToServer(credentials)
            } else {
                // O cofre do aparelho falhou: não há como se apresentar ao servidor agora.
                outcome = .failed(.offline, status: nil)
            }
            apply(outcome)
            update { $0.syncing = false }
        }
    }

    /// Manda ao servidor um código de ativação digitado pelo usuário (Conta › "Tenho um código").
    /// O aparelho se registra antes (pode ser a primeira vez com internet) e, aceito o código, pede
    /// a situação nova, que vai para a tela. Nunca em laço: uma chamada por toque no botão.
    public func activateWithCode(_ code: String) async -> CodeResult {
        await exclusive { [self] in
            await sendCode(code)
        }
    }

    /// Tira o aparelho do painel do parceiro que cuida dele (botão "Desconectar do painel").
    /// O aparelho se registra antes e, feito o pedido, pede a situação nova (as listas e a ativação
    /// continuam; só o parceiro deixa de ver o aparelho). Uma chamada por toque no botão.
    public func unlink() async -> UnlinkResult {
        await exclusive { [self] in
            await sendUnlink()
        }
    }

    /// O servidor responde? (Só um `GET /ping`, sem o ID nem o segredo.)
    public func ping() async -> Bool {
        if case .ok = await api.ping() { return true }
        return false
    }

    /// O aparelho está ativo agora (conferindo se a ativação não venceu)?
    public func isActive() -> Bool {
        loadCopyIfNeeded()
        dropIfExpired()
        return state.status == .active
    }

    /// A lista com esse número, ou `nil` se o aparelho não a tem (mais).
    public func playlist(id: Int64) -> SitePlaylist? {
        loadCopyIfNeeded()
        dropIfExpired()
        return state.playlists.first { $0.id == id }
    }

    /// Esconde as listas se a ativação venceu enquanto o app estava aberto.
    public func dropIfExpired() {
        guard dropExpired() else { return }
        // A cópia guardada também sai (acertar o relógio para trás não a traz de volta), mas na
        // vez dela: nunca no meio de uma consulta, que pode estar gravando uma cópia nova.
        Task {
            await exclusive { [self] in
                if state.status != .active { copy.delete() }
            }
        }
    }

    // MARK: - Fila

    /// Roda `work` depois de tudo o que já estava na fila, e devolve o resultado dele.
    private func exclusive<Value: Sendable>(_ work: @escaping @MainActor () async -> Value) async -> Value {
        let previous = tail
        let task = Task { @MainActor () -> Value in
            await previous?.value
            return await work()
        }
        tail = Task { @MainActor in
            _ = await task.value
        }
        return await task.value
    }

    private func update(_ change: (inout SiteListsState) -> Void) {
        var next = state
        change(&next)
        state = next
    }

    // MARK: - Código de ativação

    private func sendCode(_ code: String) async -> CodeResult {
        loadCopyIfNeeded()
        update { $0.syncing = true }
        defer { update { $0.syncing = false } }

        guard let credentials = try? identityStore.credentials() else {
            return .failed(.offline, status: nil)
        }
        switch await api.register(credentials, platform: platform, appVersion: appVersion) {
        case .ok: break
        case .refused(let status, let error): return codeRefused(status: status, error: error)
        case .unavailable: return .failed(.offline, status: nil)
        }
        let answer: CodeAnswer
        switch await api.activateWithCode(deviceId: credentials.id, secret: credentials.secret, code: code) {
        case .ok(let value): answer = value
        case .refused(let status, let error): return codeRefused(status: status, error: error)
        case .unavailable: return .failed(.offline, status: nil)
        }
        // Ativado: a situação e as listas vêm do servidor, como ao abrir o app.
        await refreshAfterChange(credentials)
        return .activated(days: answer.days)
    }

    private func codeRefused(status: Int, error: String?) -> CodeResult {
        let problem: CodeProblem
        switch error {
        case "invalid_code": problem = .invalid
        case "code_unavailable": problem = .unavailable
        case "code_used": problem = .used
        case "already_active": problem = .alreadyActive
        case "device_managed": problem = .managed
        case "no_credits": problem = .noCredits
        default:
            switch status {
            case 401: problem = .refused
            case 429: problem = .tooManyAttempts
            default:
                // Bloqueado: as listas e a cópia saem do aparelho, como numa consulta comum.
                if status == 403 { apply(.blocked) }
                problem = .rejected
            }
        }
        return .failed(problem, status: status)
    }

    // MARK: - Desconectar do painel

    private func sendUnlink() async -> UnlinkResult {
        loadCopyIfNeeded()
        update { $0.syncing = true }
        defer { update { $0.syncing = false } }

        guard let credentials = try? identityStore.credentials() else {
            return .failed(.offline, status: nil)
        }
        switch await api.register(credentials, platform: platform, appVersion: appVersion) {
        case .ok: break
        case .refused(let status, _): return unlinkRefused(status: status)
        case .unavailable: return .failed(.offline, status: nil)
        }
        let answer: UnlinkAnswer
        switch await api.unlink(deviceId: credentials.id, secret: credentials.secret) {
        case .ok(let value): answer = value
        case .refused(let status, _): return unlinkRefused(status: status)
        case .unavailable: return .failed(.offline, status: nil)
        }
        // A situação nova (sem parceiro) vem do servidor, como ao abrir o app.
        await refreshAfterChange(credentials)
        return answer.unlinked ? .unlinked : .notLinked
    }

    private func unlinkRefused(status: Int) -> UnlinkResult {
        let problem: UnlinkProblem
        switch status {
        case 401: problem = .refused
        case 404: problem = .unavailable
        case 429: problem = .tooManyAttempts
        default:
            // Bloqueado: as listas e a cópia saem do aparelho, como numa consulta comum.
            if status == 403 { apply(.blocked) }
            problem = .rejected
        }
        return .failed(problem, status: status)
    }

    private func refreshAfterChange(_ credentials: DeviceCredentials) async {
        switch await api.playlists(deviceId: credentials.id, secret: credentials.secret) {
        case .ok(let answer): apply(.answered(answer))
        case .refused(let status, _): apply(refused(status: status))
        case .unavailable: apply(.failed(.offline, status: nil))
        }
    }

    // MARK: - Consulta

    private enum Outcome {
        case answered(PlaylistsAnswer)
        case blocked
        case failed(SyncProblem, status: Int?)
    }

    private func talkToServer(_ credentials: DeviceCredentials) async -> Outcome {
        // O registro é barato e vai sempre na frente: é ele que leva ao servidor a chave nova
        // (depois de "Nova chave" ou de reinstalar o app) e a versão do app.
        switch await api.register(credentials, platform: platform, appVersion: appVersion) {
        case .ok: break
        case .refused(let status, _): return refused(status: status)
        case .unavailable: return .failed(.offline, status: nil)
        }
        switch await api.playlists(deviceId: credentials.id, secret: credentials.secret) {
        case .ok(let answer): return .answered(answer)
        case .refused(let status, _): return refused(status: status)
        case .unavailable: return .failed(.offline, status: nil)
        }
    }

    private func refused(status: Int) -> Outcome {
        switch status {
        case 401: return .failed(.refused, status: nil)
        case 403: return .blocked
        case 429: return .failed(.tooManyAttempts, status: nil)
        default: return .failed(.rejected, status: status)
        }
    }

    private func apply(_ outcome: Outcome) {
        switch outcome {
        case .answered(let answer):
            if let serverTime = answer.serverTime {
                clockOffset = serverTime.timeIntervalSince(now())
            }
            if answer.active, !isOver(answer.expiresAt) {
                copy.write(Data(answer.raw.utf8))
                state = SiteListsState(
                    status: .active,
                    playlists: answer.playlists,
                    expiresAt: answer.expiresAt,
                    syncing: state.syncing,
                    partner: answer.partner
                )
            } else {
                // Não ativo: as listas vindas do servidor saem do aparelho.
                copy.delete()
                // A data de uma ativação que já venceu fica guardada: a tela inicial avisa que venceu.
                state = SiteListsState(
                    status: .inactive,
                    expiresAt: isOver(answer.expiresAt) ? answer.expiresAt : nil,
                    syncing: state.syncing,
                    partner: answer.partner
                )
            }

        case .blocked:
            copy.delete()
            state = SiteListsState(status: .blocked, syncing: state.syncing)

        case .failed(let problem, let status):
            // Fica com o que já tinha (a cópia guardada), a não ser que a ativação tenha vencido.
            if dropExpired() { copy.delete() }
            update { $0.problem = problem; $0.problemStatus = status }
        }
    }

    // MARK: - Validade e cópia guardada

    /// Tira as listas da tela se a ativação venceu. Devolve se tirou.
    private func dropExpired() -> Bool {
        guard state.status == .active, isOver(state.expiresAt) else { return false }
        // A data fica guardada: a tela inicial mostra que a ativação venceu.
        update { $0.status = .inactive; $0.playlists = [] }
        return true
    }

    private func isOver(_ expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now().addingTimeInterval(clockOffset)
    }

    /// Antes da primeira consulta, mostra a cópia guardada (se a ativação dela ainda vale).
    private func loadCopyIfNeeded() {
        guard !copyLoaded else { return }
        copyLoaded = true
        guard let data = copy.read() else { return }
        guard let answer = try? parsePlaylistsAnswer(String(decoding: data, as: UTF8.self)) else { return }
        if answer.active, !isOver(answer.expiresAt) {
            update {
                $0.status = .active
                $0.playlists = answer.playlists
                $0.expiresAt = answer.expiresAt
                $0.partner = answer.partner
            }
        } else {
            copy.delete()
        }
    }
}
