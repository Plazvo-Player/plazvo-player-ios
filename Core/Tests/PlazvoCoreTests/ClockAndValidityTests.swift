import Foundation
import Testing
@testable import PlazvoCore

@Suite("Relógio e validade")
struct ClockAndValidityTests {
    let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!

    @Test("a hora sai igual em todos os idiomas")
    func time() {
        let afternoon = parseServerTime("2026-10-02T17:35:00Z")!
        #expect(ClockFormatter.timeText(afternoon, format: .h12, timeZone: saoPaulo) == "02:35 PM")
        #expect(ClockFormatter.timeText(afternoon, format: .h24, timeZone: saoPaulo) == "14:35")
        let midnight = parseServerTime("2026-10-02T03:05:00Z")!
        #expect(ClockFormatter.timeText(midnight, format: .h12, timeZone: saoPaulo) == "12:05 AM")
        #expect(ClockFormatter.timeText(midnight, format: .h24, timeZone: saoPaulo) == "00:05")
    }

    @Test("a data sai por extenso, no idioma do app, com maiúsculas")
    func date() {
        let now = parseServerTime("2026-10-02T17:35:00Z")!
        let portuguese = "%1$@, %2$@ de %3$@ de %4$@"
        #expect(ClockFormatter.clockText(now: now, languageTag: "pt-BR", datePattern: portuguese, timeZone: saoPaulo)
            == ClockText(time: "02:35 PM", date: "Sexta-feira, 02 de Outubro de 2026"))
        #expect(ClockFormatter.clockText(now: now, languageTag: "pt-PT", datePattern: portuguese, timeZone: saoPaulo).date
            == "Sexta-feira, 02 de Outubro de 2026")
        #expect(ClockFormatter.clockText(now: now, languageTag: "es", datePattern: portuguese, timeZone: saoPaulo).date
            == "Viernes, 02 de Octubre de 2026")
        #expect(ClockFormatter.clockText(now: now, languageTag: "en-US", datePattern: "%1$@, %3$@ %2$@, %4$@", timeZone: saoPaulo).date
            == "Friday, October 02, 2026")
    }

    @Test("a data do fim da ativação sai no fuso do aparelho")
    func activeUntil() {
        let state = SiteListsState(status: .active, expiresAt: parseServerTime("2027-11-13T02:59:59Z"))
        #expect(Validity.activeUntil(state, pattern: "dd/MM/yyyy", timeZone: saoPaulo) == "12/11/2027")
        #expect(Validity.activeUntil(state, pattern: "MM/dd/yyyy", timeZone: saoPaulo) == "11/12/2027")
        #expect(Validity.activeUntil(SiteListsState(status: .inactive, expiresAt: state.expiresAt), pattern: "dd/MM/yyyy") == nil)
        #expect(Validity.activeUntil(SiteListsState(status: .active), pattern: "dd/MM/yyyy") == nil)
    }

    @Test("avisos de vencimento: 1 mês, 7 dias, 24 horas e vencido")
    func warnings() {
        let now = parseServerTime("2026-10-05T19:00:00Z")!
        func active(_ expires: String) -> SiteListsState {
            SiteListsState(status: .active, expiresAt: parseServerTime(expires))
        }
        #expect(Validity.warning(active("2027-10-05T19:00:00Z"), now: now) == nil)
        #expect(Validity.warning(active("2026-11-04T19:00:01Z"), now: now) == nil)
        #expect(Validity.warning(active("2026-11-04T19:00:00Z"), now: now) == .month)
        #expect(Validity.warning(active("2026-10-12T19:00:01Z"), now: now) == .month)
        #expect(Validity.warning(active("2026-10-12T19:00:00Z"), now: now) == .week)
        #expect(Validity.warning(active("2026-10-06T19:00:01Z"), now: now) == .week)
        #expect(Validity.warning(active("2026-10-06T19:00:00Z"), now: now) == .day)
        #expect(Validity.warning(SiteListsState(status: .inactive, expiresAt: parseServerTime("2026-10-01T00:00:00Z")), now: now) == .expired)
        #expect(Validity.warning(SiteListsState(status: .inactive), now: now) == nil)
        #expect(Validity.warning(SiteListsState(status: .active), now: now) == nil)
        #expect(Validity.warning(SiteListsState(status: .blocked, expiresAt: now), now: now) == nil)
    }
}
