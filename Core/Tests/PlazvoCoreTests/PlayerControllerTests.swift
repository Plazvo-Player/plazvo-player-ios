import Foundation
import Testing
@testable import PlazvoCore

/// Tudo o que um teste do reprodutor precisa, já ligado: motor de vídeo, acesso aos vídeos,
/// conferência das falhas e lista de recentes, todos de mentira.
@MainActor
final class PlayerBench {
    let clock = TestClock("2026-11-12T17:30:00Z")
    let engine = FakeEngine()
    let access = FakeAccess()
    let diagnosis = FakeDiagnosis()
    let copy = InMemoryCopyStore()
    let recents: RecentMediaStore
    let request: PlaybackRequest
    let player: PlayerController
    private(set) var changes: [PlayerState] = []

    nonisolated static let link = PlaybackRequest(kind: .link, uri: "http://usuario:senha@exemplo.com:8080/aulas/aula 3.mkv".replacingOccurrences(of: " ", with: "%20"), title: "aula 3.mkv")
    nonisolated static let file = PlaybackRequest(kind: .file, uri: "file:///videos/F%C3%A9rias.mp4", title: "Férias.mp4", access: Data([1, 2, 3]))
    nonisolated static let demo = PlaybackRequest(kind: .demo, uri: "", title: "Big Buck Bunny (trecho)")

    init(_ request: PlaybackRequest = PlayerBench.link, stored: [RecentMedia] = []) {
        let clock = self.clock
        if !stored.isEmpty {
            copy.data = try? JSONEncoder().encode(stored)
        }
        recents = RecentMediaStore(storage: copy, now: { clock.now })
        self.request = request
        player = PlayerController(
            request: request,
            engine: engine,
            access: access,
            diagnosis: diagnosis,
            recents: recents,
            tickSeconds: nil
        )
        player.onChange = { [unowned self] in self.changes.append($0) }
    }

    var state: PlayerState { player.state }

    /// Abre o vídeo e o deixa rodando (com a duração dada), como um vídeo que abriu sem problema.
    func play(durationMs: Int64 = 600_000) {
        player.start()
        engine.startPlaying(durationMs: durationMs, at: engine.positionMs)
        engine.forgetCalls()
    }

    func tick(_ times: Int = 1) {
        for _ in 0..<times { player.tick() }
    }

    /// O vídeo anda `times` vezes, um quarto de segundo de cada vez, com uma conferência a cada duas.
    func run(ticks times: Int) {
        for _ in 0..<times {
            engine.advance(to: engine.positionMs + 250)
            engine.advance(to: engine.positionMs + 250)
            player.tick()
        }
    }

    func stored(_ uri: String) -> RecentMedia? {
        recents.find(uri)
    }
}

@MainActor
@Suite("Reprodutor: abrir, retomar e guardar o ponto")
struct PlayerOpeningTests {
    @Test("vídeo de demonstração: abre do início, com os controles na tela, e já pede para tocar")
    func demo() {
        let bench = PlayerBench(PlayerBench.demo)
        #expect(bench.state == PlayerState(title: "Big Buck Bunny (trecho)", kind: .demo))
        #expect(bench.state.status == .opening)
        #expect(bench.engine.calls.isEmpty)

        bench.player.start()

        #expect(bench.engine.calls == ["open \(FakeAccess.demoAddress) @0"])
        #expect(bench.access.asked == [PlayerBench.demo])
        #expect(bench.state.status == .opening)
        #expect(bench.state.controlsVisible)
        #expect(bench.state.waiting)
        #expect(bench.state.problem == nil)

        // Só a primeira chamada faz efeito.
        bench.player.start()
        #expect(bench.engine.calls.count == 1)
        #expect(bench.access.asked.count == 1)
    }

    @Test("o endereço do link vai para o motor como ele viaja (letra acentuada vira código)")
    func linkAddress() {
        let request = PlaybackRequest(kind: .link, uri: "http://exemplo.com/meu%20vídeo.mp4", title: "meu vídeo.mp4")
        let bench = PlayerBench(request)
        bench.player.start()
        #expect(bench.engine.calls == ["open http://exemplo.com/meu%20v%C3%ADdeo.mp4 @0"])
    }

    @Test("o endereço do arquivo vai como o acesso entregou")
    func fileAddress() {
        let bench = PlayerBench(PlayerBench.file)
        bench.player.start()
        #expect(bench.engine.calls == ["open file:///videos/F%C3%A9rias.mp4 @0"])
        #expect(bench.access.asked == [PlayerBench.file])
    }

