import Foundation

/// Uma lista cadastrada no site ou no painel para este aparelho.
public struct SitePlaylist: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public enum Kind: Equatable, Sendable {
        /// Servidor com usuário e senha (no contrato da API: `xtream`).
        case server
        /// Endereço de um arquivo de lista (no contrato da API: `m3u`).
        case link
    }

    public let id: Int64
    public let name: String
    public let kind: Kind
    /// Endereço do servidor (`.server`) ou do arquivo da lista (`.link`).
    public let url: String
    public let username: String
    public let password: String
    /// Endereço do guia de programação, quando o cadastro tem.
    public let epgUrl: String?
    public let pinProtected: Bool
    public let pinSalt: String?
    public let pinHash: String?

    public init(
        id: Int64,
        name: String,
        kind: Kind,
        url: String,
        username: String = "",
        password: String = "",
        epgUrl: String? = nil,
        pinProtected: Bool = false,
        pinSalt: String? = nil,
        pinHash: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.url = url
        self.username = username
        self.password = password
        self.epgUrl = epgUrl
        self.pinProtected = pinProtected
        self.pinSalt = pinSalt
        self.pinHash = pinHash
    }

    // O endereço, o usuário e a senha nunca podem ir parar num registro por descuido.
    public var description: String { "SitePlaylist(id: \(id))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["id": id]) }
}

/// Resposta do servidor ao pedido das listas.
public struct PlaylistsAnswer: Equatable, Sendable {
    public let active: Bool
    /// Fim da ativação. `nil` se o aparelho nunca foi ativado.
    public let expiresAt: Date?
    /// Hora do servidor ao responder, quando ele informa.
    public let serverTime: Date?
    public let playlists: [SitePlaylist]
    /// O texto recebido, para guardar como cópia.
    public let raw: String
    /// Um parceiro cuida deste aparelho pelo painel; `nil` quando o servidor não informou.
    public let partner: Bool?
}

/// Resposta do servidor a um código de ativação aceito (`POST /device/activate-code`).
public struct CodeAnswer: Equatable, Sendable {
    /// Por quantos dias o código ativou o aparelho, quando o servidor informa.
    public let days: Int?
}

/// Resposta do servidor ao pedido de sair do painel (`POST /device/unlink`).
public struct UnlinkAnswer: Equatable, Sendable {
    /// O aparelho saiu do painel de um parceiro agora; `false` se não estava em nenhum.
    public let unlinked: Bool
}

/// Resultado de uma chamada à API.
public enum ApiResult<Value: Sendable>: Sendable {
    case ok(Value)

    /// O servidor recusou o pedido (resposta 4xx). `error` é o nome do motivo que vem no corpo da
    /// resposta (`invalid_code`, por exemplo), ou `nil` quando a resposta não trouxe um.
    case refused(status: Int, error: String?)

    /// Não houve resposta que sirva: sem internet, tempo esgotado, servidor reiniciando (5xx) ou
    /// resposta que não deu para ler. O app usa a cópia guardada e tenta de novo mais tarde.
    case unavailable
}

/// As chamadas do contrato da API (v1) que o app usa.
public protocol SiteApi: Sendable {
    /// Apresenta o aparelho ao servidor: cria o cadastro dele ou atualiza a chave e a versão.
    func register(_ credentials: DeviceCredentials, platform: String, appVersion: String) async -> ApiResult<Void>

    /// Listas vinculadas ao aparelho e situação da ativação.
    func playlists(deviceId: String, secret: String) async -> ApiResult<PlaylistsAnswer>

    /// Ativa o aparelho com um código de ativação digitado pelo usuário.
    func activateWithCode(deviceId: String, secret: String, code: String) async -> ApiResult<CodeAnswer>

    /// Tira o aparelho do painel do parceiro que cuida dele. As listas e a ativação continuam.
    func unlink(deviceId: String, secret: String) async -> ApiResult<UnlinkAnswer>

    /// `GET /ping`: o servidor responde? (Não manda nada do aparelho.)
    func ping() async -> ApiResult<Void>
}

/// A resposta não segue o contrato da API.
public struct AnswerFormatError: Error, Equatable {
    public let field: String
}

/// O código como o servidor o entende: sem espaços nem traços, em maiúsculas.
public func normalizeActivationCode(_ text: String) -> String {
    String(text.filter { $0.isLetter || $0.isNumber }).uppercased()
}

/// O código como a tela o mostra: "ABCD-EFGH-JKMN" (o traço é só desenho).
public func formattedActivationCode(_ normalized: String) -> String {
    var groups: [String] = []
    var rest = Substring(normalized)
    while !rest.isEmpty {
        groups.append(String(rest.prefix(4)))
        rest = rest.dropFirst(4)
    }
    return groups.joined(separator: "-")
}

