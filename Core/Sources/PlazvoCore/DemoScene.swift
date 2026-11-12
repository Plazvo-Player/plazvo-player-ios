import Foundation

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

    /// O código de ativação de exemplo, que o servidor de mentira aceita (365 dias).
    public static let exampleCode = "ABCDEFGHJKMN"

    /// Um código que o servidor de mentira não conhece.
    public static let unknownCode = "ZZZZZZZZZZZZ"

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
        case .home, .account, .code, .wrongCode, .activated, .newKey, .copied:
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

    /// Leva o app à situação da cena. Chamar depois da consulta de abertura (`AppController.start`).
    @MainActor
    public func play(on app: AppController) async {
        switch self {
        case .home, .active, .offline, .blocked, .expiring, .expired:
            break
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