    @Test("vídeo já visto continua de onde parou")
    func resumes() {
        let seen = RecentMedia(uri: PlayerBench.link.uri, title: "aula 3.mkv", kind: .link, positionMs: 60_000, durationMs: 600_000)
        let bench = PlayerBench(stored: [seen])
        bench.player.start()
        #expect(bench.engine.calls == ["open \(PlayerBench.link.uri) @60000"])
        #expect(bench.state.positionMs == 60_000)
    }

    @Test("vídeo já visto sem ponto para retomar abre como da primeira vez")
    func nothingToResume() {
        let barely = RecentMedia(uri: PlayerBench.link.uri, title: "aula 3.mkv", kind: .link, positionMs: 4_000, durationMs: 600_000)
        let finished = RecentMedia(uri: PlayerBench.file.uri, title: "Férias.mp4", kind: .file, positionMs: 598_000, durationMs: 600_000)
        let first = PlayerBench(stored: [barely, finished])
        first.player.start()
        #expect(first.engine.calls == ["open \(PlayerBench.link.uri) @0"])
        let second = PlayerBench(PlayerBench.file, stored: [barely, finished])
        second.player.start()
        #expect(second.engine.calls == ["open \(PlayerBench.file.uri) @0"])
    }

    @Test("só entra nos recentes o vídeo que abriu de verdade")
    func listedOnlyWhenOpened() {
        let bench = PlayerBench()
        bench.player.start()
        bench.engine.emit(.opening)
        bench.engine.emit(.buffering)
        #expect(bench.recents.items.isEmpty)

        bench.engine.durationMs = 600_000
        bench.engine.emit(.playing)

        #expect(bench.recents.items.map(\.uri) == [PlayerBench.link.uri])
        #expect(bench.recents.items[0].title == "aula 3.mkv")
        #expect(bench.recents.items[0].kind == .link)
        #expect(bench.state.durationMs == 600_000)
        #expect(bench.state.seekable)

        // Os avisos seguintes não mexem mais na lista.
        bench.clock.set("2026-11-12T18:00:00Z")
        bench.engine.emit(.playing)
        #expect(bench.recents.items[0].lastPlayedAt == Int64(parseServerTime("2026-11-12T17:30:00Z")!.timeIntervalSince1970 * 1000))
    }

    @Test("arquivo aberto entra nos recentes com o marcador de acesso")
    func fileListedWithAccess() {
        let bench = PlayerBench(PlayerBench.file)
        bench.play()
        #expect(bench.stored(PlayerBench.file.uri)?.access == Data([1, 2, 3]))
    }

    @Test("vídeo de demonstração não entra nos recentes nem guarda ponto")
    func demoNotListed() {
        let bench = PlayerBench(PlayerBench.demo)
        bench.play(durationMs: 21_600)
        bench.run(ticks: 30)
        bench.player.togglePlay()
        bench.player.close()
        #expect(bench.recents.items.isEmpty)
        #expect(bench.copy.data == nil)
    }

    @Test("guarda o ponto do vídeo a cada 10 segundos rodando, e ao pausar")
    func savesProgress() {
        let bench = PlayerBench()
        bench.play()
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 0)

