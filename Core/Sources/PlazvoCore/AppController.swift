import Foundation

/// Qual tela está aberta.
public enum AppScreen: Equatable, Sendable {
    case home
    case account
}

/// Qual caixa está aberta por cima da tela.
public enum AppDialog: Equatable, Sendable {
    /// "Código de ativação" (Conta › "Tenho um código de ativação").
    case code
    /// "Gerar uma nova chave?"
    case newKey
    /// "Desconectar do painel?"
    case unlink
}

/// O que o botão de copiar copia: o ID ou a chave.
public enum CopyField: Equatable, Sendable {
    case id
    case key
}

/// Aviso curto, que aparece embaixo da tela por um instante.
public struct Notice: Equatable, Sendable {
    public let text: TextRef
    /// Com o sinal de "certo" (deu certo) ou sem ele (não deu).
    public let done: Bool

    public init(_ text: TextRef, done: Bool) {
        self.text = text
        self.done = done
    }
}

/// Tudo o que as telas mostram: o ID e a chave, a situação no servidor, o andamento dos pedidos
/// do usuário e o que está aberto.
public struct AppState: Equatable, Sendable {
    /// O ID e a chave; `nil` até o cofre responder (ou se ele não pôde ser usado).
    public var identity: DeviceIdentity?
    public var site = SiteListsState()

    /// Há um código de ativação a caminho do servidor.
    public var activating = false
    /// Resultado do último código enviado (`nil`: nenhum, ou já foi visto).
    public var codeResult: CodeResult?

    /// Há um pedido de sair do painel a caminho do servidor.
    public var unlinking = false
    /// Resultado do último pedido de sair do painel (`nil`: nenhum, ou já foi visto).
    public var unlinkResult: UnlinkResult?

    public var screen = AppScreen.home
    public var dialog: AppDialog?

    /// O que acabou de ser copiado (o botão de copiar mostra um "certo" enquanto isto vale).
    public var copied: CopyField?
    public var notice: Notice?

    public init() {}
}

/// O que está por trás das telas: recebe os toques, fala com a lógica e avisa a cada mudança.
/// Não sabe desenhar nada. Use uma única instância por app.
@MainActor
public final class AppController {
    /// O estado atual. Muda sempre de uma vez só (as telas nunca veem um estado pela metade).
    public private(set) var state = AppState() {
        didSet {
            if state != oldValue { onChange?(state) }
        }
    }

    /// Chamado a cada mudança do estado.
    public var onChange: ((AppState) -> Void)?

    private let identityStore: DeviceIdentityStore
    private let siteLists: SiteLists
    private let copyText: (String) -> Void
    private let noticeSeconds: Double?
    private var started = false
    private var noticeEnd: Task<Void, Never>?

    /// - Parameters:
    ///   - copyText: põe um texto na área de transferência do aparelho.
    ///   - noticeSeconds: por quanto tempo um aviso curto fica na tela; `nil`: até o próximo.
    public init(
        identityStore: DeviceIdentityStore,
        siteLists: SiteLists,
        copyText: @escaping (String) -> Void,
        noticeSeconds: Double? = 1.6
    ) {
        self.identityStore = identityStore
        self.siteLists = siteLists
        self.copyText = copyText
        self.noticeSeconds = noticeSeconds
        state.identity = identityStore.identity
        state.site = siteLists.state
        identityStore.onChange = { [weak self] identity in self?.state.identity = identity }
        siteLists.onChange = { [weak self] site in self?.state.site = site }
    }

    private func update(_ change: (inout AppState) -> Void) {
        var next = state
        change(&next)
        state = next
    }

    // MARK: - Abertura e consulta

    /// Ao abrir o app: cria (ou lê) o ID e a chave e consulta o servidor. Só a primeira chamada faz efeito.
    public func start() async {
        guard !started else { return }
        started = true
        // Cofre que não pôde ser lido: a tela fica sem o ID, e o Recarregar tenta de novo.
        _ = try? identityStore.ensureCreated()
        await siteLists.sync()
    }

