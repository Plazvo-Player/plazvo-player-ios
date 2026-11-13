import Foundation
import MobileVLCKit
import PlazvoCore
import UIKit

/// O motor de vídeo do app: o do VLC (MobileVLCKit), que toca os mesmos formatos do app Android
/// (MP4, MKV, TS, HLS…). A lógica só o conhece pelo `VideoEngine`; o que há de regra fica nela, e
/// aqui só se repassa o que o VLC faz e avisa.
///
/// O VLC não escreve nada em registros: o endereço do vídeo pode levar usuário e senha. Isso
/// vale porque o pacote do VLC usado aqui só traz o registro do sistema, que vem desligado, e
/// porque este app não liga nenhum registro dele (a compilação confere, em ci/compilar.sh).
@MainActor
final class VLCVideoEngine: NSObject, VideoEngine {
    var onEvent: ((EngineEvent) -> Void)?

    /// Onde a imagem do vídeo aparece.
    let surface: UIView

    private let player: VLCMediaPlayer
    private let listener: Listener
    /// Este motor está com um vídeo aberto no reprodutor do VLC.
    private var active = false
    private var stopped = false
    /// Aberto um vídeo, os avisos só valem a partir do "abrindo" dele: os do vídeo anterior que
    /// ainda estiverem a caminho ficam de fora.
    private var awaitingOpening = true
    /// O VLC já abriu este vídeo (avisou "tocando" ou o tempo andou). Antes disso ele não recebe
    /// pedido de pausa: no meio da abertura, o VLC responde a uma pausa desistindo de abrir.
    private var opened = false
    /// O tamanho do vídeo já avisado.
    private var shownSize = CGSize.zero

    /// O reprodutor do VLC: um só para o app todo, criado no primeiro vídeo e nunca desfeito.
    /// (O VLC termina de fechar cada vídeo em segundo plano, e desfazer o reprodutor esperaria
    /// por isso com a tela parada.)
    private static var sharedPlayer: VLCMediaPlayer?

    /// - Parameter userAgent: como o app se apresenta ao servidor do vídeo.
    init(userAgent: String) {
        surface = UIView()
        listener = Listener()
        if let shared = VLCVideoEngine.sharedPlayer {
            player = shared
        } else {
            let created = VLCMediaPlayer()
            created.libraryInstance.setHumanReadableName("Plazvo Player", withHTTPUserAgent: userAgent)
            VLCVideoEngine.sharedPlayer = created
            player = created
        }
        super.init()
        surface.backgroundColor = .black
        // Os toques são da tela do reprodutor, que fica por cima.
        surface.isUserInteractionEnabled = false
        listener.engine = self
    }

    // MARK: - Pedidos da lógica

    func open(uri: String, startAtMs: Int64) {
        guard !stopped, let url = URL(string: uri) else {
            // Endereço que o sistema não entende: conta como vídeo que não abriu.
            Task { @MainActor [weak self] in self?.onEvent?(.failed) }
            return
        }
        let media = VLCMedia(url: url)
        if startAtMs > 0 {
            // O ponto de onde continuar, em segundos.
            media.addOption(":start-time=\(Double(startAtMs) / 1000)")
        }
        shownSize = .zero
        awaitingOpening = true
        opened = false
        active = true
        player.delegate = listener
        player.drawable = surface
        player.media = media
        player.play()
    }

    func play() {
        guard active else { return }
        player.play()
    }

    func pause() {
        guard active, opened else { return }
        player.pause()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        guard active else { return }
        active = false
        // O reprodutor do VLC fica para o próximo vídeo, sem nada deste.
        if player.delegate === listener { player.delegate = nil }
        player.stop()
        player.media = nil
    }

    func seek(toMs: Int64) {
        guard active else { return }
        player.time = VLCTime(int: Int32(clamping: toMs))
    }

    var isPlaying: Bool { active && player.isPlaying }

    var positionMs: Int64 { active ? Int64(player.time.intValue) : 0 }

    var durationMs: Int64 { active ? Int64(player.media?.length.intValue ?? 0) : 0 }

    var isSeekable: Bool { active && player.isSeekable }

    var rate: Double {
        get { Double(player.rate) }
        set { player.rate = Float(newValue) }
    }

