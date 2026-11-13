import Foundation
import Testing
@testable import PlazvoCore

/// Os mesmos casos do app Android (RecentMediaTest e RecentMediaStoreTest).
@Suite("Vídeos recentes: onde cada um parou")
struct RecentMediaTests {
    private func item(positionMs: Int64, durationMs: Int64) -> RecentMedia {
        RecentMedia(uri: "file:///videos/1.mp4", title: "Vídeo", kind: .file, positionMs: positionMs, durationMs: durationMs)
    }

    @Test("continua de onde parou")
    func resumes() {
        #expect(item(positionMs: 60_000, durationMs: 600_000).resumePositionMs == 60_000)
    }

    @Test("mal começou, volta ao início")
    func barelyStarted() {
        #expect(item(positionMs: 4_000, durationMs: 600_000).resumePositionMs == 0)
    }

    @Test("nos últimos segundos, volta ao início")
    func nearTheEnd() {
        // Vídeo curto: os últimos 5 segundos contam como terminado.
        #expect(item(positionMs: 18_000, durationMs: 21_000).resumePositionMs == 0)
        #expect(item(positionMs: 12_000, durationMs: 21_000).resumePositionMs == 12_000)
        // Vídeo longo: os últimos 2% (créditos) contam como terminado.
        #expect(item(positionMs: 7_100_000, durationMs: 7_200_000).resumePositionMs == 0)
        #expect(item(positionMs: 7_000_000, durationMs: 7_200_000).resumePositionMs == 7_000_000)
    }

    @Test("sem duração conhecida, continua do ponto guardado")
    func unknownDuration() {
        #expect(item(positionMs: 30_000, durationMs: 0).resumePositionMs == 30_000)
    }

    @Test("progresso vai de 0 a 1 e some sem duração")
    func progress() {
        #expect(item(positionMs: 150_000, durationMs: 600_000).progress == 0.25)
        #expect(item(positionMs: 700_000, durationMs: 600_000).progress == 1)
        #expect(item(positionMs: 150_000, durationMs: 0).progress == nil)
    }

    @Test("tempo no formato do reprodutor: com horas ou sem, arredondado")
    func duration() {
        #expect(formatDuration(0) == "0:00")
        #expect(formatDuration(-5) == "0:00")
        #expect(formatDuration(499) == "0:00")
        #expect(formatDuration(500) == "0:01")
        #expect(formatDuration(9_000) == "0:09")
        #expect(formatDuration(21_630) == "0:22")
        #expect(formatDuration(123_000) == "2:03")
        #expect(formatDuration(754_000) == "12:34")
        #expect(formatDuration(3_723_000) == "1:02:03")
        #expect(formatDuration(36_000_000) == "10:00:00")
        // O maior número que existe não derruba a conta.
        #expect(formatDuration(Int64.max) == "2562047788015:12:56")
        #expect(formatDuration(Int64.min) == "0:00")
    }

    @Test("o ponto está no fim do vídeo nos últimos 5 segundos ou nos últimos 2%, o que for maior")
    func nearEndRule() {
        #expect(RecentMedia.isNearEnd(positionMs: 15_001, durationMs: 20_000))
        #expect(!RecentMedia.isNearEnd(positionMs: 15_000, durationMs: 20_000))
        #expect(RecentMedia.isNearEnd(positionMs: 7_056_001, durationMs: 7_200_000))
        #expect(!RecentMedia.isNearEnd(positionMs: 7_056_000, durationMs: 7_200_000))
        // Sem duração conhecida, nunca.
        #expect(!RecentMedia.isNearEnd(positionMs: 30_000, durationMs: 0))
        #expect(!RecentMedia.isNearEnd(positionMs: 0, durationMs: -1))
    }

    @Test("o pedido e o vídeo recente nunca mostram o endereço num registro")
    func redacted() {
        let secret = "http://usuario:senha@exemplo.com/a.mp4"
        let request = PlaybackRequest(kind: .link, uri: secret, title: "a.mp4", access: Data("marcador".utf8))
        let recent = RecentMedia(uri: secret, title: "a.mp4", kind: .link, access: Data("marcador".utf8))
        var dumped = ""
        dump(request, to: &dumped)
        dump(recent, to: &dumped)
        dump([recent], to: &dumped)
        for text in ["\(request)", String(reflecting: request), "\(recent)", String(reflecting: recent), "\([recent])", "\(Optional(request) as Any)", dumped] {
            #expect(!text.contains("senha"))
            #expect(!text.contains("exemplo.com"))
            #expect(!text.contains("marcador"))
        }
        #expect("\(request)" == "PlaybackRequest(kind: link)")
        #expect("\(recent)" == "RecentMedia(kind: link)")
    }

