import Foundation

/// Qual tela está aberta.
public enum AppScreen: Equatable, Sendable {
    case home
    case account
    /// Mídia: os três caminhos para abrir um vídeo e os vídeos recentes.
    case media
    /// "Abrir link de vídeo".
    case openLink
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

    /// Os vídeos abertos recentemente (tela Mídia), do mais recente para o mais antigo.
    public var recents: [RecentMedia] = []
    /// "Abrir link de vídeo": o último endereço tentado não é um endereço que valha.
    public var linkInvalid = false
    /// O vídeo aberto no reprodutor, que fica por cima de qualquer tela; `nil`: nenhum.
    public var playing: PlaybackRequest?

    /// O que acabou de ser copiado (o botão de copiar mostra um "certo" enquanto isto vale).
    public var copied: CopyField?
    public var notice: Notice?

    public init() {}
}

/// O que o reprodutor precisa do aparelho: o motor de vídeo, o acesso aos vídeos e a conferência
/// das falhas.
public struct PlaybackParts {
    /// Cria o motor de vídeo de cada vídeo aberto.
    public let makeEngine: @MainActor () -> VideoEngine
    public let access: MediaAccess
    public let diagnosis: PlaybackDiagnosis
    /// De quanto em quanto tempo o reprodutor confere o vídeo; `nil`: só quem usa chama.
    public let tickSeconds: Double?

    public init(
        makeEngine: @escaping @MainActor () -> VideoEngine,
        access: MediaAccess,
        diagnosis: PlaybackDiagnosis,
        tickSeconds: Double? = PlayerController.tickSeconds
    ) {
        self.makeEngine = makeEngine
        self.access = access
        self.diagnosis = diagnosis
        self.tickSeconds = tickSeconds
    }
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

    /// O reprodutor do vídeo aberto (`state.playing`), ou `nil`.
    public private(set) var player: PlayerController?

    /// O último endereço tentado em "Abrir link de vídeo" que não chegou a tocar, para corrigir
    /// sem digitar tudo de novo. Some quando o vídeo toca (aí ele está na lista de recentes, sem
    /// o endereço à mostra) e quando a lista de recentes é limpa. Fica fora do estado das telas:
    /// pode levar usuário e senha.
    public private(set) var lastLink = ""

    private let identityStore: DeviceIdentityStore
    private let siteLists: SiteLists
    private let recentMedia: RecentMediaStore
    private let playback: PlaybackParts
    private let copyText: (String) -> Void
    private let noticeSeconds: Double?
    private var started = false
    private var noticeEnd: Task<Void, Never>?

    /// - Parameters:
    ///   - recentMedia: os vídeos abertos recentemente, guardados no aparelho.
    ///   - playback: o que o reprodutor precisa do aparelho.
    ///   - copyText: põe um texto na área de transferência do aparelho.
    ///   - noticeSeconds: por quanto tempo um aviso curto fica na tela; `nil`: até o próximo.
    public init(
        identityStore: DeviceIdentityStore,
        siteLists: SiteLists,
        recentMedia: RecentMediaStore,
        playback: PlaybackParts,
        copyText: @escaping (String) -> Void,
        noticeSeconds: Double? = 1.6
    ) {
        self.identityStore = identityStore
        self.siteLists = siteLists
        self.recentMedia = recentMedia
        self.playback = playback
        self.copyText = copyText
        self.noticeSeconds = noticeSeconds
        state.identity = identityStore.identity
        state.site = siteLists.state
        state.recents = recentMedia.items
        identityStore.onChange = { [weak self] identity in self?.state.identity = identity }
        siteLists.onChange = { [weak self] site in self?.state.site = site }
        recentMedia.onChange = { [weak self] items in self?.state.recents = items }
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

    /// Cartão Mídia da tela inicial.
    public func openMedia() {
        update { $0.screen = .media }
    }

    /// Mídia › "Abrir link de vídeo".
    public func openLinkScreen() {
        update {
            $0.linkInvalid = false
            $0.screen = .openLink
        }
    }

    /// Seta Voltar (e o gesto de voltar): fecha a caixa aberta; sem caixa, sai do vídeo; sem
    /// vídeo, volta uma tela ("Abrir link" volta para Mídia; as outras, para a tela inicial).
    public func back() {
        if state.dialog != nil {
            closeDialog()
        } else if state.playing != nil {
            closePlayer()
        } else {
            update { $0.screen = $0.screen == .openLink ? .media : .home }
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

    // MARK: - Mídia e vídeo

    /// Mídia › "Vídeo de demonstração". `title` é o nome dele no idioma do app.
    public func playDemo(title: String) {
        play(PlaybackRequest(kind: .demo, uri: "", title: title))
    }

    /// "Abrir link de vídeo" › Abrir (ou o "ir" do teclado). Endereço que não vale: a tela avisa
    /// e nada abre. Devolve se abriu.
    @discardableResult
    public func openLink(_ text: String) -> Bool {
        guard let url = VideoLink.normalize(text) else {
            update { $0.linkInvalid = true }
            return false
        }
        lastLink = url
        update {
            $0.linkInvalid = false
            // Depois do vídeo, voltar leva para a tela Mídia (e não para o campo do link).
            $0.screen = .media
        }
        play(PlaybackRequest(kind: .link, uri: url, title: VideoLink.title(url)))
        return true
    }

    /// O usuário mexeu no campo do link: o aviso de endereço errado some.
    public func linkEdited() {
        update { $0.linkInvalid = false }
    }

    /// Mídia › "Procurar vídeo no aparelho", depois de o usuário escolher o arquivo.
    /// - Parameters:
    ///   - uri: o endereço do arquivo no aparelho.
    ///   - title: o nome do arquivo.
    ///   - access: o marcador que o sistema entregou para o app voltar a ler o arquivo depois.
    public func playFile(uri: String, title: String, access: Data?) {
        play(PlaybackRequest(kind: .file, uri: uri, title: title, access: access))
    }

    /// Toque num vídeo recente: abre e continua de onde parou.
    public func openRecent(_ item: RecentMedia) {
        play(item.request)
    }

    /// Mídia › Recentes › Limpar. O último endereço tentado vai junto.
    public func clearRecents() {
        recentMedia.clear()
        lastLink = ""
    }

    /// Sai do reprodutor: a seta de voltar dele, o gesto de voltar ou "Voltar" na mensagem de falha.
    public func closePlayer() {
        guard player != nil else { return }
        finishPlayer()
        update { $0.playing = nil }
    }

    /// Fecha o reprodutor aberto, se houver.
    private func finishPlayer() {
        guard let open = player else { return }
        player = nil
        open.close()
        // O link que tocou não precisa de conserto: o endereço dele não volta para a tela.
        if open.hasPlayed, open.request.kind == .link, open.request.uri == lastLink { lastLink = "" }
    }

    private func play(_ request: PlaybackRequest) {
        // Um pedido novo recomeça o reprodutor do zero.
        finishPlayer()
        let controller = PlayerController(
            request: request,
            engine: playback.makeEngine(),
            access: playback.access,
            diagnosis: playback.diagnosis,
            recents: recentMedia,
            tickSeconds: playback.tickSeconds
        )
        player = controller
        update { $0.playing = request }
        controller.start()
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
