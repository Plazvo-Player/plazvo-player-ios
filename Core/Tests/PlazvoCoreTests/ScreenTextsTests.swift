import Foundation
import Testing
@testable import PlazvoCore

/// A pasta do repositório (os testes ficam em Core/Tests/PlazvoCoreTests).
private let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private let languages = ["pt-BR", "pt-PT", "en", "es"]

/// Lê os textos de um idioma do app (App/Resources/<idioma>.lproj/Localizable.strings).
private func appTexts(_ language: String) throws -> [String: String] {
    let url = repository.appendingPathComponent("App/Resources/\(language).lproj/Localizable.strings")
    var texts: [String: String] = [:]
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        guard line.hasPrefix("\""), line.hasSuffix("\";"), let middle = line.range(of: "\" = \"") else { continue }
        let key = String(line[line.index(after: line.startIndex)..<middle.lowerBound])
        let value = String(line[middle.upperBound..<line.index(line.endIndex, offsetBy: -2)])
        texts[key] = value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
    return texts
}

/// Os nomes de texto que as telas pedem direto, com `t("nome")`, nos arquivos da pasta App.
private func keysUsedByScreens() throws -> Set<String> {
    let folder = repository.appendingPathComponent("App")
    let pattern = try NSRegularExpression(pattern: "\\bt\\(\"([A-Za-z0-9_.]+)\"")
    var keys: Set<String> = []
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: file, encoding: .utf8)
        let whole = NSRange(source.startIndex..., in: source)
        for match in pattern.matches(in: source, range: whole) {
            if let range = Range(match.range(at: 1), in: source) { keys.insert(String(source[range])) }
        }
    }
    return keys
}

@Suite("Textos das telas")
struct ScreenTextsTests {
    let saoPaulo = TimeZone(identifier: "America/Sao_Paulo")!

    // MARK: - Qual texto cada situação mostra

    @Test("situação do aparelho: não ativo, bloqueado, ativo sem listas, buscando")
    func status() {
        #expect(ScreenTexts.status(SiteListsState(status: .inactive)) == TextRef("playlists_inactive"))
        #expect(ScreenTexts.status(SiteListsState(status: .blocked)) == TextRef("playlists_blocked"))
        #expect(ScreenTexts.status(SiteListsState(status: .active)) == TextRef("playlists_empty"))
        let list = SitePlaylist(id: 7, name: "Casa", kind: .server, url: "http://servidor.exemplo:8080")
        #expect(ScreenTexts.status(SiteListsState(status: .active, playlists: [list])) == nil)
        #expect(ScreenTexts.status(SiteListsState(status: .unknown, syncing: true)) == TextRef("playlists_loading"))
        #expect(ScreenTexts.status(SiteListsState(status: .unknown)) == nil)
    }

    @Test("aviso da última consulta: sem conexão (com e sem cópia guardada), recusa, tentativas demais, erro")
    func problem() {
        #expect(ScreenTexts.problem(SiteListsState(status: .inactive)) == nil)
        #expect(ScreenTexts.problem(SiteListsState(status: .unknown, problem: .offline)) == TextRef("playlists_offline"))
        #expect(ScreenTexts.problem(SiteListsState(status: .active, problem: .offline)) == TextRef("playlists_offline_saved"))
        #expect(ScreenTexts.problem(SiteListsState(problem: .refused)) == TextRef("playlists_register_refused"))
        #expect(ScreenTexts.problem(SiteListsState(problem: .tooManyAttempts)) == TextRef("playlists_too_many"))
        #expect(ScreenTexts.problem(SiteListsState(problem: .rejected, problemStatus: 418)) == TextRef("playlists_rejected", ["418"]))
        #expect(ScreenTexts.problem(SiteListsState(problem: .rejected)) == TextRef("playlists_rejected", ["0"]))
    }

