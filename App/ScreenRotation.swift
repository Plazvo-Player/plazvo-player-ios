import UIKit

/// As posições em que a tela do app pode ficar.
///
/// Fora do reprodutor, as que o aparelho permite. No reprodutor do iPhone, a tela acompanha o
/// vídeo: deita com um vídeo deitado e fica em pé com um vídeo gravado em pé. No iPad o sistema
/// não deixa o app girar a tela: o vídeo aparece na posição em que o aparelho estiver.
@MainActor
enum ScreenRotation {
    /// As posições permitidas agora (o sistema pergunta por elas ao `AppDelegate`).
    private(set) static var allowed: UIInterfaceOrientationMask = .all

    /// O reprodutor abriu, ou o vídeo mostrou em que posição foi gravado.
    static func follow(portraitVideo: Bool) {
        apply(portraitVideo ? .portrait : .landscape)
    }

    /// O reprodutor fechou: a tela volta a acompanhar o aparelho.
    static func release() {
        apply(.all)
    }

    private static func apply(_ wanted: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone, wanted != allowed else { return }
        allowed = wanted
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            // No iPhone, de cabeça para baixo não vale: o pedido usa só as posições que ele aceita.
            let asked = wanted == .all ? UIInterfaceOrientationMask.allButUpsideDown : wanted
            windowScene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: asked)) { _ in }
        }
    }
}

/// Só existe para dizer ao sistema em que posições a tela pode ficar.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        ScreenRotation.allowed
    }
}
