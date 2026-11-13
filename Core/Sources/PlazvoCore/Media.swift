import Foundation

/// De onde vem o vídeo.
public enum MediaKind: String, Equatable, Sendable, Codable {
    /// Vídeo de demonstração que vem dentro do app.
    case demo
    /// Arquivo escolhido no aparelho.
    case file
    /// Endereço http/https digitado ou colado pelo usuário.
    case link
}

/// Pedido para abrir um vídeo no reprodutor. No vídeo de demonstração o `uri` fica vazio.
public struct PlaybackRequest: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let kind: MediaKind
    /// O endereço do vídeo: http/https (link) ou o endereço do arquivo no aparelho.
    public let uri: String
    public let title: String
    /// Arquivo do aparelho: o marcador que o sistema entrega para o app voltar a ler o arquivo
    /// depois (pela lista de recentes). `nil` nos outros casos.
    public let access: Data?

    public init(kind: MediaKind, uri: String, title: String, access: Data? = nil) {
        self.kind = kind
        self.uri = uri
        self.title = title
        self.access = access
    }

    // O endereço pode levar usuário e senha: nunca pode ir parar num registro por descuido.
    public var description: String { "PlaybackRequest(kind: \(kind))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["kind": kind]) }
}

/// Um vídeo aberto recentemente, com o ponto onde o usuário parou.
public struct RecentMedia: Equatable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let uri: String
    public var title: String
    public var kind: MediaKind
    public var positionMs: Int64
    /// 0 quando a duração não é conhecida (por exemplo, transmissão ao vivo).
    public var durationMs: Int64
    /// Quando foi aberto pela última vez, em milissegundos desde 1970.
    public var lastPlayedAt: Int64
    /// Arquivo do aparelho: o marcador de acesso (ver `PlaybackRequest.access`).
    public var access: Data?

    public init(
        uri: String,
        title: String,
        kind: MediaKind,
        positionMs: Int64 = 0,
        durationMs: Int64 = 0,
        lastPlayedAt: Int64 = 0,
        access: Data? = nil
    ) {
        self.uri = uri
        self.title = title
        self.kind = kind
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.lastPlayedAt = lastPlayedAt
        self.access = access
    }

    private enum CodingKeys: String, CodingKey {
        case uri, title, kind, access
        case positionMs = "position"
        case durationMs = "duration"
        case lastPlayedAt = "lastPlayed"
    }

    /// Parte já assistida, de 0 a 1, ou `nil` quando a duração não é conhecida.
    public var progress: Double? {
        guard durationMs > 0 else { return nil }
        return min(max(Double(positionMs) / Double(durationMs), 0), 1)
    }

    /// Ponto de onde continuar. 0 quando é melhor começar do início (mal começou ou já acabou).
    public var resumePositionMs: Int64 {
        if positionMs < RecentMedia.minResumeMs { return 0 }
        if RecentMedia.isNearEnd(positionMs: positionMs, durationMs: durationMs) { return 0 }
        return positionMs
    }

    /// O ponto está no fim do vídeo: nos últimos 5 segundos ou nos últimos 2%, o que for maior.
    /// Sem duração conhecida, nunca.
    public static func isNearEnd(positionMs: Int64, durationMs: Int64) -> Bool {
        durationMs > 0 && positionMs > durationMs - max(minResumeMs, durationMs / 50)
    }

    /// O maior tempo que o app guarda ou mostra (o maior que o motor de vídeo informa: perto de
    /// 600 horas). Um número maior que este só aparece num arquivo estragado.
    public static let maxTimeMs = Int64(Int32.max)

    /// O pedido que reabre este vídeo.
    public var request: PlaybackRequest {
        PlaybackRequest(kind: kind, uri: uri, title: title, access: access)
    }

    private static let minResumeMs: Int64 = 5_000

    // O endereço pode levar usuário e senha: nunca pode ir parar num registro por descuido.
    public var description: String { "RecentMedia(kind: \(kind))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["kind": kind]) }
}

/// Tempo no formato 1:02:03 (com horas) ou 2:03 (sem horas), arredondado como no reprodutor.
public func formatDuration(_ millis: Int64) -> String {
    let whole = max(millis, 0)
    let totalSeconds = whole / 1000 + (whole % 1000 >= 500 ? 1 : 0)
    let hours = totalSeconds / 3600
    let minutes = totalSeconds % 3600 / 60
    let seconds = totalSeconds % 60
    func two(_ value: Int64) -> String { value < 10 ? "0\(value)" : "\(value)" }
    return hours > 0 ? "\(hours):\(two(minutes)):\(two(seconds))" : "\(minutes):\(two(seconds))"
}