        // 19 conferências (9,5 s): ainda não.
        bench.run(ticks: 19)
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 0)
        bench.run(ticks: 1)
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 10_250)
        #expect(bench.stored(PlayerBench.link.uri)?.durationMs == 600_000)

        bench.run(ticks: 5)
        bench.player.togglePlay()
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 12_750)
        #expect(bench.stored(PlayerBench.link.uri)?.resumePositionMs == 12_750)
    }

    @Test("vídeo que terminou recomeça do início na próxima vez")
    func finishedStartsOver() {
        let bench = PlayerBench()
        bench.play(durationMs: 60_000)
        bench.engine.advance(to: 59_900)
        bench.player.saveProgress()
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 59_900)

        bench.engine.isPlaying = false
        bench.engine.emit(.ended)

        #expect(bench.state.status == .ended)
        #expect(bench.state.positionMs == 60_000)
        #expect(bench.state.controlsVisible)
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 0)
        #expect(bench.stored(PlayerBench.link.uri)?.durationMs == 60_000)
        #expect(bench.stored(PlayerBench.link.uri)?.resumePositionMs == 0)
    }

    @Test("transmissão ao vivo e vídeo sem duração conhecida não guardam ponto")
    func liveSavesNoPoint() {
        let live = PlayerBench()
        live.engine.isSeekable = false
        live.play(durationMs: 600_000)
        live.run(ticks: 25)
        live.player.saveProgress()
        #expect(live.stored(PlayerBench.link.uri)?.positionMs == 0)
        #expect(live.stored(PlayerBench.link.uri)?.durationMs == 600_000)

        let unknown = PlayerBench()
        unknown.play(durationMs: 0)
        unknown.run(ticks: 25)
        unknown.player.saveProgress()
        #expect(unknown.stored(PlayerBench.link.uri)?.positionMs == 0)
        #expect(unknown.stored(PlayerBench.link.uri)?.durationMs == 0)
    }

    @Test("sair do app pausa e guarda o ponto; fechar guarda, para o motor e devolve o acesso")
    func backgroundAndClose() {
        let bench = PlayerBench(PlayerBench.file)
        bench.play()
        bench.run(ticks: 4)

        bench.player.enterBackground()

        #expect(bench.engine.calls == ["pause"])
        #expect(bench.state.status == .paused)
        #expect(bench.state.controlsVisible)
        #expect(bench.stored(PlayerBench.file.uri)?.positionMs == 2_250)
        // De novo no fundo, já pausado: não pede outra pausa.
        bench.player.enterBackground()
        #expect(bench.engine.calls == ["pause"])

        bench.engine.advance(to: 5_000)
        bench.player.close()

        #expect(bench.engine.calls == ["pause", "stop"])
        #expect(bench.access.closes == 1)
        #expect(bench.stored(PlayerBench.file.uri)?.positionMs == 5_000)
        #expect(bench.engine.onEvent == nil)

        // Fechado, nada mais faz efeito.
        let before = bench.state
        bench.player.close()
        bench.player.togglePlay()
        bench.player.seek(toMs: 1_000)
        bench.player.tick()
        bench.player.enterBackground()
        bench.player.start()
        #expect(bench.engine.calls == ["pause", "stop"])
        #expect(bench.access.closes == 1)
        #expect(bench.state == before)
    }

    @Test("fechar um reprodutor que nem abriu não pede nada ao motor")
    func closeBeforeStart() {
        let bench = PlayerBench()
        bench.player.close()
        #expect(bench.engine.calls.isEmpty)
        #expect(bench.access.closes == 0)
        bench.player.start()
        #expect(bench.engine.calls.isEmpty)
    }
}

@MainActor
@Suite("Reprodutor: o que a tela mostra enquanto o vídeo roda")
struct PlayerStatusTests {
    @Test("abrindo, juntando vídeo, e só rodando quando o tempo anda")
    func fromOpeningToPlaying() {
        let bench = PlayerBench()
        bench.player.start()
        #expect(bench.state.status == .opening)

        bench.engine.emit(.opening)
        #expect(bench.state.status == .opening)
        bench.engine.emit(.buffering)
        #expect(bench.state.status == .buffering)
        #expect(bench.state.waiting)

        // O motor achou o vídeo, mas a imagem ainda não anda: a rodinha continua.
        bench.engine.durationMs = 600_000
        bench.engine.isPlaying = true
        bench.engine.emit(.playing)
        #expect(bench.state.status == .buffering)
        bench.engine.advance(to: 0)
        #expect(bench.state.status == .buffering)

        bench.engine.advance(to: 250)
        #expect(bench.state.status == .playing)
        #expect(!bench.state.waiting)
        #expect(bench.state.positionMs == 250)
        #expect(bench.state.durationMs == 600_000)
    }

    @Test("vídeo que não informa o tempo é dado por rodando três segundos depois de abrir")
    func noTimeInformation() {
        let bench = PlayerBench()
        bench.player.start()
        bench.engine.isPlaying = true
        bench.engine.emit(.playing)

        bench.tick(5)
        #expect(bench.state.status == .buffering)
        bench.tick()
        #expect(bench.state.status == .playing)

        // E, sem tempo para medir, a rodinha de espera não volta sozinha.
        bench.tick(20)
        #expect(bench.state.status == .playing)
    }

    @Test("o tempo andando vale pelo aviso de que o vídeo abriu")
    func timeMovingMeansOpened() {
        let bench = PlayerBench()
        bench.player.start()
        bench.engine.durationMs = 600_000
        bench.engine.advance(to: 0)
        #expect(bench.recents.items.isEmpty)
        bench.engine.advance(to: 250)
        #expect(bench.state.status == .playing)
        #expect(bench.recents.items.count == 1)
        #expect(bench.state.durationMs == 600_000)
    }