    @Test("\"Ativo até\": só com o aparelho ativo e a data informada, na ordem do idioma")
    func activeUntil() {
        let active = SiteListsState(status: .active, expiresAt: parseServerTime("2027-11-13T02:59:59Z"))
        #expect(ScreenTexts.activeUntil(active, datePattern: "dd/MM/yyyy", timeZone: saoPaulo) == TextRef("playlists_active_until", ["12/11/2027"]))
        #expect(ScreenTexts.activeUntil(active, datePattern: "MM/dd/yyyy", timeZone: saoPaulo) == TextRef("playlists_active_until", ["11/12/2027"]))
        #expect(ScreenTexts.activeUntil(SiteListsState(status: .active), datePattern: "dd/MM/yyyy") == nil)
        #expect(ScreenTexts.activeUntil(SiteListsState(status: .inactive, expiresAt: active.expiresAt), datePattern: "dd/MM/yyyy") == nil)
    }

    @Test("código de ativação: por quantos dias ativou e o aviso de cada recusa")
    func code() {
        #expect(ScreenTexts.activated(days: nil) == TextRef("code_activated"))
        #expect(ScreenTexts.activated(days: 1) == TextRef("code_activated_days.one", ["1"]))
        #expect(ScreenTexts.activated(days: 365) == TextRef("code_activated_days.other", ["365"]))

        #expect(ScreenTexts.codeProblem(.activated(days: 30)) == nil)
        let expected: [(CodeProblem, String)] = [
            (.invalid, "code_invalid"), (.unavailable, "code_unavailable"), (.used, "code_used"),
            (.alreadyActive, "code_already_active"), (.managed, "code_managed"), (.noCredits, "code_no_credits"),
            (.tooManyAttempts, "code_too_many"), (.offline, "code_offline"), (.refused, "playlists_register_refused"),
        ]
        for (problem, key) in expected {
            #expect(ScreenTexts.codeProblem(.failed(problem, status: 409)) == TextRef(key))
        }
        #expect(ScreenTexts.codeProblem(.failed(.rejected, status: 400)) == TextRef("playlists_rejected", ["400"]))
        #expect(ScreenTexts.codeProblem(.failed(.rejected, status: nil)) == TextRef("playlists_rejected", ["0"]))
    }

    @Test("desconectar do painel: o que a caixa diz depois do pedido")
    func unlink() {
        #expect(ScreenTexts.unlinkResult(.unlinked) == TextRef("unlink_done"))
        #expect(ScreenTexts.unlinkResult(.notLinked) == TextRef("unlink_was_not_linked"))
        #expect(ScreenTexts.unlinkResult(.failed(.offline, status: nil)) == TextRef("code_offline"))
        #expect(ScreenTexts.unlinkResult(.failed(.unavailable, status: 404)) == TextRef("unlink_unavailable"))
        #expect(ScreenTexts.unlinkResult(.failed(.tooManyAttempts, status: 429)) == TextRef("code_too_many"))
        #expect(ScreenTexts.unlinkResult(.failed(.refused, status: 401)) == TextRef("playlists_register_refused"))
        #expect(ScreenTexts.unlinkResult(.failed(.rejected, status: 500)) == TextRef("playlists_rejected", ["500"]))
    }

    @Test("avisos de vencimento")
    func warnings() {
        #expect(ScreenTexts.validityWarning(.month) == TextRef("home_expires_month"))
        #expect(ScreenTexts.validityWarning(.week) == TextRef("home_expires_week"))
        #expect(ScreenTexts.validityWarning(.day) == TextRef("home_expires_day"))
        #expect(ScreenTexts.validityWarning(.expired) == TextRef("home_expired"))
    }

    // MARK: - Espaços dos textos