/// Quantas letras e números tem um código de ativação.
public let activationCodeLength = 12

/// Lê a resposta de `POST /device/activate-code`. Lança se não for um objeto JSON.
public func parseCodeAnswer(_ text: String) throws -> CodeAnswer {
    guard let fields = try JSONValue.parse(text).fields else { throw AnswerFormatError(field: "") }
    let days = fields["days"]?.whole
    return CodeAnswer(days: (days ?? 0) > 0 ? days : nil)
}

/// Lê a resposta de `POST /device/unlink`. Lança se não for um objeto JSON.
public func parseUnlinkAnswer(_ text: String) throws -> UnlinkAnswer {
    guard let fields = try JSONValue.parse(text).fields else { throw AnswerFormatError(field: "") }
    return UnlinkAnswer(unlinked: fields["unlinked"]?.flag ?? false)
}

/// Lê a resposta de `GET /device/playlists`. Lança se ela não seguir o contrato.
/// Lista de um tipo que este app não conhece, sem número ou sem endereço, é deixada de fora.
public func parsePlaylistsAnswer(_ text: String) throws -> PlaylistsAnswer {
    guard let fields = try JSONValue.parse(text).fields else { throw AnswerFormatError(field: "") }
    guard let active = fields["active"]?.flag else { throw AnswerFormatError(field: "active") }

    var playlists: [SitePlaylist] = []
    if case .array(let items)? = fields["playlists"] {
        for item in items {
            guard let entry = item.fields else { continue }
            let kind: SitePlaylist.Kind
            switch entry.text("type") {
            case "xtream": kind = .server
            case "m3u": kind = .link
            default: continue
            }
            let url = (entry.text("url") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, let id = entry.text("id").flatMap({ Int64($0) }) else { continue }
            let pinHash = entry.text("pin_hash")
            playlists.append(
                SitePlaylist(
                    id: id,
                    name: entry.text("name") ?? "",
                    kind: kind,
                    url: url,
                    username: entry.text("username") ?? "",
                    password: entry.text("password") ?? "",
                    epgUrl: entry.text("epg_url"),
                    // Lista que traz o resumo de um PIN é protegida, diga o que disser o outro campo.
                    pinProtected: (entry["pin_protected"]?.flag ?? false) || !(pinHash ?? "").isEmpty,
                    pinSalt: entry.text("pin_salt"),
                    pinHash: pinHash
                )
            )
        }
    }

    // Fim da ativação que não dá para entender não pode virar "sem fim".
    var expiresAt: Date?
    if let value = fields.text("expires_at") {
        guard let date = parseServerTime(value) else { throw AnswerFormatError(field: "expires_at") }
        expiresAt = date
    }

    return PlaylistsAnswer(
        active: active,
        expiresAt: expiresAt,
        serverTime: fields.text("server_time").flatMap(parseServerTime),
        playlists: playlists,
        raw: text,
        partner: fields["partner"]?.flag
    )
}

/// Hora no formato do contrato (`AAAA-MM-DDTHH:MM:SSZ`, UTC), ou `nil` se o texto não é isso.
public func parseServerTime(_ text: String) -> Date? {
    // Lido à mão, campo a campo: o formato é fixo e nenhuma data "quase certa" pode passar.
    let characters = Array(text.utf8)
    guard characters.count == 20 else { return nil }
    func digits(_ range: Range<Int>) -> Int? {
        var value = 0
        for index in range {
            let byte = characters[index]
            guard byte >= 48, byte <= 57 else { return nil }
            value = value * 10 + Int(byte - 48)
        }
        return value
    }
    func isByte(_ index: Int, _ character: Character) -> Bool {
        characters[index] == character.asciiValue
    }
    guard isByte(4, "-"), isByte(7, "-"), isByte(10, "T"), isByte(13, ":"), isByte(16, ":"), isByte(19, "Z"),
          let year = digits(0..<4), let month = digits(5..<7), let day = digits(8..<10),
          let hour = digits(11..<13), let minute = digits(14..<16), let second = digits(17..<19),
          (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60
    else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    var parts = DateComponents()
    parts.year = year
    parts.month = month
    parts.day = day
    parts.hour = hour
    parts.minute = minute
    parts.second = second
    guard let date = calendar.date(from: parts) else { return nil }
    // 31 de fevereiro e parecidos: o calendário "arruma" a data; aqui isso é data errada.
    let back = calendar.dateComponents([.year, .month, .day], from: date)
    guard back.year == year, back.month == month, back.day == day else { return nil }
    return date
}