    @Test("vídeo que para de andar por um segundo e meio mostra a rodinha, até voltar a andar")
    func stall() {
        let bench = PlayerBench()
        bench.play()
        bench.run(ticks: 2)
        #expect(bench.state.status == .playing)

        // Três conferências seguidas sem o ponto mudar.
        bench.tick(2)
        #expect(bench.state.status == .playing)
        bench.tick()
        #expect(bench.state.status == .buffering)
        #expect(bench.state.waiting)

        bench.engine.advance(to: bench.engine.positionMs + 250)
        #expect(bench.state.status == .playing)
    }

    @Test("pausado, o vídeo parado não é espera")
    func pausedIsNotStalled() {
        let bench = PlayerBench()
        bench.play()
        bench.run(ticks: 2)
        bench.player.togglePlay()
        bench.tick(10)
        #expect(bench.state.status == .paused)
        #expect(!bench.state.waiting)
    }

    @Test("vídeo gravado em pé é reconhecido")
    func portrait() {
        let bench = PlayerBench()
        bench.player.start()
        #expect(!bench.state.portraitVideo)
        bench.engine.emit(.videoSize(width: 1080, height: 1920))
        #expect(bench.state.portraitVideo)
        bench.engine.emit(.videoSize(width: 1920, height: 1080))
        #expect(!bench.state.portraitVideo)
        // Tamanho que ainda não se sabe não muda nada.
        bench.engine.emit(.videoSize(width: 1080, height: 1920))
        bench.engine.emit(.videoSize(width: 0, height: 0))
        #expect(bench.state.portraitVideo)
    }

    @Test("faixas de áudio e legendas: aparecem quando o vídeo abre e quando mudam")
    func tracks() {
        let bench = PlayerBench()
        bench.engine.audioTracks = [MediaTrack(id: 1, name: "Português"), MediaTrack(id: 2, name: "English")]
        bench.engine.audioTrack = 1
        bench.play()
        #expect(bench.state.audioTracks.map(\.name) == ["Português", "English"])
        #expect(bench.state.audioTrack == 1)
        #expect(bench.state.subtitleTracks.isEmpty)
        #expect(bench.state.subtitleTrack == nil)

        bench.engine.subtitleTracks = [MediaTrack(id: 3, name: "Português"), MediaTrack(id: 4, name: "Español")]
        bench.engine.emit(.tracksChanged)
        #expect(bench.state.subtitleTracks.map(\.id) == [3, 4])

        bench.player.selectSubtitle(4)
        #expect(bench.engine.subtitleTrack == 4)
        #expect(bench.state.subtitleTrack == 4)
        bench.player.selectSubtitle(nil)
        #expect(bench.engine.subtitleTrack == nil)
        #expect(bench.state.subtitleTrack == nil)
        bench.player.selectAudio(2)
        #expect(bench.engine.audioTrack == 2)
        #expect(bench.state.audioTrack == 2)

        // Faixa que o vídeo não tem: nada muda.
        bench.player.selectSubtitle(9)
        bench.player.selectAudio(9)
        #expect(bench.engine.subtitleTrack == nil)
        #expect(bench.engine.audioTrack == 2)
    }
}

@MainActor
@Suite("Reprodutor: os toques do usuário")
struct PlayerControlsTests {
    @Test("botão do meio: pausa e continua")
    func pauseAndResume() {
        let bench = PlayerBench()
        bench.play()
        bench.run(ticks: 2)

        bench.player.togglePlay()
        #expect(bench.engine.calls == ["pause"])
        #expect(bench.state.status == .paused)
        #expect(bench.state.controlsVisible)

        bench.player.togglePlay()
        #expect(bench.engine.calls == ["pause", "play"])
        #expect(bench.state.status == .playing)
    }

    @Test("pausado antes de o vídeo abrir: a pausa vale quando ele abre")
    func pausedBeforeOpening() {
        let bench = PlayerBench()
        bench.player.start()
        bench.engine.forgetCalls()
        bench.player.togglePlay()
        #expect(bench.engine.calls == ["pause"])
        #expect(bench.state.status == .paused)

        bench.engine.startPlaying()

        #expect(bench.engine.calls == ["pause", "pause"])
        #expect(bench.state.status == .paused)
        #expect(bench.recents.items.count == 1)
    }

