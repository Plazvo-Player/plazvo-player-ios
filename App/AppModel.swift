import PlazvoCore
import SwiftUI
import UIKit

/// Liga a lógica (PlazvoCore) às telas: publica o estado e leva os toques ao controle.
@MainActor
final class AppModel: ObservableObject {
    /// Tudo o que as telas mostram. Muda sempre de uma vez só.
    @Published private(set) var state: AppState

    /// O reprodutor do vídeo aberto, ou `nil` sem vídeo aberto.
    @Published private(set) var player: PlayerModel?

    let app: AppController
    let version: String
    /// O que o campo do código já traz digitado (só nas cenas das fotos do simulador).
    let typedCode: String
    /// O que o campo do link já traz digitado (só nas cenas das fotos do simulador).
    let typedLink: String

    private let media: DeviceMediaAccess
    private let fixedNow: Date?
    private let startUp: () async -> Void

    init(_ environment: AppEnvironment) {
        app = environment.controller
        version = environment.version
        typedCode = environment.typedCode
        typedLink = environment.typedLink
        media = environment.media
        fixedNow = environment.fixedNow
        startUp = environment.start
        state = environment.controller.state
        environment.controller.onChange = { [weak self] state in
            self?.state = state
            self?.followPlayer()
        }
        followPlayer()
    }

    /// A tela do reprodutor acompanha o vídeo aberto na lógica: um reprodutor novo a cada vídeo.
    private func followPlayer() {
        let open = app.player
        if open !== player?.controller {
            player = open.map { PlayerModel($0) }
        }
    }

    /// A hora de agora, para os avisos de vencimento.
    var now: Date { fixedNow ?? Date() }

    /// A hora e a data da barra do alto, no idioma do app. `tick` é a hora de quem refaz a barra.
    func clockText(at tick: Date) -> ClockText {
        ClockFormatter.clockText(now: fixedNow ?? tick, languageTag: t("language_tag"), datePattern: t("home_date"))
    }

    func start() async {
        await startUp()
    }

    // Os toques que viram pedidos ao servidor: cada um corre na tarefa dele.

    func reload() {
        Task { await app.reload() }
    }

    func confirmNewKey() {
        Task { await app.confirmNewKey() }
    }

    func activate(_ code: String) {
        Task { await app.activateWithCode(code) }
    }

    func unlink() {
        Task { await app.unlink() }
    }

    // Mídia.

    /// Mídia › "Vídeo de demonstração".
    func playDemo() {
        app.playDemo(title: t("media_demo_title"))
    }

    /// Mídia › "Procurar vídeo no aparelho": o arquivo que o usuário escolheu no seletor do sistema.
    func pickedFile(_ url: URL) {
        let file = media.picked(url, untitled: t("media_untitled"))
        app.playFile(uri: file.uri, title: file.title, access: file.access)
    }
}

/// Liga o reprodutor de um vídeo (PlazvoCore) à tela dele.
@MainActor
final class PlayerModel: ObservableObject {
    /// Tudo o que a tela do reprodutor mostra. Muda sempre de uma vez só.
    @Published private(set) var state: PlayerState

    let controller: PlayerController

    init(_ controller: PlayerController) {
        self.controller = controller
        state = controller.state
        controller.onChange = { [weak self] state in
            self?.state = state
        }
    }

    /// Onde o motor de vídeo desenha a imagem.
    var surface: UIView? {
        (controller.engine as? VLCVideoEngine)?.surface
    }
}
