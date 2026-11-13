import Foundation
import PlazvoCore
import UIKit

/// As peças do app, montadas de um jeito no simulador e de outro no aparelho.
///
/// Regra do projeto: a compilação do simulador nunca fala com o servidor de verdade. Nela o
/// servidor, o cofre e a cópia guardada são de mentira (só na memória), e o endereço do servidor
/// de verdade nem entra no app. No aparelho: o servidor de verdade, o cofre do iPhone e a cópia
/// num arquivo protegido. O reprodutor de vídeo é o mesmo nos dois.
@MainActor
struct AppEnvironment {
    let controller: AppController
    /// A versão do app ("0.1.0").
    let version: String
    /// A hora fixa das fotos das telas; `nil` fora delas (vale o relógio do aparelho).
    let fixedNow: Date?
    /// O que o campo do código já traz digitado (só nas cenas das fotos).
    let typedCode: String
    /// O que o campo do link já traz digitado (só nas cenas das fotos).
    let typedLink: String
    /// O acesso aos vídeos do aparelho (o arquivo escolhido no seletor do sistema passa por aqui).
    let media: DeviceMediaAccess
    /// O que fazer ao abrir o app.
    let start: () async -> Void

    static func make() -> AppEnvironment {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let platform = "ios"
        let copyText: (String) -> Void = { UIPasteboard.general.string = $0 }

        // O vídeo: o motor do VLC, o acesso aos arquivos e a conferência de um vídeo que não abre.
        // O link que o usuário abre é a única conversa do reprodutor com a internet.
        let videoAgent = "PlazvoPlayer/\(version) (iOS \(UIDevice.current.systemVersion))"
        let media = DeviceMediaAccess()
        let playback = PlaybackParts(
            makeEngine: { VLCVideoEngine(userAgent: videoAgent) },
            access: media,
            diagnosis: PlaybackCheck(userAgent: videoAgent)
        )

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
        // Os vídeos recentes só ficam na memória (nas cenas das fotos, já com os de exemplo).
        let recentMedia = RecentMediaStore(storage: InMemoryCopyStore(data: scene?.storedRecents(now: now())), now: now)
        let controller = AppController(
            identityStore: identityStore,
            siteLists: siteLists,
            recentMedia: recentMedia,
            playback: playback,
            copyText: copyText,
            // Nas fotos o aviso de "copiado" fica na tela.
            noticeSeconds: scene == nil ? 1.6 : nil
        )
        return AppEnvironment(
            controller: controller,
            version: version,
            fixedNow: fixedNow,
            typedCode: scene?.typedCode ?? "",
            typedLink: scene?.typedLink ?? "",
            media: media,
            start: {
                await SimulatorScenes.run(request, site: site, now: now(), controller: controller)
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
        // Os vídeos recentes ficam num arquivo protegido e fora das cópias de segurança: o endereço
        // de um link pode levar usuário e senha.
        let recentMedia = RecentMediaStore(storage: FileCopyStore(url: folder.appendingPathComponent("recent-media.json")))
        let controller = AppController(
            identityStore: identityStore,
            siteLists: siteLists,
            recentMedia: recentMedia,
            playback: playback,
            copyText: copyText
        )
        return AppEnvironment(
            controller: controller,
            version: version,
            fixedNow: nil,
            typedCode: "",
            typedLink: "",
            media: media,
            start: { await controller.start() }
        )
        #endif
    }
}