    @Test("voltar e avançar 10 segundos, sem passar do começo nem do fim")
    func skips() {
        let bench = PlayerBench()
        bench.play(durationMs: 60_000)
        bench.engine.advance(to: 30_000)

        bench.player.skip(seconds: 10)
        #expect(bench.engine.calls == ["seek 40000"])
        #expect(bench.state.positionMs == 40_000)
        bench.player.skip(seconds: -10)
        bench.player.skip(seconds: -10)
        #expect(bench.state.positionMs == 20_000)

        bench.player.seek(toMs: 3_000)
        bench.player.skip(seconds: -10)
        #expect(bench.state.positionMs == 0)
        bench.player.seek(toMs: 55_000)
        bench.player.skip(seconds: 10)
        #expect(bench.state.positionMs == 60_000)
        #expect(bench.engine.calls.last == "seek 60000")
    }

    @Test("vídeo em que não dá para ir a outro ponto ignora a barra e os botões de 10 segundos")
    func notSeekable() {
        let bench = PlayerBench()
        bench.engine.isSeekable = false
        bench.play()
        #expect(!bench.state.seekable)
        bench.player.skip(seconds: 10)
        bench.player.seek(toMs: 5_000)
        #expect(bench.engine.calls.isEmpty)
        #expect(bench.state.positionMs == 250)
    }

    @Test("depois do fim: o botão do meio recomeça, e voltar reabre no ponto pedido")
    func afterTheEnd() {
        let bench = PlayerBench()
        bench.play(durationMs: 60_000)
        bench.engine.advance(to: 59_900)
        bench.engine.isPlaying = false
        bench.engine.emit(.ended)
        #expect(bench.state.status == .ended)

        bench.player.skip(seconds: -10)
        #expect(bench.engine.calls == ["open \(PlayerBench.link.uri) @50000"])
        #expect(bench.state.status == .opening)
        #expect(bench.state.positionMs == 50_000)

        bench.engine.startPlaying(durationMs: 60_000, at: 50_000)
        bench.engine.advance(to: 59_900)
        bench.engine.isPlaying = false
        bench.engine.emit(.ended)
        bench.engine.forgetCalls()

        bench.player.togglePlay()
        #expect(bench.engine.calls == ["open \(PlayerBench.link.uri) @0"])
        #expect(bench.state.status == .opening)
        #expect(bench.state.positionMs == 0)
        // O acesso ao vídeo foi pedido uma vez só.
        #expect(bench.access.asked.count == 1)
    }

    @Test("velocidade: só as da lista, e vale também depois de reabrir")
    func rate() {
        let bench = PlayerBench()
        bench.play(durationMs: 60_000)

        bench.player.setRate(1.5)
        #expect(bench.engine.rate == 1.5)
        #expect(bench.state.rate == 1.5)
        bench.player.setRate(3)
        bench.player.setRate(0)
        #expect(bench.engine.rate == 1.5)
        #expect(bench.state.rate == 1.5)
        #expect(PlayerController.rates == [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2])

        bench.engine.isPlaying = false
        bench.engine.emit(.ended)
        bench.engine.forgetCalls()
        bench.player.togglePlay()
        #expect(bench.engine.calls == ["open \(PlayerBench.link.uri) @0", "rate 1.5"])
    }

    @Test("controles: somem depois de 4 segundos com o vídeo rodando; um toque no vídeo mostra e esconde")
    func controlsHide() {
        let bench = PlayerBench()
        bench.play()
        #expect(bench.state.controlsVisible)

        bench.run(ticks: 7)
        #expect(bench.state.controlsVisible)
        bench.run(ticks: 1)
        #expect(!bench.state.controlsVisible)

        bench.player.tapVideo()
        #expect(bench.state.controlsVisible)
        bench.player.tapVideo()
        #expect(!bench.state.controlsVisible)
        bench.player.tapVideo()
        bench.run(ticks: 7)
        #expect(bench.state.controlsVisible)
        bench.run(ticks: 1)
        #expect(!bench.state.controlsVisible)
    }

    @Test("controles: mexer neles recomeça a contagem")
    func controlsStayWhileUsed() {
        let bench = PlayerBench()
        bench.play()
        bench.run(ticks: 6)
        bench.player.skip(seconds: 10)
        bench.run(ticks: 6)
        bench.player.keepControls()
        bench.run(ticks: 6)
        bench.player.setRate(1.25)
        bench.run(ticks: 7)
        #expect(bench.state.controlsVisible)
        bench.run(ticks: 1)
        #expect(!bench.state.controlsVisible)
    }

