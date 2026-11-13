import Foundation

/// Aviso sobre o fim da ativação.
public enum ValidityWarning: Equatable, Sendable {
    /// Vence em menos de 1 mês.
    case month
    /// Vence em menos de 7 dias.
    case week
    /// Vence em menos de 24 horas.
    case day
    /// Já venceu.
    case expired
}

public enum Validity {
    private static let day: TimeInterval = 24 * 60 * 60

    /// Qual aviso mostrar agora, ou `nil` se não há aviso.
    public static func warning(_ state: SiteListsState, now: Date) -> ValidityWarning? {
        guard let expiresAt = state.expiresAt else { return nil }
        switch state.status {
        case .inactive:
            return .expired
        case .active:
            // Ativação de parceria: o servidor a renova sozinho; a tela não avisa de vencimento.
            if state.sponsored { return nil }
            let left = expiresAt.timeIntervalSince(now)
            if left <= day { return .day }
            if left <= 7 * day { return .week }
            if left <= 30 * day { return .month }
            return nil
        case .unknown, .blocked:
            return nil
        }
    }

    /// A data do fim da ativação ("02/10/2027"), quando o aparelho está ativo e o servidor informou.
    public static func activeUntil(_ state: SiteListsState, pattern: String, timeZone: TimeZone = .current) -> String? {
        guard state.status == .active, let expiresAt = state.expiresAt else { return nil }
        return ClockFormatter.dateText(expiresAt, pattern: pattern, timeZone: timeZone)
    }
}