    var audioTracks: [MediaTrack] {
        active ? tracks(names: player.audioTrackNames, ids: player.audioTrackIndexes) : []
    }

    var audioTrack: Int? {
        get {
            guard active else { return nil }
            let id = Int(player.currentAudioTrackIndex)
            return id >= 0 ? id : nil
        }
        set {
            if active, let newValue { player.currentAudioTrackIndex = Int32(clamping: newValue) }
        }
    }

    var subtitleTracks: [MediaTrack] {
        active ? tracks(names: player.videoSubTitlesNames, ids: player.videoSubTitlesIndexes) : []
    }

    var subtitleTrack: Int? {
        get {
            guard active else { return nil }
            let id = Int(player.currentVideoSubTitleIndex)
            return id >= 0 ? id : nil
        }
        set {
            // No VLC, a legenda de número -1 é "desligadas".
            if active { player.currentVideoSubTitleIndex = Int32(clamping: newValue ?? -1) }
        }
    }

    /// As faixas que o VLC lista, sem a de número negativo (que é a opção de desligar).
    private func tracks(names: [Any], ids: [Any]) -> [MediaTrack] {
        var result: [MediaTrack] = []
        for (name, id) in zip(names, ids) {
            guard let number = id as? NSNumber, number.intValue >= 0 else { continue }
            result.append(MediaTrack(id: number.intValue, name: (name as? String) ?? ""))
        }
        return result
    }

    // MARK: - Avisos do VLC

    fileprivate func stateChanged() {
        guard active else { return }
        let state = player.state
        if awaitingOpening {
            guard state == .opening else { return }
            awaitingOpening = false
        }
        switch state {
        case .opening:
            onEvent?(.opening)
        case .buffering:
            onEvent?(.buffering)
        case .playing:
            opened = true
            onEvent?(.playing)
        case .ended:
            onEvent?(.ended)
        case .error:
            onEvent?(.failed)
        case .stopped, .paused:
            break
        default:
            // O VLC achou mais uma faixa (vídeo, áudio ou legenda).
            onEvent?(.tracksChanged)
            checkVideoSize()
        }
        if shownSize == .zero { checkVideoSize() }
    }

    fileprivate func timeChanged() {
        guard active, !awaitingOpening else { return }
        opened = true
        onEvent?(.time(positionMs: positionMs, durationMs: durationMs))
        if shownSize == .zero { checkVideoSize() }
    }

    /// Avisa o tamanho com que o vídeo aparece, quando o VLC passa a saber dele (ou ele muda).
    private func checkVideoSize() {
        guard active, let media = player.media else { return }
        for case let track as [String: Any] in media.tracksInformation {
            guard track[VLCMediaTracksInformationType] as? String == VLCMediaTracksInformationTypeVideo else { continue }
            func number(_ key: String) -> Int { (track[key] as? NSNumber)?.intValue ?? 0 }
            guard let size = VideoGeometry.displaySize(
                width: number(VLCMediaTracksInformationVideoWidth),
                height: number(VLCMediaTracksInformationVideoHeight),
                sarNum: number(VLCMediaTracksInformationSourceAspectRatio),
                sarDen: number(VLCMediaTracksInformationSourceAspectRatioDenominator),
                orientation: number(VLCMediaTracksInformationVideoOrientation)
            ) else { continue }
            let found = CGSize(width: size.width, height: size.height)
            if found != shownSize {
                shownSize = found
                onEvent?(.videoSize(width: size.width, height: size.height))
            }
            return
        }
    }
}

/// Recebe os avisos do VLC e os entrega ao motor, sempre na linha principal (que é onde o VLC os
/// manda; se algum vier de outra, ele é levado para ela).
private final class Listener: NSObject, VLCMediaPlayerDelegate {
    weak var engine: VLCVideoEngine?

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        deliver { $0.stateChanged() }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        deliver { $0.timeChanged() }
    }

    private func deliver(_ action: @escaping @MainActor (VLCVideoEngine) -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if let engine = self.engine { action(engine) }
            }
        } else {
            Task { @MainActor in
                if let engine = self.engine { action(engine) }
            }
        }
    }
}