    @Test("controles: pausado, ficam na tela até o usuário esconder")
    func controlsWhilePaused() {
        let bench = PlayerBench()
        bench.play()
        bench.run(ticks: 8)
        #expect(!bench.state.controlsVisible)

        bench.player.tapVideo()
        bench.player.togglePlay()
        bench.tick(40)
        #expect(bench.state.controlsVisible)

        // O usuário esconde com um toque: continuam escondidos.
        bench.player.tapVideo()
        bench.tick(10)
        #expect(!bench.state.controlsVisible)

        // Ao continuar, voltam, e somem de novo depois de 4 segundos.
        bench.player.tapVideo()
        bench.player.togglePlay()
        #expect(bench.state.controlsVisible)
        bench.run(ticks: 8)
        #expect(!bench.state.controlsVisible)
    }

    @Test("o motor parou sozinho por um segundo: a tela mostra pausado, com os controles")
    func engineStoppedAlone() {
        let bench = PlayerBench()
        bench.play()
        bench.run(ticks: 10)
        #expect(!bench.state.controlsVisible)

        bench.engine.isPlaying = false
        bench.tick()
        #expect(bench.state.status == .playing)
        bench.tick()
        #expect(bench.state.status == .paused)
        #expect(bench.state.controlsVisible)
        #expect(bench.engine.calls.isEmpty)
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 5_250)

        // O usuário manda continuar.
        bench.player.togglePlay()
        #expect(bench.engine.calls == ["play"])
        #expect(bench.state.status == .playing)
    }

    @Test("o motor não atendeu à pausa por um segundo: o pedido é repetido")
    func engineIgnoredPause() {
        let bench = PlayerBench()
        bench.play()
        bench.run(ticks: 2)
        bench.player.togglePlay()
        #expect(bench.engine.calls == ["pause"])

        bench.engine.isPlaying = true
        bench.tick()
        #expect(bench.engine.calls == ["pause"])
        bench.tick()
        #expect(bench.engine.calls == ["pause", "pause"])
        #expect(bench.state.status == .paused)
    }
}

@MainActor
@Suite("Reprodutor: vídeo que não abre")
struct PlayerFailureTests {
    @Test("link que não respondeu: a tela espera a conferência e mostra a mensagem com o código")
    func linkWithoutAnswer() async {
        let bench = PlayerBench()
        bench.diagnosis.willAnswer(.network)
        bench.player.start()
        bench.engine.emit(.opening)

        bench.engine.emit(.failed)

        // Enquanto a conferência não volta, a tela continua à espera.
        #expect(bench.state.problem == nil)
        #expect(bench.state.waiting)
        #expect(await eventually { bench.state.problem != nil })

        #expect(bench.state.problem == PlaybackProblem(message: TextRef("player_error_network"), code: 2001))
        #expect(!bench.state.controlsVisible)
        #expect(!bench.state.waiting)
        // A conferência recebe o endereço como ele viaja, e uma vez só.
        #expect(bench.diagnosis.asked == [FakeDiagnosis.Question(kind: .link, address: PlayerBench.link.uri)])
        #expect(bench.recents.items.isEmpty)

        // Com a mensagem na tela, os avisos e os toques não fazem efeito.
        bench.engine.forgetCalls()
        bench.engine.emit(.failed)
        bench.engine.emit(.playing)
        bench.engine.advance(to: 1_000)
        bench.engine.advance(to: 2_000)
        bench.player.togglePlay()
        bench.player.seek(toMs: 5_000)
        bench.player.tapVideo()
        bench.player.tick()
        #expect(bench.engine.calls.isEmpty)
        #expect(bench.state.problem?.code == 2001)
        #expect(bench.diagnosis.asked.count == 1)
        #expect(bench.recents.items.isEmpty)
    }

    @Test("servidor que recusou o vídeo: a mensagem leva o número do erro")
    func serverRefused() async {
        let bench = PlayerBench()
        bench.diagnosis.willAnswer(.http(status: 403))
        bench.player.start()
        bench.engine.emit(.failed)
        #expect(await eventually { bench.state.problem != nil })
        #expect(bench.state.problem == PlaybackProblem(message: TextRef("player_error_http", ["403"]), code: 2004))
    }