    @Test("os espaços do texto recebem os valores, numerados ou na ordem")
    func fill() {
        #expect(ScreenTexts.fill("Ativo até %1$@", ["12/11/2027"]) == "Ativo até 12/11/2027")
        #expect(ScreenTexts.fill("%1$@, %3$@ %2$@, %4$@", ["Friday", "02", "October", "2026"]) == "Friday, October 02, 2026")
        #expect(ScreenTexts.fill("Aparelho ativado por %1$d dias.", ["365"]) == "Aparelho ativado por 365 dias.")
        #expect(ScreenTexts.fill("%@ e %@", ["um", "dois"]) == "um e dois")
        #expect(ScreenTexts.fill("%d de %d", ["1", "2"]) == "1 de 2")
        #expect(ScreenTexts.fill("100%% certo", []) == "100% certo")
        #expect(ScreenTexts.fill("sem espaços", ["sobra"]) == "sem espaços")
        // Espaço sem valor, ou marca que não é um espaço, fica como está.
        #expect(ScreenTexts.fill("erro %1$@ e %2$@", ["404"]) == "erro 404 e %2$@")
        #expect(ScreenTexts.fill("50% de %1$", ["x"]) == "50% de %1$")
        #expect(ScreenTexts.fill("fim %", []) == "fim %")
        // O valor entra como está, mesmo que pareça um espaço.
        #expect(ScreenTexts.fill("erro %1$@", ["%2$@"]) == "erro %2$@")
    }

    // MARK: - Arquivos de textos do app

    @Test("os quatro idiomas têm os mesmos textos, e nenhum está vazio")
    func sameKeysInEveryLanguage() throws {
        let portuguese = try appTexts("pt-BR")
        #expect(portuguese.count >= 68)
        for language in languages {
            let texts = try appTexts(language)
            #expect(Set(texts.keys) == Set(portuguese.keys), "idioma \(language)")
            #expect(!texts.values.contains(""), "idioma \(language)")
        }
    }

    @Test("todo texto que a lógica escolhe existe nos quatro idiomas")
    func everyChosenTextExists() throws {
        var refs: [TextRef] = [
            TextRef("playlists_inactive"), TextRef("playlists_blocked"), TextRef("playlists_empty"), TextRef("playlists_loading"),
            TextRef("playlists_active_until"), TextRef("new_key_failed"), TextRef("device_id_copied"), TextRef("device_key_copied"),
            ScreenTexts.activated(days: nil), ScreenTexts.activated(days: 1), ScreenTexts.activated(days: 2),
            ScreenTexts.unlinkResult(.unlinked), ScreenTexts.unlinkResult(.notLinked),
        ]
        for problem in [SyncProblem.offline, .refused, .tooManyAttempts, .rejected] {
            refs.append(ScreenTexts.problem(SiteListsState(status: .active, problem: problem))!)
            refs.append(ScreenTexts.problem(SiteListsState(status: .inactive, problem: problem))!)
        }
        for problem in [CodeProblem.invalid, .unavailable, .used, .alreadyActive, .managed, .noCredits, .tooManyAttempts, .offline, .refused, .rejected] {
            refs.append(ScreenTexts.codeProblem(.failed(problem, status: 400))!)
        }
        for problem in [UnlinkProblem.offline, .unavailable, .tooManyAttempts, .refused, .rejected] {
            refs.append(ScreenTexts.unlinkResult(.failed(problem, status: 400)))
        }
        for warning in [ValidityWarning.month, .week, .day, .expired] {
            refs.append(ScreenTexts.validityWarning(warning))
        }
        for language in languages {
            let texts = try appTexts(language)
            for ref in refs {
                #expect(texts[ref.key] != nil, "falta \(ref.key) em \(language)")
            }
        }
    }

    @Test("todo texto que as telas pedem existe nos quatro idiomas")
    func everyScreenTextExists() throws {
        let keys = try keysUsedByScreens()
        // As telas da 0.1 pedem bem mais que isto; se a busca não achar nada, o teste não vale.
        #expect(keys.count >= 20)
        for language in languages {
            let texts = try appTexts(language)
            for key in keys.sorted() {
                #expect(texts[key] != nil, "falta \(key) em \(language)")
            }
        }
    }

