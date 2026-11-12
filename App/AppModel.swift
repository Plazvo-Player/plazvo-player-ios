import PlazvoCore
import SwiftUI

/// Liga a lógica (PlazvoCore) às telas: publica o estado e leva os toques ao controle.
@MainActor
final class AppModel: ObservableObject {
    /// Tudo o que as telas mostram. Muda sempre de uma vez só.
    @Published private(set) var state: AppState

    let app: AppController
    let version: String
    /// O que o campo do código já traz digitado (só nas cenas das fotos do simulador).
    let typedCode: String

    private let fixedNow: Date?
    private let startUp: () async -> Void

    init(_ environment: AppEnvironment) {
        app = environment.controller
        version = environment.version
        typedCode = environment.typedCode
        fixedNow = environment.fixedNow
        startUp = environment.start
        state = environment.controller.state
        environment.controller.onChange = { [weak self] state in
            self?.state = state
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
}
