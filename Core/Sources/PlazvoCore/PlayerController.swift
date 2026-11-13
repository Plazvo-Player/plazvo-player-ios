import Foundation

/// Em que pé está o vídeo aberto.
public enum PlayerStatus: Equatable, Sendable {
    /// Abrindo: o endereço ainda não respondeu.
    case opening
    /// Esperando o vídeo chegar (antes de começar ou no meio dele).
    case buffering
    case playing
    case paused
    /// O vídeo chegou ao fim.
    case ended
}

/// Tudo o que a tela do reprodutor mostra.
public struct PlayerState: Equatable, Sendable {
    public let title: String
    public let kind: MediaKind
    public var status = PlayerStatus.opening
    public var positionMs: Int64 = 0
    /// 0 quando a duração não é conhecida (transmissão ao vivo).
    public var durationMs: Int64 = 0
    /// Dá para ir a outro ponto do vídeo (a barra de tempo e os botões de 10 segundos funcionam).
    public var seekable = false
    /// Falha que impede a reprodução, ou `nil` enquanto está tudo bem.
    public var problem: PlaybackProblem?
    /// Vídeo gravado em pé: a tela acompanha.
    public var portraitVideo = false
    /// Velocidade: 1 é a normal.
    public var rate: Double = 1
    public var audioTracks: [MediaTrack] = []
    public var audioTrack: Int?
    public var subtitleTracks: [MediaTrack] = []
    /// A legenda em uso, ou `nil` com as legendas desligadas.
    public var subtitleTrack: Int?
    /// Os controles estão na tela.
    public var controlsVisible = true

    public init(title: String, kind: MediaKind) {
        self.title = title
        self.kind = kind
    }

    /// A rodinha de espera: o vídeo ainda não chegou.
    public var waiting: Bool {
        problem == nil && (status == .opening || status == .buffering)
    }
}