    @Test("as frases em português, com os valores no lugar")
    func portugueseSentences() throws {
        let texts = try appTexts("pt-BR")
        func sentence(_ ref: TextRef) -> String { ScreenTexts.fill(texts[ref.key] ?? "", ref.args) }
        #expect(sentence(TextRef("playlists_active_until", ["12/11/2027"])) == "Ativo até 12/11/2027")
        #expect(sentence(ScreenTexts.activated(days: 365)) == "Aparelho ativado por 365 dias.")
        #expect(sentence(ScreenTexts.activated(days: 1)) == "Aparelho ativado por 1 dia.")
        #expect(sentence(TextRef("playlists_rejected", ["418"])) == "O servidor não aceitou o pedido (erro 418).")
        #expect(sentence(TextRef("version_short", ["0.1.0"])) == "v0.1.0")
        #expect(sentence(TextRef("device_key_copied")) == "Chave copiada")
        #expect(sentence(TextRef("device_id_copied")) == "ID copiado")
        let pattern = try #require(texts["home_date"])
        let now = parseServerTime("2026-11-12T17:30:00Z")!
        #expect(ClockFormatter.clockText(now: now, languageTag: texts["language_tag"] ?? "", datePattern: pattern, timeZone: saoPaulo)
            == ClockText(time: "02:30 PM", date: "Quinta-feira, 12 de Novembro de 2026"))
    }
}

@Suite("Arranjo das telas e campo do código")
struct ScreenLayoutTests {
    @Test("tela inicial: celular em pé, tablet em pé e tela larga")
    func home() {
        #expect(ScreenLayout.home(width: 402, height: 874) == .compact)
        #expect(ScreenLayout.home(width: 320, height: 568) == .compact)
        #expect(ScreenLayout.home(width: 599, height: 900) == .compact)
        #expect(ScreenLayout.home(width: 600, height: 900) == .medium)
        #expect(ScreenLayout.home(width: 834, height: 1210) == .medium)
        #expect(ScreenLayout.home(width: 840, height: 1210) == .wide)
        #expect(ScreenLayout.home(width: 1210, height: 834) == .wide)
        // Celular deitado: largo a partir de 560 por 300.
        #expect(ScreenLayout.home(width: 874, height: 402) == .wide)
        #expect(ScreenLayout.home(width: 667, height: 375) == .wide)
        #expect(ScreenLayout.home(width: 568, height: 320) == .wide)
        #expect(ScreenLayout.home(width: 559, height: 320) == .compact)
        #expect(ScreenLayout.home(width: 667, height: 299) == .medium)
    }

    @Test("telas internas: largas a partir de 600 de largura, ou deitadas")
    func inner() {
        #expect(!ScreenLayout.isWide(width: 402, height: 874))
        #expect(ScreenLayout.isWide(width: 600, height: 900))
        #expect(ScreenLayout.isWide(width: 874, height: 402))
        #expect(!ScreenLayout.isWide(width: 559, height: 320))
    }

    @Test("barra do alto apertada: celular com menos de 400 de largura")
    func narrowHeader() {
        #expect(ScreenLayout.isNarrowHeader(width: 393))
        #expect(!ScreenLayout.isNarrowHeader(width: 400))
        #expect(!ScreenLayout.isNarrowHeader(width: 402))
    }

    @Test("campo do código: guarda só letras e números em maiúsculas, até 12")
    func codeInput() {
        #expect(acceptedActivationCodeInput("") == "")
        #expect(acceptedActivationCodeInput("abcd-efgh") == "ABCDEFGH")
        #expect(acceptedActivationCodeInput(" ABCD EFGH JKMN ") == "ABCDEFGHJKMN")
        #expect(acceptedActivationCodeInput("ABCD-EFGH-JKMN") == "ABCDEFGHJKMN")
        // Mais do que um código tem: o campo fica como estava.
        #expect(acceptedActivationCodeInput("ABCD-EFGH-JKMNX") == nil)
        // O campo mostra os traços sozinho; apagar a última letra de um grupo leva o traço junto.
        #expect(formattedActivationCode("ABCDE") == "ABCD-E")
        #expect(formattedActivationCode(acceptedActivationCodeInput("ABCD-") ?? "") == "ABCD")
    }
}