    @Test("arquivo que sumiu: a mensagem aparece direto, sem chamar o motor; tentar de novo procura o arquivo outra vez")
    func fileGone() async {
        let bench = PlayerBench(PlayerBench.file)
        bench.access.missing = [PlayerBench.file.uri]

        bench.player.start()

        #expect(bench.state.problem == PlaybackProblem(message: TextRef("player_error_not_found"), code: 2005))
        #expect(bench.engine.calls.isEmpty)
        #expect(bench.diagnosis.asked.isEmpty)
        #expect(!bench.state.controlsVisible)

        // O arquivo voltou (o usuário religou o disco, por exemplo).
        bench.access.missing = []
        bench.player.retry()

        #expect(bench.state.problem == nil)
        #expect(bench.engine.calls == ["open \(PlayerBench.file.uri) @0"])
        #expect(bench.access.asked.count == 2)
        // O acesso da primeira tentativa foi devolvido antes de pedir o outro.
        #expect(bench.access.closes == 1)
        bench.player.close()
        #expect(bench.access.closes == 2)
    }

    @Test("arquivo que o motor não leu: se ele sumiu, a próxima tentativa pede o acesso de novo")
    func fileUnreadable() async {
        let bench = PlayerBench(PlayerBench.file)
        bench.diagnosis.willAnswer(.notFound)
        bench.player.start()
        bench.engine.emit(.failed)
        #expect(await eventually { bench.state.problem != nil })
        #expect(bench.state.problem?.code == 2005)
        #expect(bench.diagnosis.asked == [FakeDiagnosis.Question(kind: .file, address: PlayerBench.file.uri)])

        bench.player.retry()
        #expect(bench.access.asked.count == 2)
    }

    @Test("formato que o reprodutor não toca")
    func format() async {
        let bench = PlayerBench(PlayerBench.file)
        bench.diagnosis.willAnswer(.format)
        bench.player.start()
        bench.engine.emit(.failed)
        #expect(await eventually { bench.state.problem != nil })
        #expect(bench.state.problem == PlaybackProblem(message: TextRef("player_error_format"), code: 3003))
    }

    @Test("\"fim\" sem nunca ter mostrado nada conta como falha")
    func endedWithoutShowingAnything() async {
        let bench = PlayerBench()
        bench.diagnosis.willAnswer(.format)
        bench.player.start()
        bench.engine.emit(.opening)
        bench.engine.emit(.ended)
        #expect(await eventually { bench.state.problem != nil })
        #expect(bench.state.problem?.code == 3003)
        #expect(bench.state.status != .ended)

        // Abriu, mas acabou sem imagem, sem tempo e sem duração: também.
        let other = PlayerBench()
        other.diagnosis.willAnswer(.format)
        other.player.start()
        other.engine.emit(.playing)
        other.engine.emit(.ended)
        #expect(await eventually { other.state.problem != nil })
        #expect(other.state.problem?.code == 3003)
    }

    @Test("tentar de novo limpa a mensagem e abre o vídeo outra vez, do ponto em que estava")
    func retry() async {
        let bench = PlayerBench()
        bench.play(durationMs: 600_000)
        bench.engine.advance(to: 95_000)
        bench.engine.emit(.failed)
        #expect(await eventually { bench.state.problem != nil })
        bench.engine.forgetCalls()

        bench.player.retry()

        #expect(bench.state.problem == nil)
        #expect(bench.state.status == .opening)
        #expect(bench.state.controlsVisible)
        #expect(bench.engine.calls == ["open \(PlayerBench.link.uri) @95000"])
        #expect(bench.access.asked.count == 1)

        bench.engine.startPlaying(durationMs: 600_000, at: 95_000)
        #expect(bench.state.status == .playing)
        #expect(bench.state.positionMs == 95_250)
        // Sem falha na tela, "tentar de novo" não faz nada.
        bench.engine.forgetCalls()
        bench.player.retry()
        #expect(bench.engine.calls.isEmpty)
    }

