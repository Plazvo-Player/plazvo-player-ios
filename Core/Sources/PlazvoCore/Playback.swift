import Foundation

/// Uma faixa de áudio ou de legenda do vídeo.
public struct MediaTrack: Equatable, Sendable {
    /// O número que o motor de vídeo dá à faixa.
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// O que o motor de vídeo avisa enquanto um vídeo está aberto.
public enum EngineEvent: Equatable, Sendable {
    /// Começou a abrir o endereço.
    case opening
    /// Está juntando vídeo para tocar. Pode chegar várias vezes, mesmo com o vídeo já andando.
    case buffering
    /// O vídeo está tocando.
    case playing
    /// O vídeo chegou ao fim.
    case ended
    /// O vídeo não abriu ou parou por erro. O motor não diz o motivo.
    case failed
    /// O ponto atual e a duração (0 quando não é conhecida), em milissegundos.
    case time(positionMs: Int64, durationMs: Int64)
    case videoSize(width: Int, height: Int)
    /// As faixas de áudio ou de legenda mudaram.
    case tracksChanged
}

/// O motor de vídeo, como a lógica o vê. No app é o do VLC; nos testes, um de mentira.
@MainActor
public protocol VideoEngine: AnyObject {
    var onEvent: ((EngineEvent) -> Void)? { get set }

    /// Abre o endereço e começa a tocar a partir de `startAtMs` (larga o vídeo que estava aberto).
    func open(uri: String, startAtMs: Int64)
    func play()
    func pause()
    func stop()
    func seek(toMs: Int64)

    /// O vídeo está andando agora (nem pausado, nem parado).
    var isPlaying: Bool { get }
    var positionMs: Int64 { get }
    /// 0 quando a duração não é conhecida (transmissão ao vivo).
    var durationMs: Int64 { get }
    var isSeekable: Bool { get }
    /// Velocidade: 1 é a normal.
    var rate: Double { get set }

    var audioTracks: [MediaTrack] { get }
    /// A faixa de áudio em uso, ou `nil` se o motor não informa.
    var audioTrack: Int? { get set }
    var subtitleTracks: [MediaTrack] { get }
    /// A legenda em uso, ou `nil` com as legendas desligadas.
    var subtitleTrack: Int? { get set }
}

/// O acesso ao vídeo pedido. No app: o vídeo de demonstração que vem dentro dele, o arquivo do
/// aparelho (com o marcador de acesso que o sistema entregou) ou o próprio link.
@MainActor
public protocol MediaAccess: AnyObject {
    /// O endereço que o motor de vídeo abre, ou `nil` se o vídeo não está mais lá. O acesso fica
    /// aberto até `close()`.
    func open(_ request: PlaybackRequest) -> String?
    /// Devolve ao sistema o acesso pedido em `open`.
    func close()
}

/// Por que um vídeo não abriu, depois de conferido.
public enum PlaybackFailure: Equatable, Sendable {
    /// O endereço não respondeu (sem internet, servidor fora do ar, tempo esgotado).
    case network
    /// O servidor respondeu com um número de erro.
    case http(status: Int)
    /// O arquivo não está mais lá (ou o acesso a ele acabou).
    case notFound
    /// O endereço responde (ou o arquivo existe), mas o reprodutor não toca o formato.
    case format
    case unknown
}

/// O que mostrar ao usuário quando o vídeo não abre.
public struct PlaybackProblem: Equatable, Sendable {
    /// O texto que explica o problema.
    public let message: TextRef
    /// Código para o suporte (os mesmos números do app Android para cada tipo de falha).
    public let code: Int

    public init(message: TextRef, code: Int) {
        self.message = message
        self.code = code
    }
}

/// Traduz a falha em uma mensagem simples, como o app Android.
public func problemFor(kind: MediaKind, failure: PlaybackFailure) -> PlaybackProblem {
    switch failure {
    case .http(let status):
        return PlaybackProblem(message: TextRef("player_error_http", [String(status)]), code: 2004)
    case .notFound:
        return PlaybackProblem(message: TextRef("player_error_not_found"), code: 2005)
    case .network:
        // No link é a conexão; no arquivo, ele sumiu ou o acesso acabou.
        switch kind {
        case .link: return PlaybackProblem(message: TextRef("player_error_network"), code: 2001)
        case .file: return PlaybackProblem(message: TextRef("player_error_not_found"), code: 2005)
        case .demo: return PlaybackProblem(message: TextRef("player_error_generic"), code: 1000)
        }
    case .format:
        return PlaybackProblem(message: TextRef("player_error_format"), code: 3003)
    case .unknown:
        return PlaybackProblem(message: TextRef("player_error_generic"), code: 1000)
    }
}

/// Confere por que um vídeo não abriu (o motor de vídeo só diz que deu erro).
public protocol PlaybackDiagnosis: Sendable {
    /// `address` é o endereço que o motor tentou abrir.
    func failure(of kind: MediaKind, address: String) async -> PlaybackFailure
}

/// As contas do tamanho com que um vídeo aparece na tela.
public enum VideoGeometry {
    /// O tamanho com que o vídeo aparece, a partir do que o arquivo informa, ou `nil` se o
    /// arquivo ainda não informou o tamanho.
    /// - Parameters:
    ///   - sarNum, sarDen: a proporção de cada ponto do vídeo (1 por 1 quando não informada).
    ///   - orientation: a posição em que o vídeo foi gravado, de 0 a 7, como o motor informa.
    ///     De 4 em diante ele foi gravado de lado, e a largura e a altura trocam de lugar.
    public static func displaySize(width: Int, height: Int, sarNum: Int, sarDen: Int, orientation: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        var shown = width
        if sarNum > 0, sarDen > 0, sarNum != sarDen {
            shown = Int((Double(width) * Double(sarNum) / Double(sarDen)).rounded())
        }
        guard shown > 0 else { return nil }
        return orientation >= 4 && orientation <= 7 ? (height, shown) : (shown, height)
    }
}
