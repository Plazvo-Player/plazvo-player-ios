import Foundation
@testable import PlazvoCore

/// Relógio de mentira, que o teste adianta quando quer.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ text: String = "2026-10-05T19:00:00Z") {
        value = parseServerTime(text)!
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ text: String) {
        lock.lock()
        value = parseServerTime(text)!
        lock.unlock()
    }
}

/// Sorteio previsível: os bytes e os números saem de uma conta simples, sempre na mesma ordem.
func predictableRandom(seed: UInt64 = 1) -> RandomSource {
    final class State { var value: UInt64; init(_ value: UInt64) { self.value = value } }
    let state = State(seed)
    func next() -> UInt64 {
        state.value = state.value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state.value >> 33
    }
    return RandomSource(
        bytes: { count in (0..<count).map { _ in UInt8(truncatingIfNeeded: next()) } },
        number: { range in range.lowerBound + Int(next() % UInt64(range.count)) }
    )
}

/// Tudo o que um teste da situação do aparelho precisa, já ligado: servidor de mentira, cofre,
/// cópia guardada e relógio.
@MainActor
final class Bench {
    let clock = TestClock()
    let site: FakeSite
    let secure = InMemorySecureStore()
    let copy = InMemoryCopyStore()
    let identity: DeviceIdentityStore
    private(set) var lists: SiteLists
    private(set) var changes: [SiteListsState] = []

    init() {
        let clock = self.clock
        site = FakeSite(now: { clock.now })
        identity = DeviceIdentityStore(store: secure, random: predictableRandom())
        lists = SiteLists(api: site, identityStore: identity, copy: copy, platform: "ios", appVersion: "0.1.0", now: { clock.now })
        lists.onChange = { [unowned self] in self.changes.append($0) }
    }

    /// O app foi fechado e aberto de novo: a situação começa do zero, com o mesmo cofre e a mesma cópia.
    func reopen() {
        let clock = self.clock
        lists = SiteLists(api: site, identityStore: identity, copy: copy, platform: "ios", appVersion: "0.1.0", now: { clock.now })
        changes = []
        lists.onChange = { [unowned self] in self.changes.append($0) }
    }

    var state: SiteListsState { lists.state }

    func deviceId() throws -> String {
        try identity.ensureCreated().id
    }

    /// Todo aparelho passa a estar ativo, com estas listas, até `expiresAt`.
    func activateAll(_ playlists: [FakeSite.List] = [], expiresAt: String = "2027-10-02T22:40:23Z", partner: Bool = false) async {
        await site.setSetup { device in
            device.active = true
            device.expiresAt = expiresAt
            device.playlists = playlists
            device.partner = partner
        }
    }
}

let serverList = FakeSite.List(id: 7, name: "Casa", url: "http://servidor.exemplo:8080")
let linkList = FakeSite.List(id: 9, name: "Sala", type: "m3u", url: "http://exemplo.test/lista.m3u")

// MARK: - Mídia e vídeo

/// O motor de vídeo de mentira: guarda o que foi pedido a ele e avisa o que o teste mandar.
@MainActor
final class FakeEngine: VideoEngine {
    var onEvent: ((EngineEvent) -> Void)?

    /// O que foi pedido ao motor, na ordem: "open <endereço> @<ponto>", "play", "pause", "stop",
    /// "seek <ponto>", "rate <velocidade>".
    private(set) var calls: [String] = []

    var isPlaying = false
    var positionMs: Int64 = 0
    var durationMs: Int64 = 0
    var isSeekable = true
    var rate: Double = 1 {
        didSet { calls.append("rate \(rate)") }
    }
    var audioTracks: [MediaTrack] = []
    var audioTrack: Int?
    var subtitleTracks: [MediaTrack] = []
    var subtitleTrack: Int?

    /// Com isto, o motor se comporta sozinho como um de verdade (para os testes das telas e das
    /// cenas): o vídeo abre e anda; o que tem um destes trechos no endereço dá erro.
    var automatic = false
    var failing: [String] = ["127.0.0.1:9"]
    var automaticDurationMs: Int64 = 21_600

