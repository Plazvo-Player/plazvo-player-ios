import Foundation
@testable import PlazvoCore

/// Relógio de mentira, que o teste adianta quando quer.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ text: String = "2026-10-05T19:00:00Z") {
        value = parseServerTime(text)!
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ text: String) {
        lock.lock()
        value = parseServerTime(text)!
        lock.unlock()
    }
}

/// Sorteio previsível: os bytes e os números saem de uma conta simples, sempre na mesma ordem.
func predictableRandom(seed: UInt64 = 1) -> RandomSource {
    final class State { var value: UInt64; init(_ value: UInt64) { self.value = value } }
    let state = State(seed)
    func next() -> UInt64 {
        state.value = state.value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state.value >> 33
    }
    return RandomSource(
        bytes: { count in (0..<count).map { _ in UInt8(truncatingIfNeeded: next()) } },
        number: { range in range.lowerBound + Int(next() % UInt64(range.count)) }
    )
}

/// Tudo o que um teste da situação do aparelho precisa, já ligado: servidor de mentira, cofre,
/// cópia guardada e relógio.
@MainActor
final class Bench {
    let clock = TestClock()
    let site: FakeSite
    let secure = InMemorySecureStore()
    let copy = InMemoryCopyStore()
    let identity: DeviceIdentityStore
    private(set) var lists: SiteLists
    private(set) var changes: [SiteListsState] = []

    init() {
        let clock = self.clock
        site = FakeSite(now: { clock.now })
        identity = DeviceIdentityStore(store: secure, random: predictableRandom())
        lists = SiteLists(api: site, identityStore: identity, copy: copy, platform: "ios", appVersion: "0.1.0", now: { clock.now })
        lists.onChange = { [unowned self] in self.changes.append($0) }
    }

    /// O app foi fechado e aberto de novo: a situação começa do zero, com o mesmo cofre e a mesma cópia.
    func reopen() {
        let clock = self.clock
        lists = SiteLists(api: site, identityStore: identity, copy: copy, platform: "ios", appVersion: "0.1.0", now: { clock.now })
        changes = []
        lists.onChange = { [unowned self] in self.changes.append($0) }
    }

    var state: SiteListsState { lists.state }

    func deviceId() throws -> String {
        try identity.ensureCreated().id
    }

    /// Todo aparelho passa a estar ativo, com estas listas, até `expiresAt`.
    func activateAll(_ playlists: [FakeSite.List] = [], expiresAt: String = "2027-10-02T22:40:23Z", partner: Bool = false) async {
        await site.setSetup { device in
            device.active = true
            device.expiresAt = expiresAt
            device.playlists = playlists
            device.partner = partner
        }
    }
}

let serverList = FakeSite.List(id: 7, name: "Casa", url: "http://servidor.exemplo:8080")
let linkList = FakeSite.List(id: 9, name: "Sala", type: "m3u", url: "http://exemplo.test/lista.m3u")