/// Cuida de um vídeo aberto no reprodutor: abre, retoma de onde parou, guarda o progresso na lista
/// de recentes, traduz as falhas em mensagens e decide quando os controles aparecem. Não sabe
/// desenhar nada. Um por vídeo aberto.
@MainActor
public final class PlayerController {
    /// As velocidades que a tela oferece.
    public nonisolated static let rates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]
    /// Quanto os botões de voltar e avançar andam, em segundos.
    public nonisolated static let skipSeconds = 10

    /// De quanto em quanto tempo o reprodutor confere o vídeo, em segundos.
    public nonisolated static let tickSeconds = 0.5
    /// Os controles somem depois de 4 segundos sem toque (com o vídeo rodando).
    static let controlsTicks = 8
    /// O ponto do vídeo é guardado a cada 10 segundos enquanto ele roda.
    static let saveTicks = 20
    /// Um segundo e meio sem o vídeo andar: a rodinha de espera volta.
    static let stallTicks = 3
    /// Três segundos depois de abrir, um vídeo que não informa o tempo é dado por rodando.
    static let startTicks = 6
    /// Um segundo com o motor num estado diferente do pedido: a tela ou o motor se acertam.
    static let mismatchTicks = 2

    /// O estado atual. Muda sempre de uma vez só.
    public private(set) var state: PlayerState {
        didSet {
            if state != oldValue { onChange?(state) }
        }
    }

    /// Chamado a cada mudança do estado.
    public var onChange: ((PlayerState) -> Void)?

    public let request: PlaybackRequest
    public let engine: VideoEngine

    private let access: MediaAccess
    private let diagnosis: PlaybackDiagnosis
    private let recents: RecentMediaStore
    private let tickSeconds: Double?

    /// Só arquivos e links abertos pelo usuário ficam na lista de recentes (e são retomados).
    private let keptInRecents: Bool

    /// Em que pé o motor está.
    private enum Phase {
        /// O endereço ainda não respondeu.
        case opening
        /// O motor está juntando vídeo para começar.
        case buffering
        /// O vídeo abriu; falta a imagem começar a andar (há quantas conferências).
        case starting(ticks: Int)
        case ready
        /// Deu erro; o motivo está sendo conferido.
        case failed
    }

    private var phase = Phase.opening

    /// O motor já abriu o vídeo desta abertura. Antes disso ele não recebe pedido de pausar nem
    /// de continuar: uma pausa no meio da abertura faz o motor desistir dela, e a tela acabaria
    /// mostrando uma falha que não houve.
    private var engineOpened: Bool {
        switch phase {
        case .starting, .ready: return true
        case .opening, .buffering, .failed: return false
        }
    }
    /// O que o usuário quer: o vídeo rodando ou parado.
    private var wantsPlay = true
    private var ended = false
    private var stalled = false

    private var started = false
    private var closed = false
    /// O endereço que o motor abre (com o acesso ao arquivo aberto), ou `nil` se o vídeo sumiu.
    private var address: String?
    private var accessOpen = false
    /// Muda a cada abertura: o que sobra de uma abertura anterior é ignorado.
    private var opening = 0
    /// O ponto pedido na última abertura.
    private var openedAtMs: Int64 = 0
    /// O ponto do último aviso de tempo desta abertura.
    private var lastEventPositionMs: Int64?
    private var listedInRecents = false
    /// O vídeo chegou a tocar alguma coisa, em qualquer abertura.
    public private(set) var hasPlayed = false
    /// O vídeo chegou a abrir (o motor achou vídeo no endereço).
    private var everOpened = false
    /// O vídeo informa o tempo (ele já andou alguma vez).
    private var timeMoves = false
    private var sawPicture = false

    private var idleTicks = 0
    private var stillTicks = 0
    private var playingTicks = 0
    private var mismatchedTicks = 0
    private var lastTickPositionMs: Int64 = 0
    private var ticker: Task<Void, Never>?
    private var checking: Task<Void, Never>?

    /// - Parameters:
    ///   - tickSeconds: de quanto em quanto tempo `tick()` é chamado sozinho; `nil`: só quem usa
    ///     chama (os testes e as cenas das fotos).
    public init(
        request: PlaybackRequest,
        engine: VideoEngine,
        access: MediaAccess,
        diagnosis: PlaybackDiagnosis,
        recents: RecentMediaStore,
        tickSeconds: Double? = PlayerController.tickSeconds
    ) {
        self.request = request
        self.engine = engine
        self.access = access
        self.diagnosis = diagnosis
        self.recents = recents
        self.tickSeconds = tickSeconds
        keptInRecents = request.kind == .file || request.kind == .link
        state = PlayerState(title: request.title, kind: request.kind)
    }

    // MARK: - Abrir e fechar

    /// Abre o vídeo, continuando de onde o usuário parou da última vez. Só a primeira chamada
    /// faz efeito.
    public func start() {
        guard !started, !closed else { return }
        started = true
        engine.onEvent = { [weak self] event in self?.handle(event) }
        let resumeMs = keptInRecents ? (recents.find(request.uri)?.resumePositionMs ?? 0) : 0
        open(atMs: resumeMs)
        startTicker()
    }

    /// Fecha o reprodutor: guarda o ponto, para o motor e devolve o acesso ao arquivo.
    public func close() {
        guard !closed else { return }
        saveProgress()
        closed = true
        ticker?.cancel()
        checking?.cancel()
        engine.onEvent = nil
        if started { engine.stop() }
        if accessOpen {
            accessOpen = false
            access.close()
        }
    }

    /// Ao sair do app (ele vai para o fundo): pausa e guarda o ponto.
    public func enterBackground() {
        guard started, !closed else { return }
        if wantsPlay, !ended, state.problem == nil {
            wantsPlay = false
            // Com o vídeo ainda abrindo, o pedido fica guardado e vale quando ele abrir.
            if engineOpened { engine.pause() }
        }
        saveProgress()
        update { $0.controlsVisible = true }
    }

    /// Tenta de novo depois de uma falha, do ponto onde estava.
    public func retry() {
        guard started, !closed, state.problem != nil else { return }
        wantsPlay = true
        // Vídeo que já tinha andado volta ao ponto em que estava; o que nem abriu, ao ponto pedido.
        open(atMs: state.durationMs > 0 ? state.positionMs : openedAtMs)
    }

    private func open(atMs startMs: Int64) {
        opening += 1
        checking?.cancel()
        phase = .opening
        ended = false
        stalled = false
        everOpened = false
        timeMoves = false
        sawPicture = false
        stillTicks = 0
        mismatchedTicks = 0
        idleTicks = 0
        openedAtMs = max(startMs, 0)
        lastTickPositionMs = openedAtMs
        lastEventPositionMs = nil

        if address == nil {
            // O acesso de uma tentativa anterior é devolvido antes de pedir outro.
            if accessOpen { access.close() }
            accessOpen = true
            if let found = access.open(request) {
                // Letra acentuada num link vira o código dela, que é como o endereço viaja.
                address = request.kind == .link ? VideoLink.encoded(found) : found
            }
        }
        guard let address else {
            phase = .failed
            update {
                $0.problem = problemFor(kind: self.request.kind, failure: .notFound)
                $0.controlsVisible = false
            }
            return
        }
        update {
            $0.problem = nil
            $0.positionMs = self.openedAtMs
            $0.controlsVisible = true
        }
        engine.open(uri: address, startAtMs: openedAtMs)
        if state.rate != 1 { engine.rate = state.rate }
    }

    // MARK: - O que o motor avisa

    private func handle(_ event: EngineEvent) {
        guard started, !closed else { return }
        switch event {
        case .opening:
            break
        case .buffering:
            // Só conta antes de o vídeo abrir; depois, a espera é medida pelo tempo parado.
            if case .opening = phase {
                phase = .buffering
                update { _ in }
            }
        case .playing:
            opened()
        case .time(let positionMs, let durationMs):
            timeChanged(positionMs: positionMs, durationMs: durationMs)
        case .videoSize(let width, let height):
            guard width > 0, height > 0 else { return }
            sawPicture = true
            if everOpened { markPlayed() }
            update { $0.portraitVideo = height > width }
        case .tracksChanged:
            update { self.readTracks(into: &$0) }
        case .ended:
            reachedEnd()
        case .failed:
            failed()
        }
    }

    /// O motor achou vídeo no endereço.
    private func opened() {
        switch phase {
        case .opening, .buffering:
            phase = .starting(ticks: 0)
        case .starting, .ready, .failed:
            return
        }
        everOpened = true
        if sawPicture { markPlayed() }
        update {
            $0.seekable = self.engine.isSeekable
            $0.durationMs = max(self.engine.durationMs, 0)
            self.readTracks(into: &$0)
        }
        // Pausado antes de abrir: o pedido vale agora.
        if !wantsPlay { engine.pause() }
    }

    /// O vídeo mostrou alguma coisa (apareceu imagem, o tempo andou, ou passou o instante de
    /// espera do vídeo que não informa o tempo): só então ele entra na lista de recentes. Um
    /// endereço que abre e não toca nada (uma lista de vídeos, uma página) não entra.
    private func markPlayed() {
        hasPlayed = true
        guard keptInRecents, !listedInRecents else { return }
        listedInRecents = true
        recents.markOpened(request)
    }

    private func timeChanged(positionMs: Int64, durationMs: Int64) {
        guard !ended, state.problem == nil else { return }
        if case .failed = phase { return }
        let position = max(positionMs, 0)
        if let last = lastEventPositionMs, last != position {
            // O tempo andou: o vídeo está mesmo rodando.
            timeMoves = true
            switch phase {
            case .opening, .buffering:
                // O aviso de que o vídeo abriu não chegou; o tempo andando vale por ele.
                opened()
            case .starting, .ready, .failed:
                break
            }
            if case .starting = phase { phase = .ready }
            markPlayed()
            stillTicks = 0
            stalled = false
        }
        lastEventPositionMs = position
        update {
            $0.positionMs = position
            if durationMs > 0 { $0.durationMs = durationMs }
            $0.seekable = self.engine.isSeekable
        }
    }

    private func reachedEnd() {
        guard !ended, state.problem == nil else { return }
        // Erro seguido de "fim": vale o erro.
        if case .failed = phase { return }
        // "Fim" sem nunca ter mostrado nada: o endereço não era um vídeo.
        guard everOpened, timeMoves || sawPicture || state.durationMs > 0 else {
            failed()
            return
        }
        // "Fim" longe do fim de um vídeo de duração conhecida: o vídeo parou de chegar (a conexão
        // caiu, o arquivo está cortado). Não conta como assistido: o ponto fica guardado e a tela
        // oferece tentar de novo dali.
        if state.durationMs > 0, !RecentMedia.isNearEnd(positionMs: state.positionMs, durationMs: state.durationMs) {
            failed(interrupted: true)
            return
        }
        ended = true
        stalled = false
        saveProgress()
        update {
            if $0.durationMs > 0 { $0.positionMs = $0.durationMs }
            $0.controlsVisible = true
        }
    }

    /// O motor só diz que deu erro: o motivo é conferido à parte, e a tela espera por ele.
    /// - Parameter interrupted: o vídeo estava rodando e parou de chegar no meio.
    private func failed(interrupted: Bool = false) {
        if case .failed = phase { return }
        // Erro depois do fim de verdade: o vídeo já acabou, não há o que avisar.
        guard !ended, state.problem == nil else { return }
        phase = .failed
        stalled = false
        // O ponto em que parou fica guardado, para continuar dali.
        saveProgress()
        update { _ in }
        let current = opening
        let kind = request.kind
        let address = self.address ?? ""
        let diagnosis = self.diagnosis
        checking = Task { [weak self] in
            var failure = await diagnosis.failure(of: kind, address: address)
            // O formato não é o problema de um vídeo que já estava rodando.
            if interrupted, failure == .format { failure = .unknown }
            guard !Task.isCancelled, let self, !self.closed, self.opening == current else { return }
            if case .notFound = failure {
                // O arquivo sumiu: na próxima tentativa o acesso é pedido de novo.
                self.address = nil
            }
            self.update {
                $0.problem = problemFor(kind: kind, failure: failure)
                $0.controlsVisible = false
            }
        }
    }

    private func readTracks(into state: inout PlayerState) {
        state.audioTracks = engine.audioTracks
        state.audioTrack = engine.audioTrack
        state.subtitleTracks = engine.subtitleTracks
        state.subtitleTrack = engine.subtitleTrack
    }

    // MARK: - Toques do usuário

    /// Botão do meio: pausa, continua ou, com o vídeo terminado, começa de novo.
    public func togglePlay() {
        guard started, !closed, state.problem == nil else { return }
        if ended {
            wantsPlay = true
            open(atMs: 0)
            return
        }
        wantsPlay.toggle()
        // Com o vídeo ainda abrindo, o pedido fica guardado e vale quando ele abrir.
        if engineOpened {
            if wantsPlay { engine.play() } else { engine.pause() }
        }
        if !wantsPlay { saveProgress() }
        mismatchedTicks = 0
        stillTicks = 0
        stalled = false
        idleTicks = 0
        update { $0.controlsVisible = true }
    }

    /// Botões de voltar e avançar 10 segundos (`seconds` negativo volta).
    public func skip(seconds: Int) {
        seek(toMs: state.positionMs + Int64(seconds) * 1000)
    }

    /// Barra de tempo: vai para o ponto pedido.
    public func seek(toMs target: Int64) {
        guard started, !closed, state.problem == nil else { return }
        var position = max(target, 0)
        if state.durationMs > 0 { position = min(position, state.durationMs) }
        idleTicks = 0
        if ended {
            // Depois do fim, voltar reabre o vídeo no ponto pedido (um pouco antes do fim, no máximo).
            guard state.durationMs > 0 else { return }
            wantsPlay = true
            open(atMs: min(position, max(state.durationMs - 1000, 0)))
            return
        }
        guard state.seekable else { return }
        engine.seek(toMs: position)
        stillTicks = 0
        stalled = false
        lastTickPositionMs = position
        update { $0.positionMs = position }
    }

    /// Velocidade do vídeo (uma das de `rates`).
    public func setRate(_ rate: Double) {
        guard started, !closed, PlayerController.rates.contains(rate) else { return }
        engine.rate = rate
        idleTicks = 0
        update { $0.rate = rate }
    }

    public func selectAudio(_ id: Int) {
        guard started, !closed, state.audioTracks.contains(where: { $0.id == id }) else { return }
        engine.audioTrack = id
        idleTicks = 0
        update { $0.audioTrack = id }
    }

    /// Escolhe a legenda; `nil` desliga as legendas.
    public func selectSubtitle(_ id: Int?) {
        guard started, !closed else { return }
        if let id, !state.subtitleTracks.contains(where: { $0.id == id }) { return }
        engine.subtitleTrack = id
        idleTicks = 0
        update { $0.subtitleTrack = id }
    }

    /// Toque no vídeo: mostra os controles ou, se já estão na tela, esconde.
    public func tapVideo() {
        guard started, !closed, state.problem == nil else { return }
        idleTicks = 0
        update { $0.controlsVisible.toggle() }
    }

    /// O usuário está mexendo nos controles (arrastando a barra, com um menu aberto): eles ficam.
    public func keepControls() {
        idleTicks = 0
    }

    // MARK: - Conferência a cada meio segundo

    private func startTicker() {
        guard let tickSeconds, ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tickSeconds * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    /// Confere o vídeo: o ponto atual, se ele parou de andar, se o motor está como o usuário
    /// pediu, a hora de guardar o ponto e a hora de esconder os controles.
    public func tick() {
        guard started, !closed, state.problem == nil, !ended else { return }
        if case .failed = phase { return }

        var isReady = false
        var show = false
        switch phase {
        case .starting(let ticks):
            // Vídeo que não informa o tempo: passado um instante, é dado por rodando.
            if wantsPlay, ticks + 1 >= PlayerController.startTicks {
                phase = .ready
                isReady = true
                markPlayed()
            } else if wantsPlay {
                phase = .starting(ticks: ticks + 1)
            }
        case .ready:
            isReady = true
        case .opening, .buffering, .failed:
            break
        }

        if isReady {
            // O motor num estado diferente do pedido por um segundo seguido.
            if engine.isPlaying != wantsPlay {
                mismatchedTicks += 1
            } else {
                mismatchedTicks = 0
            }
            if mismatchedTicks >= PlayerController.mismatchTicks {
                mismatchedTicks = 0
                if wantsPlay {
                    // O motor parou sozinho (uma ligação, outro app tomou o som): a tela acompanha.
                    wantsPlay = false
                    show = true
                    saveProgress()
                } else {
                    // O motor não atendeu ao pedido de pausa: pede de novo.
                    engine.pause()
                }
            }

            // A rodinha de espera, quando o vídeo que informa o tempo para de andar.
            let position = state.positionMs
            if wantsPlay, timeMoves, position == lastTickPositionMs {
                stillTicks += 1
            } else {
                stillTicks = 0
            }
            lastTickPositionMs = position
            stalled = wantsPlay && stillTicks >= PlayerController.stallTicks
        }

        let status = currentStatus
        if status == .playing {
            playingTicks += 1
            if playingTicks % PlayerController.saveTicks == 0 { saveProgress() }
        }

        // Com o vídeo rodando, os controles somem depois de um tempo sem toque; pausado, ficam.
        var hide = false
        if state.controlsVisible, wantsPlay {
            idleTicks += 1
            hide = idleTicks >= PlayerController.controlsTicks
        }
        update {
            if hide { $0.controlsVisible = false }
            if show { $0.controlsVisible = true }
        }
    }

    // MARK: - Progresso

    /// Guarda o ponto atual do vídeo, para continuar depois.
    public func saveProgress() {
        guard listedInRecents, !closed else { return }
        let durationMs = max(state.durationMs, 0)
        let resumable = durationMs > 0 && state.seekable && !ended
        recents.savePosition(request.uri, positionMs: resumable ? state.positionMs : 0, durationMs: durationMs)
    }

    // MARK: - Estado

    private var currentStatus: PlayerStatus {
        if ended { return .ended }
        if !wantsPlay { return .paused }
        switch phase {
        case .opening, .failed: return .opening
        case .buffering, .starting: return .buffering
        case .ready: return stalled ? .buffering : .playing
        }
    }

    private func update(_ change: (inout PlayerState) -> Void) {
        var next = state
        change(&next)
        next.status = currentStatus
        state = next
    }
}
