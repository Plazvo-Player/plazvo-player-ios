import Foundation

// Fica de fora do app do aparelho de verdade: só os testes e a compilação do simulador usam.
#if !os(iOS) || targetEnvironment(simulator)
/// As cenas que a compilação do simulador sabe abrir, para as fotos das telas: cada uma deixa o
/// servidor de mentira e o app numa situação, pelos mesmos caminhos dos toques do usuário.
/// O app do aparelho de verdade não usa nada daqui.
public enum DemoScene: String, CaseIterable, Sendable {
    /// Tela inicial, aparelho ainda não ativo.
    case home = "inicial"
    /// Conta, aparelho ainda não ativo.
    case account = "conta"
    /// Conta com a caixa do código aberta e um código digitado.
    case code = "codigo"
    /// A caixa do código depois de um código que o servidor não conhece.
    case wrongCode = "codigo-errado"
    /// Conta depois de ativar com um código.
    case activated = "ativado"
    /// Tela inicial com a caixa "Gerar uma nova chave?".
    case newKey = "nova-chave"
    /// Tela inicial (aparelho ativo, cuidado por um parceiro) com a caixa "Desconectar do painel?".
    case unlink = "desconectar"
    /// Tela inicial logo depois de copiar a chave.
    case copied = "copiado"
    /// Tela inicial, aparelho ativo.
    case active = "ativo"
    /// Tela inicial sem resposta do servidor.
    case offline = "sem-conexao"
    /// Tela inicial, aparelho bloqueado.
    case blocked = "bloqueado"
    /// Tela inicial, ativação que vence em menos de 7 dias.
    case expiring = "vencendo"
    /// Tela inicial, ativação vencida.
    case expired = "vencido"
    /// Mídia, sem vídeos recentes.
    case media = "midia"
    /// Mídia com três vídeos recentes.
    case mediaRecents = "midia-recentes"
    /// "Abrir link de vídeo" com um endereço digitado.
    case link = "link"
    /// "Abrir link de vídeo" depois de um endereço que não vale.
    case wrongLink = "link-errado"
    /// O reprodutor com o vídeo de demonstração parado aos 9 segundos, com os controles na tela.
    case player = "reprodutor"
    /// O reprodutor com a mensagem de um link que não respondeu.
    case playerProblem = "video-falhou"

    /// O código de ativação de exemplo, que o servidor de mentira aceita (365 dias).
    public static let exampleCode = "ABCDEFGHJKMN"

    /// Um código que o servidor de mentira não conhece.
    public static let unknownCode = "ZZZZZZZZZZZZ"

    /// Um link que não responde: a porta 9 do próprio aparelho, onde nada atende. O pedido nem
    /// sai do aparelho.
    public static let deadLink = "http://127.0.0.1:9/aula-de-violao-03.mkv"

    /// O ponto em que o vídeo de demonstração fica parado na foto do reprodutor.
    public static let playerPhotoMs: Int64 = 9_000

    /// Os vídeos recentes das fotos (os mesmos nomes inventados do desenho das telas).
    public static func exampleRecents(now: Date) -> [RecentMedia] {
        let at = Int64((now.timeIntervalSince1970 * 1000).rounded())
        let hour: Int64 = 3_600_000
        return [
            RecentMedia(
                uri: "file:///exemplo/Anivers%C3%A1rio%20da%20Ana.mp4", title: "Aniversário da Ana.mp4", kind: .file,
                positionMs: 754_000, durationMs: 2_890_000, lastPlayedAt: at - hour
            ),
            RecentMedia(
                uri: "http://exemplo.com/aulas/aula-de-violao-03.mkv", title: "aula-de-violao-03.mkv", kind: .link,
                positionMs: 0, durationMs: 3_723_000, lastPlayedAt: at - 24 * hour
            ),
            RecentMedia(
                uri: "file:///exemplo/passeio-na-praia.mov", title: "passeio-na-praia.mov", kind: .file,
                positionMs: 185_000, durationMs: 340_000, lastPlayedAt: at - 48 * hour
            ),
        ]
    }

    /// O que a lista de recentes já traz guardado quando o app abre nesta cena (`nil`: nada).
    public func storedRecents(now: Date) -> Data? {
        guard self == .mediaRecents else { return nil }
        return try? JSONEncoder().encode(DemoScene.exampleRecents(now: now))
    }

    /// A hora das fotos: 14:30 do dia `day`, no fuso do aparelho (a mesma hora que a compilação na
    /// nuvem põe na barra do alto do simulador; a data da barra é a de verdade).
    public static func photoTime(on day: Date = Date(), timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = 14
        parts.minute = 30
        return calendar.date(from: parts) ?? day
    }

    /// O ID e a chave de exemplo das fotos (os mesmos do desenho das telas). O segredo e as chaves
    /// seguintes ("Nova chave") são sorteados de verdade.
    public static func exampleRandom() -> RandomSource {
        final class Turn { var value = 0 }
        let turn = Turn()
        let system = RandomSource.system
        return RandomSource(
            bytes: { count in
                count == 6 ? [0x7C, 0x2E, 0x9A, 0x41, 0xD0, 0xB6] : system.bytes(count)
            },
            number: { range in
                turn.value += 1
                return turn.value == 1 ? 483_920 : system.number(range)
            }
        )
    }

