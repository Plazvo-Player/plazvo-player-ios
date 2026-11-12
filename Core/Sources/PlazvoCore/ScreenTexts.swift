import Foundation

/// Um texto do app pelo nome dele nos arquivos de textos, com o que entra nos espaços (`%1$@`).
public struct TextRef: Equatable, Sendable {
    public let key: String
    public let args: [String]

    public init(_ key: String, _ args: [String] = []) {
        self.key = key
        self.args = args
    }
}

/// Qual texto cada situação mostra na tela (as mesmas escolhas do app Android).
public enum ScreenTexts {
    /// Frase sobre a situação do aparelho, ou `nil` quando não há o que dizer.
    public static func status(_ site: SiteListsState) -> TextRef? {
        switch site.status {
        case .active: return site.playlists.isEmpty ? TextRef("playlists_empty") : nil
        case .inactive: return TextRef("playlists_inactive")
        case .blocked: return TextRef("playlists_blocked")
        case .unknown: return site.syncing ? TextRef("playlists_loading") : nil
        }
    }

    /// Aviso sobre a última consulta ao servidor que não deu certo, ou `nil`.
    public static func problem(_ site: SiteListsState) -> TextRef? {
        switch site.problem {
        case nil: return nil
        case .offline: return TextRef(site.status == .active ? "playlists_offline_saved" : "playlists_offline")
        case .refused: return TextRef("playlists_register_refused")
        case .tooManyAttempts: return TextRef("playlists_too_many")
        case .rejected: return TextRef("playlists_rejected", [String(site.problemStatus ?? 0)])
        }
    }

    /// "Ativo até 02/10/2027", quando o aparelho está ativo e o servidor informou a data.
    /// `datePattern` é a ordem de dia, mês e ano do idioma (texto `playlists_date_pattern`).
    public static func activeUntil(_ site: SiteListsState, datePattern: String, timeZone: TimeZone = .current) -> TextRef? {
        guard let date = Validity.activeUntil(site, pattern: datePattern, timeZone: timeZone) else { return nil }
        return TextRef("playlists_active_until", [date])
    }

    /// O aviso em destaque sobre o fim da ativação.
    public static func validityWarning(_ warning: ValidityWarning) -> TextRef {
        switch warning {
        case .month: return TextRef("home_expires_month")
        case .week: return TextRef("home_expires_week")
        case .day: return TextRef("home_expires_day")
        case .expired: return TextRef("home_expired")
        }
    }

    /// "Aparelho ativado por 30 dias." (ou só "Aparelho ativado." se o servidor não disse por quanto tempo).
    public static func activated(days: Int?) -> TextRef {
        guard let days else { return TextRef("code_activated") }
        return TextRef(days == 1 ? "code_activated_days.one" : "code_activated_days.other", [String(days)])
    }

    /// O aviso de um código que não ativou o aparelho, ou `nil` se ele ativou.
    public static func codeProblem(_ result: CodeResult) -> TextRef? {
        guard case .failed(let problem, let status) = result else { return nil }
        switch problem {
        case .invalid: return TextRef("code_invalid")
        case .unavailable: return TextRef("code_unavailable")
        case .used: return TextRef("code_used")
        case .alreadyActive: return TextRef("code_already_active")
        case .managed: return TextRef("code_managed")
        case .noCredits: return TextRef("code_no_credits")
        case .tooManyAttempts: return TextRef("code_too_many")
        case .offline: return TextRef("code_offline")
        case .refused: return TextRef("playlists_register_refused")
        case .rejected: return TextRef("playlists_rejected", [String(status ?? 0)])
        }
    }

    /// O que a caixa diz depois do pedido de sair do painel.
    public static func unlinkResult(_ result: UnlinkResult) -> TextRef {
        switch result {
        case .unlinked: return TextRef("unlink_done")
        case .notLinked: return TextRef("unlink_was_not_linked")
        case .failed(let problem, let status):
            switch problem {
            case .offline: return TextRef("code_offline")
            case .unavailable: return TextRef("unlink_unavailable")
            case .tooManyAttempts: return TextRef("code_too_many")
            case .refused: return TextRef("playlists_register_refused")
            case .rejected: return TextRef("playlists_rejected", [String(status ?? 0)])
            }
        }
    }

    /// Põe `args` nos espaços de `pattern`: `%1$@` e `%1$d` (numerados) ou `%@` e `%d` (na ordem).
    /// `%%` vira `%`. Espaço sem valor (ou marca que não é uma destas) fica como está.
    public static func fill(_ pattern: String, _ args: [String]) -> String {
        let characters = Array(pattern)
        var result = ""
        var nextInOrder = 0
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "%", index + 1 < characters.count else {
                result.append(character)
                index += 1
                continue
            }
            if characters[index + 1] == "%" {
                result.append("%")
                index += 2
                continue
            }
            // Depois do "%": um número e "$" (opcionais) e a letra do tipo.
            var cursor = index + 1
            var digits = ""
            while cursor < characters.count, characters[cursor].isASCII, characters[cursor].isNumber {
                digits.append(characters[cursor])
                cursor += 1
            }
            var position: Int?
            if !digits.isEmpty {
                guard cursor < characters.count, characters[cursor] == "$", let number = Int(digits), number >= 1 else {
                    result.append(character)
                    index += 1
                    continue
                }
                position = number - 1
                cursor += 1
            }
            guard cursor < characters.count, characters[cursor] == "@" || characters[cursor] == "d" else {
                result.append(character)
                index += 1
                continue
            }
            let wanted = position ?? nextInOrder
            if position == nil { nextInOrder += 1 }
            if wanted < args.count {
                result.append(args[wanted])
            } else {
                result.append(String(characters[index...cursor]))
            }
            index = cursor + 1
        }
        return result
    }
}
