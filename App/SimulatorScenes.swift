#if targetEnvironment(simulator)
import PlazvoCore
import UIKit

/// Só na compilação do simulador, para as fotos das telas: abre a cena que a linha de comando
/// pede, deita a tela quando ela pede e avisa, num arquivo, que a cena está pronta (a compilação
/// na nuvem espera por ele antes de fotografar). O app do aparelho de verdade não leva nada disto.
@MainActor
enum SimulatorScenes {
    private static var ran = false
    private static var keyboardShown = false
    private static var keyboardObservers: [NSObjectProtocol] = []
    /// O que o sistema respondeu ao pedido de deitar a tela, quando recusou.
    private static var turnRefusal: String?

    /// Abre a cena pedida e marca quando ela está pronta. Só a primeira chamada faz efeito, e numa
    /// tarefa própria: se a tela for refeita no meio do caminho, a cena não para nem recomeça.
    static func run(_ request: DemoRequest, site: FakeSite, now: Date, controller: AppController) async {
        guard !ran else { return }
        ran = true
        await Task { @MainActor in
            let started = Date()
            watchKeyboard()
            askLandscape(request)
            await (request.scene ?? .home).prepare(site, now: now)
            await controller.start()
            if let scene = request.scene {
                await scene.play(on: controller)
            }
            await settle(request)
            writeMarker(request, state: controller.state, seconds: Date().timeIntervalSince(started))
        }.value
    }

    // MARK: - Tela deitada e teclado

    /// Pede a tela deitada. O iPhone atende; o iPad só deita quando o aparelho é girado.
    private static func askLandscape(_ request: DemoRequest) {
        guard request.landscape else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let landscape = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeRight)
            windowScene.requestGeometryUpdate(landscape) { error in
                let reason = error.localizedDescription
                Task { @MainActor in turnRefusal = reason }
            }
        }
    }

    private static var isLandscape: Bool {
        UIApplication.shared.connectedScenes.contains { scene in
            (scene as? UIWindowScene)?.interfaceOrientation.isLandscape == true
        }
    }

    /// Passa a saber se o teclado está na tela.
    private static func watchKeyboard() {
        let center = NotificationCenter.default
        keyboardObservers = [
            center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in keyboardShown = true }
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in keyboardShown = false }
            },
        ]
    }

    // MARK: - Cena pronta

    /// Espera a cena assentar: o app na frente, a tela deitada (quando pedida), o teclado (nas
    /// cenas que terminam com ele) e mais um instante para as animações acabarem. Cada espera tem
    /// limite: passado ele, a cena é dada por pronta assim mesmo, e o arquivo diz como ela estava.
    private static func settle(_ request: DemoRequest) async {
        await wait(seconds: 20) { UIApplication.shared.applicationState == .active }
        if request.landscape {
            await wait(seconds: 6) { isLandscape }
        }
        if request.scene?.showsKeyboard == true {
            await wait(seconds: 15) { keyboardShown }
        }
        // Algumas voltas do laço principal: o que mudou chega de fato à tela antes da contagem final.
        for _ in 0..<5 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                RunLoop.main.perform { continuation.resume() }
            }
            await pause(0.02)
        }
        await pause(1.5)
    }

    private static func wait(seconds: Double, until done: () -> Bool) async {
        let limit = Date().addingTimeInterval(seconds)
        while !done(), Date() < limit {
            await pause(0.1)
        }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Escreve `Documents/cena.txt`: a cena, a posição da tela, o tamanho da janela, o arranjo e o
    /// que o app tinha aberto naquele momento.
    private static func writeMarker(_ request: DemoRequest, state: AppState, seconds: Double) {
        var lines = ["cena=\(request.scene?.rawValue ?? "")"]
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let position: String
            switch windowScene.interfaceOrientation {
            case .landscapeLeft: position = "deitado-esquerda"
            case .landscapeRight: position = "deitado-direita"
            case .portraitUpsideDown: position = "em-pe-invertido"
            default: position = "em-pe"
            }
            lines.append("posicao=\(position)")
            if let size = windowScene.windows.first?.bounds.size {
                lines.append("janela=\(Int(size.width))x\(Int(size.height))")
                let layout = ScreenLayout.home(width: Double(size.width), height: Double(size.height))
                lines.append("arranjo=\(layout)")
            }
        }
        lines.append("tela=\(state.screen == .account ? "conta" : "inicial")")
        let dialog: String
        switch state.dialog {
        case .some(.code): dialog = "codigo"
        case .some(.newKey): dialog = "nova-chave"
        case .some(.unlink): dialog = "desconectar"
        case .none: dialog = "nenhuma"
        }
        lines.append("caixa=\(dialog)")
        lines.append("teclado=\(keyboardShown ? "sim" : "nao")")
        lines.append("espera=\(String(format: "%.1f", seconds))s")
        if let turnRefusal {
            lines.append("giro-recusado=\(turnRefusal)")
        }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: folder.appendingPathComponent("cena.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
