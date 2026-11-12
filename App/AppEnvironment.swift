import Foundation
import PlazvoCore
import UIKit

/// As peças do app, montadas de um jeito no simulador e de outro no aparelho.
///
/// Regra do projeto: a compilação do simulador nunca fala com o servidor de verdade. Nela o
/// servidor, o cofre e a cópia guardada são de mentira (só na memória), e o endereço do servidor
/// de verdade nem entra no app. No aparelho: o servidor de verdade, o cofre do iPhone e a cópia
/// num arquivo protegido.
@MainActor
struct AppEnvironment {
    let controller: AppController
    /// A versão do app ("0.1.0").
    let version: String
    /// A hora fixa das fotos das telas; `nil` fora delas (vale o relógio do aparelho).
    let fixedNow: Date?
    /// O que o campo do código já traz digitado (só nas cenas das fotos).
    let typedCode: String
    /// O que fazer ao abrir o app.
    let start: () async -> Void

    static func make() -> AppEnvironment {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let platform = "ios"
        let copyText: (String) -> Void = { UIPasteboard.general.string = $0 }

        #if targetEnvironment(simulator)
        let request = DemoRequest(arguments: ProcessInfo.processInfo.arguments)
        let scene = request.scene
        // Nas cenas das fotos, a hora é fixa e o ID e a chave são os de exemplo.
        let fixedNow: Date? = scene == nil ? nil : DemoScene.photoTime()
        let now: @Sendable () -> Date = { fixedNow ?? Date() }
        let site = FakeSite(now: now)
        let identityStore = DeviceIdentityStore(
            store: InMemorySecureStore(),
            random: scene == nil ? .system : DemoScene.exampleRandom()
        )
        let siteLists = SiteLists(
            api: site,
            identityStore: identityStore,
            copy: InMemoryCopyStore(),
            platform: platform,
            appVersion: version,
            now: now
        )
        let controller = AppController(
            identityStore: identityStore,
            siteLists: siteLists,
            copyText: copyText,
            // Nas fotos o aviso de "copiado" fica na tela.
            noticeSeconds: scene == nil ? 1.6 : nil
        )
        return AppEnvironment(
            controller: controller,
            version: version,
            fixedNow: fixedNow,
            typedCode: scene?.typedCode ?? "",
            start: {
                SimulatorScenes.rotateIfAsked(request)
                await (scene ?? .home).prepare(site, now: now())
                await controller.start()
                if let scene {
                    await scene.play(on: controller)
                }
                await SimulatorScenes.markReady(request)
            }
        )
        #else
        let api = HttpSiteApi(baseURL: "https://api.plazvo.com/v1", userAgent: "PlazvoPlayer/\(version) (\(platform))")
        let identityStore = DeviceIdentityStore(store: KeychainStore(service: "com.plazvo.player.device", account: "identity"))
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let siteLists = SiteLists(
            api: api,
            identityStore: identityStore,
            copy: FileCopyStore(url: folder.appendingPathComponent("site-answer.json")),
            platform: platform,
            appVersion: version
        )
        let controller = AppController(identityStore: identityStore, siteLists: siteLists, copyText: copyText)
        return AppEnvironment(
            controller: controller,
            version: version,
            fixedNow: nil,
            typedCode: "",
            start: { await controller.start() }
        )
        #endif
    }
}