    /// Prepara o servidor de mentira para a cena. `now` é a hora que o app e o servidor usam.
    public func prepare(_ site: FakeSite, now: Date) async {
        await site.addCode(DemoScene.exampleCode, days: 365)
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .home, .account, .code, .wrongCode, .activated, .newKey, .copied,
             .media, .mediaRecents, .link, .wrongLink, .player, .playerProblem:
            break
        case .active:
            await site.setSetup(DemoScene.active(until: now.addingTimeInterval(365 * day), partner: false))
        case .unlink:
            await site.setSetup(DemoScene.active(until: now.addingTimeInterval(365 * day), partner: true))
        case .expiring:
            await site.setSetup(DemoScene.active(until: now.addingTimeInterval(5 * day), partner: false))
        case .expired:
            await site.setSetup(DemoScene.active(until: now.addingTimeInterval(-2 * day), partner: false))
        case .offline:
            await site.setDown(true)
        case .blocked:
            await site.setSetup { $0.blocked = true }
        }
    }

    private static func active(until: Date, partner: Bool) -> @Sendable (inout FakeSite.Device) -> Void {
        let expiresAt = formatServerTime(until)
        return { device in
            device.active = true
            device.expiresAt = expiresAt
            device.partner = partner
        }
    }

    /// O que o campo do código já traz digitado quando a caixa abre.
    public var typedCode: String {
        switch self {
        case .code, .activated: return DemoScene.exampleCode
        case .wrongCode: return DemoScene.unknownCode
        default: return ""
        }
    }

    /// O que o campo do link já traz digitado quando a tela abre.
    public var typedLink: String {
        switch self {
        case .link: return "http://exemplo.com/video.mp4"
        case .wrongLink: return "meu video"
        default: return ""
        }
    }

    /// A cena termina com o teclado na tela: a caixa do código ou o campo do link, à espera do
    /// usuário.
    public var showsKeyboard: Bool {
        switch self {
        case .code, .wrongCode, .link, .wrongLink: return true
        default: return false
        }
    }

    /// A cena termina no reprodutor (que, no iPhone, deita a tela sozinho).
    public var showsPlayer: Bool {
        self == .player || self == .playerProblem
    }

    /// Leva o app à situação da cena. Chamar depois da consulta de abertura (`AppController.start`).
    /// - Parameters:
    ///   - demoTitle: o nome do vídeo de demonstração no idioma do app.
    ///   - patience: quanto esperar, em segundos, pelo reprodutor (abrir o vídeo, dar a falha).
    @MainActor
    public func play(on app: AppController, demoTitle: String = "Big Buck Bunny", patience: Double = 60) async {
        switch self {
        case .home, .active, .offline, .blocked, .expiring, .expired:
            break
        case .media, .mediaRecents:
            app.openMedia()
        case .link:
            app.openMedia()
            app.openLinkScreen()
        case .wrongLink:
            app.openMedia()
            app.openLinkScreen()
            app.openLink(typedLink)
        case .player:
            app.openMedia()
            app.playDemo(title: demoTitle)
            guard let player = app.player else { return }
            // Espera o vídeo andar, leva-o ao ponto da foto, espera a imagem desse ponto e para.
            await DemoScene.wait(patience) { player.state.status == .playing || player.state.problem != nil }
            guard player.state.status == .playing else { return }
            player.seek(toMs: DemoScene.playerPhotoMs)
            await DemoScene.wait(patience / 2) { player.state.positionMs > DemoScene.playerPhotoMs || player.state.status == .ended }
            guard player.state.status != .ended else { return }
            player.togglePlay()
            // Parado, o tempo da tela fica exatamente no ponto da foto.
            player.seek(toMs: DemoScene.playerPhotoMs)
        case .playerProblem:
            app.openMedia()
            app.openLinkScreen()
            app.openLink(DemoScene.deadLink)
            guard let player = app.player else { return }
            await DemoScene.wait(patience) { player.state.problem != nil }
        case .account:
            app.openAccount()
        case .code:
            app.openAccount()
            app.openCodeDialog()
        case .wrongCode:
            app.openAccount()
            app.openCodeDialog()
            await app.activateWithCode(DemoScene.unknownCode)
        case .activated:
            app.openAccount()
            app.openCodeDialog()
            await app.activateWithCode(DemoScene.exampleCode)
        case .newKey:
            app.openNewKeyDialog()
        case .unlink:
            app.openUnlinkDialog()
        case .copied:
            app.copy(.key)
        }
    }
}

extension DemoScene {
    /// Espera, até `seconds`, uma condição ficar verdadeira.
    @MainActor
    static func wait(_ seconds: Double, until done: () -> Bool) async {
        let limit = Date().addingTimeInterval(seconds)
        while !done(), Date() < limit {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

/// O que a linha de comando pede à compilação do simulador:
/// `-PlazvoCena <nome>` abre uma cena; `-PlazvoDeitado` deita a tela.
public struct DemoRequest: Equatable, Sendable {
    public var scene: DemoScene?
    public var landscape = false

    public init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "-PlazvoCena":
                if index + 1 < arguments.count {
                    scene = DemoScene(rawValue: arguments[index + 1])
                    index += 1
                }
            case "-PlazvoDeitado":
                landscape = true
            default:
                break
            }
            index += 1
        }
    }
}
#endif