    @Test("o vídeo recente reabre com o mesmo pedido")
    func request() {
        let access = Data([1, 2, 3])
        let recent = RecentMedia(uri: "file:///videos/1.mp4", title: "Férias.mp4", kind: .file, positionMs: 9, durationMs: 10, access: access)
        #expect(recent.request == PlaybackRequest(kind: .file, uri: "file:///videos/1.mp4", title: "Férias.mp4", access: access))
    }
}

@MainActor
@Suite("Vídeos recentes: a lista guardada no aparelho")
struct RecentMediaStoreTests {
    let clock = TestClock("2026-11-12T17:30:00Z")
    let copy = InMemoryCopyStore()

    /// Abre a lista guardada, como o app ao iniciar.
    private func open() -> RecentMediaStore {
        let clock = self.clock
        return RecentMediaStore(storage: copy, now: { clock.now })
    }

    private func link(_ name: String) -> PlaybackRequest {
        PlaybackRequest(kind: .link, uri: "http://exemplo.com/\(name)", title: name)
    }

    private func file(_ number: Int, access: Data? = nil) -> PlaybackRequest {
        PlaybackRequest(kind: .file, uri: "file:///videos/\(number).mp4", title: "Vídeo \(number)", access: access)
    }

    @Test("começa vazia")
    func startsEmpty() {
        let store = open()
        #expect(store.items.isEmpty)
        #expect(store.find("http://exemplo.com/a.mp4") == nil)
        #expect(copy.data == nil)
    }