    /// Pedidos de pausa que chegaram antes de o vídeo abrir. O motor de verdade, se recebe a
    /// pausa no meio da abertura, desiste dela (e avisa "fim"): o reprodutor nunca manda uma.
    private(set) var earlyPauses = 0
    /// O vídeo desta abertura já abriu (o motor avisou "tocando").
    private var opened = false

    func open(uri: String, startAtMs: Int64) {
        calls.append("open \(uri) @\(startAtMs)")
        positionMs = startAtMs
        isPlaying = false
        opened = false
        guard automatic else { return }
        let fails = failing.contains { uri.contains($0) }
        let pausesBefore = earlyPauses
        Task { @MainActor in
            self.emit(.opening)
            if fails {
                self.emit(.failed)
            } else if self.earlyPauses != pausesBefore {
                // Pausa no meio da abertura: o motor de verdade desiste e avisa "fim".
                self.emit(.ended)
            } else {
                self.startPlaying(durationMs: self.automaticDurationMs, at: startAtMs)
            }
        }
    }

    func play() {
        calls.append("play")
        isPlaying = true
    }

    func pause() {
        calls.append("pause")
        isPlaying = false
        if !opened { earlyPauses += 1 }
    }

    func stop() {
        calls.append("stop")
        isPlaying = false
    }

    func seek(toMs: Int64) {
        calls.append("seek \(toMs)")
        positionMs = toMs
        guard automatic, isPlaying else { return }
        Task { @MainActor in self.advance(to: toMs + 250) }
    }

    func forgetCalls() {
        calls = []
    }

    func emit(_ event: EngineEvent) {
        if case .playing = event { opened = true }
        onEvent?(event)
    }

    /// O vídeo abriu e está andando: o aviso de que abriu e dois avisos de tempo seguidos.
    func startPlaying(durationMs: Int64 = 600_000, at positionMs: Int64 = 0) {
        self.durationMs = durationMs
        isPlaying = true
        emit(.playing)
        advance(to: positionMs)
        advance(to: positionMs + 250)
    }

    /// O vídeo andou até este ponto.
    func advance(to positionMs: Int64) {
        self.positionMs = positionMs
        emit(.time(positionMs: positionMs, durationMs: durationMs))
    }
}

/// O acesso aos vídeos de mentira: o de demonstração tem um endereço fixo; os outros, o próprio.
@MainActor
final class FakeAccess: MediaAccess {
    static let demoAddress = "file:///app/demo_video.mp4"

    /// Os vídeos que não estão mais lá.
    var missing: Set<String> = []
    private(set) var asked: [PlaybackRequest] = []
    private(set) var closes = 0

    func open(_ request: PlaybackRequest) -> String? {
        asked.append(request)
        if request.kind == .demo { return FakeAccess.demoAddress }
        return missing.contains(request.uri) ? nil : request.uri
    }

    func close() {
        closes += 1
    }
}

/// A conferência das falhas de mentira: responde o que o teste combinar.
final class FakeDiagnosis: PlaybackDiagnosis, @unchecked Sendable {
    struct Question: Equatable {
        let kind: MediaKind
        let address: String
    }

    private let lock = NSLock()
    private var answer = PlaybackFailure.network
    private var delay: UInt64 = 0
    private var questions: [Question] = []

    /// A próxima resposta e quanto ela demora, em segundos.
    func willAnswer(_ failure: PlaybackFailure, after seconds: Double = 0) {
        lock.lock()
        answer = failure
        delay = UInt64(seconds * 1_000_000_000)
        lock.unlock()
    }

    var asked: [Question] {
        lock.lock()
        defer { lock.unlock() }
        return questions
    }

    func failure(of kind: MediaKind, address: String) async -> PlaybackFailure {
        let (failure, wait) = record(Question(kind: kind, address: address))
        if wait > 0 { try? await Task.sleep(nanoseconds: wait) }
        return failure
    }

    private func record(_ question: Question) -> (PlaybackFailure, UInt64) {
        lock.lock()
        defer { lock.unlock() }
        questions.append(question)
        return (answer, delay)
    }
}
