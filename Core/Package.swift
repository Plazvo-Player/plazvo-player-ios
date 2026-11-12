// swift-tools-version: 5.9
import PackageDescription

// A lógica do Plazvo Player, sem tela: identidade do aparelho, conversa com o servidor e
// situação da ativação. Fica separada do app para ser testada sem simulador.
let package = Package(
    name: "PlazvoCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "PlazvoCore", targets: ["PlazvoCore"]),
    ],
    targets: [
        .target(name: "PlazvoCore"),
        .testTarget(name: "PlazvoCoreTests", dependencies: ["PlazvoCore"]),
    ]
)
