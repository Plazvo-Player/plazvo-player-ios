#if targetEnvironment(simulator)
import PlazvoCore
import UIKit

/// Só na compilação do simulador, para as fotos das telas: deita a tela quando a linha de comando
/// pede e avisa, num arquivo, que a cena está pronta (a compilação na nuvem espera por ele antes
/// de fotografar). O app do aparelho de verdade não leva nada disto.
@MainActor
enum SimulatorScenes {
    static func rotateIfAsked(_ request: DemoRequest) {
        guard request.landscape, #available(iOS 16.0, *) else { return }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            let landscape = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeRight)
            windowScene.requestGeometryUpdate(landscape) { _ in }
        }
    }

    /// Escreve `Documents/cena.txt` com a cena aberta, a posição da tela e o tamanho da janela.
    static func markReady(_ request: DemoRequest) async {
        // Um instante para a tela assentar (a troca de tela, a caixa, a tela deitada).
        try? await Task.sleep(nanoseconds: 1_500_000_000)
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
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: folder.appendingPathComponent("cena.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
