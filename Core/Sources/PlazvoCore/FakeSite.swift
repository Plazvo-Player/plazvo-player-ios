import Foundation

/// O servidor de mentira, dentro do próprio app. Guarda os aparelhos que se registram e responde
/// como o contrato da API (v1) manda, passando pelo mesmo leitor de respostas que o app usa com o
/// servidor de verdade.
///
/// Serve aos testes e à compilação do simulador, que nunca fala com o servidor de verdade.
public actor FakeSite: SiteApi {
    public struct Device: Sendable {
        public var key: String
        public let secret: String
        public var platform: String
        public var appVersion: String
        public var active = false
        public var blocked = false
        /// Fim da ativação, no formato do contrato.
        public var expiresAt: String?
        public var playlists: [List] = []
        /// Um parceiro cuida do aparelho pelo painel.
        public var partner = false
    }

    /// Uma lista como o servidor a entrega.
    public struct List: Sendable {
        public var id: Int64
        public var name: String
        /// `xtream` ou `m3u` (ou um tipo que o app não conhece, para os testes).
        public var type: String
        public var url: String
        public var username: String
        public var password: String

        public init(id: Int64, name: String, type: String = "xtream", url: String, username: String = "usuario", password: String = "senha") {
            self.id = id
            self.name = name
            self.type = type
            self.url = url
            self.username = username
            self.password = password
        }
    }

    /// Um código de ativação cadastrado no servidor de mentira.
    public struct Code: Sendable {
        public var days: Int
        public var usesLeft: Int
        public var disabled = false
        public var usedBy: [String] = []
        /// Código de parceiro cuja conta está sem créditos: `409 no_credits`.
        public var noCredits = false
    }

    public private(set) var devices: [String: Device] = [:]
    public private(set) var codes: [String: Code] = [:]
    /// Nomes das chamadas recebidas, na ordem: "register", "playlists", "activate-code", "unlink" e "ping".
    public private(set) var calls: [String] = []

    private var down = false
    private var refuseWith: Int?
    private var oldPanel = false
    private var setup: (@Sendable (inout Device) -> Void)?
    private let now: @Sendable () -> Date

    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: - Preparação

    /// Servidor fora do ar (ou aparelho sem internet): nenhuma chamada tem resposta.
    public func setDown(_ value: Bool) { down = value }

    /// Resposta 4xx para dar a todas as chamadas (por exemplo, 429), ou `nil`.
    public func setRefuseWith(_ status: Int?) { refuseWith = status }

    /// Painel antigo: não informa `partner` e responde 404 ao "Desconectar do painel".
    public func setOldPanel(_ value: Bool) { oldPanel = value }

    /// Aplicado a todo aparelho assim que ele se registra, e de novo a cada pedido de listas.
    public func setSetup(_ change: (@Sendable (inout Device) -> Void)?) { setup = change }

    /// Muda um aparelho já registrado.
    public func change(_ deviceId: String, _ change: @Sendable (inout Device) -> Void) {
        guard var device = devices[deviceId] else { return }
        change(&device)
        devices[deviceId] = device
    }

    /// Cadastra um código de ativação que ativa por `days` dias, até `uses` aparelhos.
    public func addCode(_ code: String, days: Int = 30, uses: Int = 3, noCredits: Bool = false, disabled: Bool = false) {
        codes[normalizeActivationCode(code)] = Code(days: days, usesLeft: uses, disabled: disabled, noCredits: noCredits)
    }

    /// Segura as respostas até `release()`: para ver o app durante uma consulta.
    public func hold() { held = true }

    public func release() {
        held = false
        let pending = waiting
        waiting = []
        for continuation in pending {
            continuation.resume()
        }
    }

    /// Quantas chamadas estão paradas, esperando o `release()`.
    public var waitingCalls: Int { waiting.count }

    private func pass() async {
        guard held else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    // MARK: - API

    public func register(_ credentials: DeviceCredentials, platform: String, appVersion: String) async -> ApiResult<Void> {
        calls.append("register")
        await pass()
        if down { return .unavailable }
        if let refuseWith { return .refused(status: refuseWith, error: nil) }
        if var known = devices[credentials.id] {
            if known.secret != credentials.secret { return .refused(status: 401, error: "invalid_credentials") }
            if known.blocked { return .refused(status: 403, error: "device_blocked") }
            known.key = credentials.key
            known.platform = platform
            known.appVersion = appVersion
            devices[credentials.id] = known
        } else {
            var device = Device(key: credentials.key, secret: credentials.secret, platform: platform, appVersion: appVersion)
            setup?(&device)
            devices[credentials.id] = device
        }
        return .ok(())
    }

    public func playlists(deviceId: String, secret: String) async -> ApiResult<PlaylistsAnswer> {
        calls.append("playlists")
        await pass()
        if down { return .unavailable }
        if let refuseWith { return .refused(status: refuseWith, error: nil) }
        guard var device = devices[deviceId], device.secret == secret else {
            return .refused(status: 401, error: "invalid_credentials")
        }
        setup?(&device)
        devices[deviceId] = device
        if device.blocked { return .refused(status: 403, error: "device_blocked") }

        var answer: [String: Any] = [
            "active": device.active,
            "expires_at": device.active ? (device.expiresAt as Any? ?? NSNull()) : NSNull(),
            "server_time": formatServerTime(now()),
            "playlists": device.active ? device.playlists.map(json) : [],
        ]
        if !oldPanel { answer["partner"] = device.partner }
        guard let text = text(answer), let parsed = try? parsePlaylistsAnswer(text) else { return .unavailable }
        return .ok(parsed)
    }

    public func activateWithCode(deviceId: String, secret: String, code: String) async -> ApiResult<CodeAnswer> {
        calls.append("activate-code")
        await pass()
        if down { return .unavailable }
        if let refuseWith { return .refused(status: refuseWith, error: nil) }
        guard var device = devices[deviceId], device.secret == secret else {
            return .refused(status: 401, error: "invalid_credentials")
        }
        if device.blocked { return .refused(status: 403, error: "device_blocked") }
        if code != normalizeActivationCode(code) || code.count != activationCodeLength {
            return .refused(status: 400, error: "invalid_request")
        }
        guard var known = codes[code] else { return .refused(status: 404, error: "invalid_code") }
        if known.disabled || known.usesLeft <= 0 { return .refused(status: 410, error: "code_unavailable") }
        if known.usedBy.contains(deviceId) { return .refused(status: 409, error: "code_used") }
        if device.active { return .refused(status: 409, error: "already_active") }
        if device.partner { return .refused(status: 409, error: "device_managed") }
        if known.noCredits { return .refused(status: 409, error: "no_credits") }

        known.usesLeft -= 1
        known.usedBy.append(deviceId)
        codes[code] = known
        device.active = true
        device.expiresAt = formatServerTime(now().addingTimeInterval(Double(known.days) * 86_400))
        device.playlists = []
        devices[deviceId] = device
        guard let parsed = try? parseCodeAnswer("{\"ok\": true, \"active\": true, \"days\": \(known.days)}") else { return .unavailable }
        return .ok(parsed)
    }

    public func unlink(deviceId: String, secret: String) async -> ApiResult<UnlinkAnswer> {
        calls.append("unlink")
        await pass()
        if down { return .unavailable }
        if let refuseWith { return .refused(status: refuseWith, error: nil) }
        if oldPanel { return .refused(status: 404, error: "not_found") }
        guard var device = devices[deviceId], device.secret == secret else {
            return .refused(status: 401, error: "invalid_credentials")
        }
        if device.blocked { return .refused(status: 403, error: "device_blocked") }
        let unlinked = device.partner
        device.partner = false
        devices[deviceId] = device
        guard let parsed = try? parseUnlinkAnswer("{\"ok\": true, \"unlinked\": \(unlinked), \"partner\": false}") else { return .unavailable }
        return .ok(parsed)
    }

    public func ping() async -> ApiResult<Void> {
        calls.append("ping")
        await pass()
        return down ? .unavailable : .ok(())
    }

    // MARK: - Texto das respostas

    private func json(_ list: List) -> [String: Any] {
        [
            "id": list.id,
            "name": list.name,
            "type": list.type,
            "url": list.url,
            "username": list.username,
            "password": list.password,
            "pin_protected": false,
        ]
    }

    private func text(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Uma hora no formato do contrato da API: `AAAA-MM-DDTHH:MM:SSZ`, em UTC.
public func formatServerTime(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    func two(_ value: Int?) -> String {
        let number = value ?? 0
        return number < 10 ? "0\(number)" : "\(number)"
    }
    let year = parts.year ?? 0
    let yearText = String(repeating: "0", count: max(0, 4 - String(year).count)) + String(year)
    return "\(yearText)-\(two(parts.month))-\(two(parts.day))T\(two(parts.hour)):\(two(parts.minute)):\(two(parts.second))Z"
}