    @Test("o vídeo aberto por último fica no topo")
    func lastOnTop() {
        let store = open()
        clock.set("2026-11-12T17:30:01Z")
        store.markOpened(link("a.mp4"))
        clock.set("2026-11-12T17:30:02Z")
        store.markOpened(file(2))

        #expect(store.items.map(\.uri) == ["file:///videos/2.mp4", "http://exemplo.com/a.mp4"])
        #expect(store.items[0] == RecentMedia(
            uri: "file:///videos/2.mp4", title: "Vídeo 2", kind: .file,
            lastPlayedAt: Int64(parseServerTime("2026-11-12T17:30:02Z")!.timeIntervalSince1970 * 1000)
        ))
    }

    @Test("reabrir sobe para o topo sem repetir e mantém o ponto")
    func reopening() {
        let store = open()
        store.markOpened(file(1))
        store.markOpened(file(2))
        store.savePosition("file:///videos/1.mp4", positionMs: 90_000, durationMs: 600_000)
        clock.set("2026-11-12T18:00:00Z")

        store.markOpened(file(1))

        #expect(store.items.map(\.uri) == ["file:///videos/1.mp4", "file:///videos/2.mp4"])
        #expect(store.items[0].positionMs == 90_000)
        #expect(store.items[0].durationMs == 600_000)
        #expect(store.items[0].lastPlayedAt == Int64(parseServerTime("2026-11-12T18:00:00Z")!.timeIntervalSince1970 * 1000))
    }

    @Test("guarda o ponto e continua de lá")
    func savesPosition() {
        let store = open()
        store.markOpened(file(1))
        store.savePosition("file:///videos/1.mp4", positionMs: 125_000, durationMs: 600_000)
        #expect(store.find("file:///videos/1.mp4")?.resumePositionMs == 125_000)

        // Valores negativos (duração desconhecida no motor) viram zero.
        store.savePosition("file:///videos/1.mp4", positionMs: -1, durationMs: -1)
        #expect(store.find("file:///videos/1.mp4")?.positionMs == 0)
        #expect(store.find("file:///videos/1.mp4")?.durationMs == 0)
    }

    @Test("ponto de vídeo fora da lista é ignorado")
    func unknownVideo() {
        let store = open()
        store.savePosition("file:///videos/9.mp4", positionMs: 125_000, durationMs: 600_000)
        #expect(store.items.isEmpty)
        #expect(copy.data == nil)
    }

    @Test("a lista continua ao reabrir o app, com o marcador de acesso do arquivo")
    func persists() {
        let access = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let first = open()
        first.markOpened(link("a.mp4"))
        first.savePosition("http://exemplo.com/a.mp4", positionMs: 30_000, durationMs: 120_000)
        first.markOpened(file(1, access: access))

        let reopened = open()

        let at = Int64(clock.now.timeIntervalSince1970 * 1000)
        #expect(reopened.items == [
            RecentMedia(uri: "file:///videos/1.mp4", title: "Vídeo 1", kind: .file, lastPlayedAt: at, access: access),
            RecentMedia(uri: "http://exemplo.com/a.mp4", title: "a.mp4", kind: .link, positionMs: 30_000, durationMs: 120_000, lastPlayedAt: at),
        ])
    }

    @Test("reabrir um arquivo sem marcador novo mantém o marcador guardado")
    func keepsAccess() {
        let access = Data([7, 7, 7])
        let store = open()
        store.markOpened(file(1, access: access))
        store.markOpened(file(1))
        #expect(store.items.count == 1)
        #expect(store.items[0].access == access)

        let newer = Data([8, 8])
        store.markOpened(file(1, access: newer))
        #expect(store.items[0].access == newer)
    }

    @Test("guarda no máximo 20: o mais antigo sai")
    func atMostTwenty() {
        let store = open()
        for number in 0...20 {
            store.markOpened(file(number))
        }
        #expect(store.items.count == 20)
        #expect(store.items.first?.uri == "file:///videos/20.mp4")
        #expect(store.items.last?.uri == "file:///videos/1.mp4")
        #expect(open().items.count == 20)
    }

    @Test("limpar esvazia a lista e apaga o que estava guardado")
    func clears() {
        let store = open()
        store.markOpened(file(1))
        store.markOpened(link("a.mp4"))
        #expect(copy.data != nil)

        store.clear()

        #expect(store.items.isEmpty)
        #expect(copy.data == nil)
        #expect(open().items.isEmpty)
    }

    @Test("dados estragados viram lista vazia em vez de travar o app")
    func corrupted() {
        copy.data = Data("[{\"uri\": 1".utf8)
        let store = open()
        #expect(store.items.isEmpty)
        // E volta a funcionar normalmente.
        store.markOpened(file(1))
        #expect(store.items.count == 1)
        #expect(open().items.count == 1)
    }

    @Test("um item que não dá para ler fica de fora; os outros continuam")
    func oneBadItem() {
        copy.data = Data("""
        [
          {"uri": "http://exemplo.com/a.mp4", "title": "a.mp4", "kind": "link", "position": 5000, "duration": 60000, "lastPlayed": 1},
          {"uri": "http://exemplo.com/b.mp4", "title": "b.mp4", "kind": "fita"},
          {"title": "sem endereço", "kind": "file"},
          "texto solto",
          {"uri": "file:///videos/1.mp4", "title": "Vídeo 1", "kind": "file", "position": 0, "duration": 0, "lastPlayed": 2}
        ]
        """.utf8)
        let store = open()
        #expect(store.items.map(\.uri) == ["http://exemplo.com/a.mp4", "file:///videos/1.mp4"])
        #expect(store.items[0].positionMs == 5_000)
    }

    @Test("o que o app nunca teria gravado fica de fora: demonstração, link que não vale, arquivo sem endereço de arquivo")
    func notWrittenByTheApp() {
        copy.data = Data("""
        [
          {"uri": "", "title": "Demonstração", "kind": "demo", "position": 0, "duration": 0, "lastPlayed": 9},
          {"uri": "file:///etc/hosts", "title": "hosts", "kind": "link", "position": 0, "duration": 0, "lastPlayed": 8},
          {"uri": "smb://exemplo.test/pasta/a.mkv", "title": "a.mkv", "kind": "link", "position": 0, "duration": 0, "lastPlayed": 7},
          {"uri": "exemplo.com/sem-http.mp4", "title": "sem-http.mp4", "kind": "link", "position": 0, "duration": 0, "lastPlayed": 6},
          {"uri": "http://exemplo.com/com espaço.mp4", "title": "com espaço.mp4", "kind": "link", "position": 0, "duration": 0, "lastPlayed": 5},
          {"uri": "http://exemplo.com/a.mp4", "title": "a.mp4", "kind": "file", "position": 0, "duration": 0, "lastPlayed": 4},
          {"uri": "http://usuario:senha@exemplo.com:8080/a%20b.mp4?x=1", "title": "a b.mp4", "kind": "link", "position": 0, "duration": 0, "lastPlayed": 3},
          {"uri": "file:///videos/1.mp4", "title": "Vídeo 1", "kind": "file", "position": 0, "duration": 0, "lastPlayed": 2}
        ]
        """.utf8)
        let store = open()
        #expect(store.items.map(\.uri) == ["http://usuario:senha@exemplo.com:8080/a%20b.mp4?x=1", "file:///videos/1.mp4"])
    }

    @Test("números fora da faixa são acertados ao ler, e a tela não cai por causa deles")
    func outOfRangeNumbers() {
        copy.data = Data("""
        [
          {"uri": "file:///videos/1.mp4", "title": "Vídeo 1", "kind": "file", "position": 9223372036854775807, "duration": 9223372036854775807, "lastPlayed": 9223372036854775807},
          {"uri": "file:///videos/2.mp4", "title": "Vídeo 2", "kind": "file", "position": -9223372036854775808, "duration": -5, "lastPlayed": -1},
          {"uri": "file:///videos/3.mp4", "title": "Vídeo 3", "kind": "file", "position": 1e30, "duration": 60000, "lastPlayed": 1}
        ]
        """.utf8)
        let store = open()
        #expect(store.items.map(\.uri) == ["file:///videos/1.mp4", "file:///videos/2.mp4"])
        #expect(store.items[0].positionMs == RecentMedia.maxTimeMs)
        #expect(store.items[0].durationMs == RecentMedia.maxTimeMs)
        #expect(store.items[1].positionMs == 0)
        #expect(store.items[1].durationMs == 0)
        // As contas que a tela e o reprodutor fazem com esses números.
        for item in store.items {
            _ = item.progress
            _ = item.resumePositionMs
            _ = ScreenTexts.recentProgress(item, pattern: "%1$@ de %2$@")
            _ = formatDuration(item.positionMs + 10_000)
        }
        #expect(ScreenTexts.recentProgress(store.items[0], pattern: "%1$@ de %2$@") == "596:31:24 de 596:31:24")
        // Gravar um ponto fora da faixa também é acertado.
        store.savePosition("file:///videos/2.mp4", positionMs: Int64.max, durationMs: Int64.max)
        #expect(store.items[1].positionMs == RecentMedia.maxTimeMs)
        #expect(store.items[1].durationMs == RecentMedia.maxTimeMs)
    }

    @Test("o mesmo vídeo repetido no que estava guardado aparece uma vez só (vale o primeiro)")
    func duplicates() {
        copy.data = Data("""
        [
          {"uri": "file:///videos/1.mp4", "title": "Primeiro", "kind": "file", "position": 5000, "duration": 60000, "lastPlayed": 3},
          {"uri": "http://exemplo.com/a.mp4", "title": "a.mp4", "kind": "link", "position": 0, "duration": 0, "lastPlayed": 2},
          {"uri": "file:///videos/1.mp4", "title": "Repetido", "kind": "file", "position": 9000, "duration": 60000, "lastPlayed": 1}
        ]
        """.utf8)
        let store = open()
        #expect(store.items.map(\.title) == ["Primeiro", "a.mp4"])
        #expect(store.items[0].positionMs == 5_000)
    }

    @Test("cada mudança da lista é avisada uma vez")
    func notifies() {
        let store = open()
        var changes: [[String]] = []
        store.onChange = { changes.append($0.map(\.title)) }

        store.markOpened(link("a.mp4"))
        store.savePosition("http://exemplo.com/a.mp4", positionMs: 10_000, durationMs: 60_000)
        // O mesmo ponto de novo não muda nada.
        store.savePosition("http://exemplo.com/a.mp4", positionMs: 10_000, durationMs: 60_000)
        store.clear()
        store.clear()

        #expect(changes == [["a.mp4"], ["a.mp4"], []])
    }

    @Test("o que fica guardado é só o da lista: nome, endereço, tipo, ponto e marcador")
    func storedFields() throws {
        let store = open()
        store.markOpened(file(1, access: Data([1, 2])))
        let data = try #require(copy.data)
        let list = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(list.count == 1)
        #expect(Set(list[0].keys) == ["uri", "title", "kind", "position", "duration", "lastPlayed", "access"])
        #expect(list[0]["kind"] as? String == "file")
    }
}