    @Test("vídeo retomado que nem abriu: tentar de novo volta ao ponto de onde ia continuar")
    func retryKeepsResumePoint() async {
        let seen = RecentMedia(uri: PlayerBench.link.uri, title: "aula 3.mkv", kind: .link, positionMs: 60_000, durationMs: 600_000)
        let bench = PlayerBench(stored: [seen])
        bench.player.start()
        bench.engine.emit(.failed)
        #expect(await eventually { bench.state.problem != nil })
        bench.engine.forgetCalls()

        bench.player.retry()

        #expect(bench.engine.calls == ["open \(PlayerBench.link.uri) @60000"])
        // A falha não mexe no ponto guardado.
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 60_000)
    }

    @Test("falha no meio do vídeo: o ponto guardado continua valendo")
    func failureKeepsSavedPoint() async {
        let bench = PlayerBench()
        bench.play(durationMs: 600_000)
        bench.engine.advance(to: 95_000)
        bench.player.saveProgress()
        bench.engine.emit(.failed)
        #expect(await eventually { bench.state.problem != nil })
        bench.player.close()
        #expect(bench.stored(PlayerBench.link.uri)?.positionMs == 95_000)
    }

    @Test("sair do vídeo durante a conferência: a resposta dela é ignorada")
    func closedWhileChecking() async {
        let bench = PlayerBench()
        bench.diagnosis.willAnswer(.network, after: 0.1)
        bench.player.start()
        bench.engine.emit(.failed)
        #expect(await eventually { bench.diagnosis.asked.count == 1 })

        bench.player.close()
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(bench.state.problem == nil)
    }

    @Test("as mensagens de cada falha, como no app Android")
    func problems() {
        // Servidor recusou: mostra o número do erro.
        #expect(problemFor(kind: .link, failure: .http(status: 404)) == PlaybackProblem(message: TextRef("player_error_http", ["404"]), code: 2004))
        #expect(problemFor(kind: .file, failure: .http(status: 500)).message == TextRef("player_error_http", ["500"]))
        // Sem conexão: no link é a conexão; no arquivo, ele sumiu ou o acesso acabou.
        #expect(problemFor(kind: .link, failure: .network) == PlaybackProblem(message: TextRef("player_error_network"), code: 2001))
        #expect(problemFor(kind: .file, failure: .network) == PlaybackProblem(message: TextRef("player_error_not_found"), code: 2005))
        #expect(problemFor(kind: .demo, failure: .network) == PlaybackProblem(message: TextRef("player_error_generic"), code: 1000))
        // Arquivo que sumiu ou perdeu o acesso.
        for kind in [MediaKind.demo, .file, .link] {
            #expect(problemFor(kind: kind, failure: .notFound) == PlaybackProblem(message: TextRef("player_error_not_found"), code: 2005))
            // Formato que o aparelho não reproduz.
            #expect(problemFor(kind: kind, failure: .format) == PlaybackProblem(message: TextRef("player_error_format"), code: 3003))
            // Qualquer outra falha tem mensagem geral, com o código.
            #expect(problemFor(kind: kind, failure: .unknown) == PlaybackProblem(message: TextRef("player_error_generic"), code: 1000))
        }
    }
}

@Suite("Tamanho com que o vídeo aparece")
struct VideoGeometryTests {
    private func size(_ width: Int, _ height: Int, sar: (Int, Int) = (1, 1), orientation: Int = 0) -> [Int]? {
        VideoGeometry.displaySize(width: width, height: height, sarNum: sar.0, sarDen: sar.1, orientation: orientation).map { [$0.width, $0.height] }
    }

    @Test("vídeo comum: o tamanho que o arquivo informa")
    func plain() {
        #expect(size(1920, 1080) == [1920, 1080])
        #expect(size(854, 480) == [854, 480])
        #expect(size(1080, 1920) == [1080, 1920])
    }

    @Test("vídeo gravado com o celular em pé: a largura e a altura trocam de lugar")
    func rotated() {
        for orientation in 4...7 {
            #expect(size(1920, 1080, orientation: orientation) == [1080, 1920], "posição \(orientation)")
        }
        // De cabeça para baixo ou espelhado, o vídeo continua deitado.
        for orientation in 0...3 {
            #expect(size(1920, 1080, orientation: orientation) == [1920, 1080], "posição \(orientation)")
        }
        // Posição que o motor não conhece: como veio.
        #expect(size(1920, 1080, orientation: 9) == [1920, 1080])
        #expect(size(1920, 1080, orientation: -1) == [1920, 1080])
    }

    @Test("pontos que não são quadrados: a largura acompanha a proporção deles")
    func anamorphic() {
        #expect(size(720, 576, sar: (16, 11)) == [1047, 576])
        #expect(size(720, 576, sar: (16, 15)) == [768, 576])
        // Em pé, depois de alargar.
        #expect(size(720, 576, sar: (16, 11), orientation: 6) == [576, 1047])
        // Proporção não informada conta como 1 por 1.
        #expect(size(720, 576, sar: (0, 0)) == [720, 576])
        #expect(size(720, 576, sar: (0, 1)) == [720, 576])
        #expect(size(720, 576, sar: (-4, 3)) == [720, 576])
    }

    @Test("sem tamanho informado, não há o que dizer")
    func unknown() {
        #expect(size(0, 0) == nil)
        #expect(size(1920, 0) == nil)
        #expect(size(0, 1080) == nil)
        #expect(size(-1, 1080) == nil)
    }
}
