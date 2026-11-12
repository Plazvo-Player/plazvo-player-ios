import Foundation

/// Hora e data já formatadas para mostrar na tela.
public struct ClockText: Equatable, Sendable {
    public let time: String
    public let date: String

    public init(time: String, date: String) {
        self.time = time
        self.date = date
    }
}

/// Como a hora aparece: em 12 horas com AM/PM ou em 24 horas.
public enum TimeFormat: Equatable, Sendable {
    case h12
    case h24
}

public enum ClockFormatter {
    /// A hora, igual em todos os idiomas: "02:35 PM" ou "14:35".
    public static func timeText(_ date: Date, format: TimeFormat = .h12, timeZone: TimeZone = .current) -> String {
        formatted(date, pattern: format == .h12 ? "hh:mm a" : "HH:mm", locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone)
    }

    /// A hora e a data por extenso, no idioma do app.
    ///
    /// A data é montada peça por peça: cada idioma diz a ordem delas em `datePattern`
    /// (`%1$@` dia da semana, `%2$@` dia, `%3$@` mês, `%4$@` ano), e o dia da semana e o mês saem
    /// com a primeira letra maiúscula ("Sexta-feira, 02 de Outubro de 2026").
    public static func clockText(
        now: Date,
        languageTag: String,
        datePattern: String,
        timeFormat: TimeFormat = .h12,
        timeZone: TimeZone = .current
    ) -> ClockText {
        let locale = Locale(identifier: languageTag)
        let posix = Locale(identifier: "en_US_POSIX")
        let pieces = [
            capitalized(formatted(now, pattern: "EEEE", locale: locale, timeZone: timeZone), locale),
            formatted(now, pattern: "dd", locale: posix, timeZone: timeZone),
            capitalized(formatted(now, pattern: "MMMM", locale: locale, timeZone: timeZone), locale),
            formatted(now, pattern: "yyyy", locale: posix, timeZone: timeZone),
        ]
        var date = datePattern
        for (index, piece) in pieces.enumerated() {
            date = date.replacingOccurrences(of: "%\(index + 1)$@", with: piece)
        }
        return ClockText(time: timeText(now, format: timeFormat, timeZone: timeZone), date: date)
    }

    /// Uma data só com algarismos comuns, na ordem do idioma: "05/10/2027" (`dd/MM/yyyy`).
    public static func dateText(_ date: Date, pattern: String, timeZone: TimeZone = .current) -> String {
        formatted(date, pattern: pattern, locale: Locale(identifier: "en_US_POSIX"), timeZone: timeZone)
    }

    private static func formatted(_ date: Date, pattern: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func capitalized(_ text: String, _ locale: Locale) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }
}