    /// Botão Recarregar: consulta o servidor de novo.
    public func reload() async {
        await siteLists.sync()
    }

    /// Ao voltar para o app: se a ativação venceu com ele aberto, a tela mostra.
    public func checkExpiry() {
        siteLists.dropIfExpired()
    }

    // MARK: - Telas e caixas

    /// Botão Conta da tela inicial.
    public func openAccount() {
        update { $0.screen = .account }
    }

    /// Seta Voltar (e o gesto de voltar): fecha a caixa aberta ou, sem caixa, volta à tela inicial.
    public func back() {
        if state.dialog != nil {
            closeDialog()
        } else {
            update { $0.screen = .home }
        }
    }

    /// Conta › "Tenho um código de ativação".
    public func openCodeDialog() {
        update {
            // O aviso de uma tentativa anterior não volta numa caixa nova.
            if case .failed = $0.codeResult { $0.codeResult = nil }
            $0.dialog = .code
        }
    }

    /// Botão Nova chave: pergunta antes de trocar.
    public func openNewKeyDialog() {
        update { $0.dialog = .newKey }
    }

    /// Botão Desconectar do painel: pergunta antes de sair.
    public func openUnlinkDialog() {
        update {
            $0.unlinkResult = nil
            $0.dialog = .unlink
        }
    }

    /// Fecha a caixa aberta e descarta o resultado que ela mostrava.
    public func closeDialog() {
        update {
            if case .failed = $0.codeResult { $0.codeResult = nil }
            $0.unlinkResult = nil
            $0.dialog = nil
        }
    }

    // MARK: - Pedidos do usuário

    /// "Gerar nova chave" (depois da pergunta): troca a chave e leva a nova ao servidor. Se o cofre
    /// não gravar, a chave continua a mesma e a tela avisa.
    public func confirmNewKey() async {
        // Só com a caixa da pergunta aberta: dois toques seguidos no botão trocam a chave uma vez só.
        guard state.dialog == .newKey else { return }
        closeDialog()
        do {
            try identityStore.rotateKey()
        } catch {
            show(Notice(TextRef("new_key_failed"), done: false))
            return
        }
        // A chave nova só vale no site depois que o registro chega ao servidor.
        await siteLists.sync()
    }

    /// Caixa do código › Ativar: manda o código ao servidor. Um pedido por vez.
    public func activateWithCode(_ code: String) async {
        guard !state.activating else { return }
        update {
            $0.activating = true
            $0.codeResult = nil
        }
        let result = await siteLists.activateWithCode(code)
        update {
            $0.activating = false
            $0.codeResult = result
            // Código aceito: a caixa fecha e a situação nova aparece na Conta.
            if case .activated = result, $0.dialog == .code { $0.dialog = nil }
        }
    }

    /// Caixa "Desconectar do painel?" › Desconectar: um pedido por vez.
    public func unlink() async {
        guard !state.unlinking else { return }
        update {
            $0.unlinking = true
            $0.unlinkResult = nil
        }
        let result = await siteLists.unlink()
        update {
            $0.unlinking = false
            $0.unlinkResult = result
        }
    }

    /// Botão de copiar ao lado do ID e da chave. Só o ID ou a chave saem daqui; o segredo, nunca.
    public func copy(_ field: CopyField) {
        guard let identity = state.identity else { return }
        copyText(field == .id ? identity.id : identity.key)
        show(Notice(TextRef(field == .id ? "device_id_copied" : "device_key_copied"), done: true), copied: field)
    }

    // MARK: - Aviso curto

    private func show(_ notice: Notice, copied: CopyField? = nil) {
        noticeEnd?.cancel()
        update {
            $0.notice = notice
            $0.copied = copied
        }
        guard let noticeSeconds else { return }
        noticeEnd = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(noticeSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.update {
                $0.notice = nil
                $0.copied = nil
            }
        }
    }
}
