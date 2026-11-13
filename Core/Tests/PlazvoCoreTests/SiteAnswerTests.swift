import Foundation
import Testing
@testable import PlazvoCore

@Suite("Leitura das respostas do servidor")
struct SiteAnswerTests {
    @Test("resposta completa das listas")
    func fullAnswer() throws {
        let text = """
        {"ok": true, "active": true, "expires_at": "2027-10-02T22:40:23Z", "server_time": "2026-10-05T19:00:00Z",
         "new_key_needed": false, "partner": true,
         "playlists": [
           {"id": 7, "name": "Casa", "type": "xtream", "url": " http://servidor.exemplo:8080 ", "username": "ana", "password": "segredo",
            "epg_url": "http://servidor.exemplo/guia.xml", "pin_protected": false},
           {"id": "9", "name": "Sala", "type": "m3u", "url": "http://exemplo.test/lista.m3u", "pin_protected": true,
            "pin_salt": "9f2c61d0a4b7e835", "pin_hash": "abc123"}
         ]}
        """
        let answer = try parsePlaylistsAnswer(text)
        #expect(answer.active)
        #expect(answer.expiresAt == parseServerTime("2027-10-02T22:40:23Z"))
        #expect(answer.serverTime == parseServerTime("2026-10-05T19:00:00Z"))
        #expect(answer.partner == true)
        #expect(answer.raw == text)
        #expect(answer.playlists == [
            SitePlaylist(id: 7, name: "Casa", kind: .server, url: "http://servidor.exemplo:8080", username: "ana", password: "segredo",
                         epgUrl: "http://servidor.exemplo/guia.xml"),
            SitePlaylist(id: 9, name: "Sala", kind: .link, url: "http://exemplo.test/lista.m3u", pinProtected: true,
                         pinSalt: "9f2c61d0a4b7e835", pinHash: "abc123"),
        ])
    }

    @Test("aparelho não ativo: sem data, sem listas, sem parceiro informado")
    func inactiveAnswer() throws {
        let answer = try parsePlaylistsAnswer(#"{"active": false, "expires_at": null, "playlists": []}"#)
        #expect(!answer.active)
        #expect(answer.expiresAt == nil)
        #expect(answer.serverTime == nil)
        #expect(answer.playlists.isEmpty)
        #expect(answer.partner == nil)
    }

    @Test("lista de tipo desconhecido, sem número ou sem endereço fica de fora")
    func skipsListsItCannotUse() throws {
        let text = """
        {"active": true, "playlists": [
          {"id": 1, "name": "outro tipo", "type": "novidade", "url": "http://a.test"},
          {"name": "sem número", "type": "m3u", "url": "http://b.test"},
          {"id": "abc", "name": "número que não é número", "type": "m3u", "url": "http://c.test"},
          {"id": 4, "name": "sem endereço", "type": "m3u", "url": "   "},
          "isto não é uma lista",
          {"id": 5, "name": "boa", "type": "m3u", "url": "http://e.test"}
        ]}
        """
        #expect(try parsePlaylistsAnswer(text).playlists.map(\.id) == [5])
    }

    @Test("lista que traz o resumo de um PIN é protegida, diga o que disser o outro campo")
    func pinHashMeansProtected() throws {
        let text = #"{"active": true, "playlists": [{"id": 1, "type": "m3u", "url": "http://a.test", "pin_protected": false, "pin_hash": "abc"}]}"#
        #expect(try parsePlaylistsAnswer(text).playlists.first?.pinProtected == true)
    }

    @Test("resposta que não segue o contrato é recusada", arguments: [
        "",
        "página de uma rede Wi-Fi",
        "[]",
        #"{"playlists": []}"#,
        #"{"active": "talvez"}"#,
        #"{"active": true, "expires_at": "amanhã"}"#,
        #"{"active": true, "expires_at": "2027-02-31T10:00:00Z"}"#,
        #"{"active": true, "expires_at": ""}"#,
        #"{"active": true, "expires_at": 20271002}"#,
        #"{"active": true, "expires_at": true}"#,
        #"{"active": true, "expires_at": {}}"#,
        #"{"active": true, "expires_at": []}"#,
        #"{"active": true, "expires_at": ["2027-10-02T22:40:23Z"]}"#,
    ])
    func rejectsBrokenAnswers(text: String) {
        #expect(throws: (any Error).self) { try parsePlaylistsAnswer(text) }
    }

    @Test("resposta com listas e objetos demais, uns dentro dos outros, é recusada sem ser lida")
    func rejectsTooDeepAnswers() throws {
        func nested(_ levels: Int) -> String {
            String(repeating: "[", count: levels) + String(repeating: "]", count: levels)
        }
        // O objeto de fora conta um nível: até o limite passa, um a mais não.
        let allowed = #"{"active": true, "extra": "# + nested(JSONValue.maxDepth - 1) + "}"
        let tooDeep = #"{"active": true, "extra": "# + nested(JSONValue.maxDepth) + "}"
        #expect(try parsePlaylistsAnswer(allowed).active)
        #expect(throws: JSONValue.TooDeep.self) { try parsePlaylistsAnswer(tooDeep) }
        #expect(throws: JSONValue.TooDeep.self) { try parseCodeAnswer(#"{"days": "# + nested(100_000) + "}") }
        #expect(throws: JSONValue.TooDeep.self) { try parseUnlinkAnswer(String(repeating: #"{"a":"#, count: 100_000)) }

        // O que está entre aspas não conta, nem com aspas e barras dentro do texto.
        let brackets = String(repeating: "[{", count: 200)
        let inText = #"{"active": true, "name": ""# + brackets + #" \" "# + brackets + #" \\", "playlists": []}"#
        #expect(try parsePlaylistsAnswer(inText).active)
        #expect(JSONValue.nestingDepth(of: inText) == 2)
        #expect(JSONValue.nestingDepth(of: "") == 0)
        #expect(JSONValue.nestingDepth(of: #"{"a": [1, {"b": []}], "c": {}}"#) == 4)
    }

    @Test("a resposta das listas não mostra o texto recebido (com usuário e senha) em texto nenhum")
    func answerIsNotPrinted() throws {
        let text = #"{"active": true, "playlists": [{"id": 7, "name": "Casa", "type": "xtream", "url": "http://servidor.exemplo:8080", "username": "ana", "password": "segredo"}]}"#
        let answer = try parsePlaylistsAnswer(text)
        var dumped = ""
        dump(answer, to: &dumped)
        for printed in ["\(answer)", String(describing: answer), String(reflecting: answer), dumped, "\([answer])", "\(Optional(answer) as Any)"] {
            #expect(!printed.contains("segredo"))
            #expect(!printed.contains("ana"))
            #expect(!printed.contains("servidor.exemplo"))
        }
        // O texto continua lá para a cópia guardada.
        #expect(answer.raw == text)
    }

    @Test("verdadeiro e falso como texto são aceitos, como no app Android")
    func booleanAsText() throws {
        #expect(try parsePlaylistsAnswer(#"{"active": "true"}"#).active)
        #expect(try !parsePlaylistsAnswer(#"{"active": "FALSE"}"#).active)
    }

    @Test("hora do servidor: só o formato do contrato")
    func serverTime() {
        let date = parseServerTime("2026-10-05T19:00:00Z")
        #expect(date?.timeIntervalSince1970 == 1_791_226_800)
        #expect(formatServerTime(date!) == "2026-10-05T19:00:00Z")
        for wrong in ["2026-10-05T19:00:00z", "2026-10-05 19:00:00Z", "2026-10-05T19:00:00", "2026-10-05T19:00:00+00:00",
                      "2026-13-05T19:00:00Z", "2026-10-32T19:00:00Z", "2026-10-05T24:00:00Z", "2026-10-05T19:60:00Z",
                      "2026-1-05T19:00:00Z", "20261005T190000Z", " 2026-10-05T19:00:00Z", "２０２６-10-05T19:00:00Z"] {
            #expect(parseServerTime(wrong) == nil, "aceitou \(wrong)")
        }
    }

    @Test("resposta do código de ativação")
    func codeAnswer() throws {
        #expect(try parseCodeAnswer(#"{"ok": true, "active": true, "days": 30}"#).days == 30)
        #expect(try parseCodeAnswer(#"{"ok": true, "days": "365"}"#).days == 365)
        #expect(try parseCodeAnswer(#"{"ok": true, "days": null}"#).days == nil)
        #expect(try parseCodeAnswer(#"{"ok": true, "days": 0}"#).days == nil)
        #expect(try parseCodeAnswer(#"{"ok": true}"#).days == nil)
        #expect(throws: (any Error).self) { try parseCodeAnswer("nada") }

        // Parceria: o campo `sponsored` vem junto; os dias podem vir zerados.
        #expect(try parseCodeAnswer(#"{"ok": true, "days": 20, "sponsored": true}"#) == CodeAnswer(days: 20, sponsored: true))
        #expect(try parseCodeAnswer(#"{"ok": true, "days": 0, "sponsored": true}"#) == CodeAnswer(days: nil, sponsored: true))
        #expect(try parseCodeAnswer(#"{"ok": true, "days": 30, "sponsored": false}"#) == CodeAnswer(days: 30, sponsored: false))
        #expect(try !parseCodeAnswer(#"{"ok": true, "days": 30}"#).sponsored)
        #expect(try !parseCodeAnswer(#"{"ok": true, "days": 30, "sponsored": "sim"}"#).sponsored)
    }

    @Test("parceria: o campo sponsored só vale verdadeiro, e só com o aparelho ativo")
    func sponsoredField() throws {
        #expect(try parsePlaylistsAnswer(#"{"active": true, "sponsored": true}"#).sponsored)
        #expect(try parsePlaylistsAnswer(#"{"active": true, "sponsored": "true"}"#).sponsored)
        #expect(try !parsePlaylistsAnswer(#"{"active": true, "sponsored": false}"#).sponsored)
        // Painel antigo: o campo não vem.
        #expect(try !parsePlaylistsAnswer(#"{"active": true}"#).sponsored)
        for other in ["null", "1", "\"sim\"", "[true]", "{\"sponsored\": true}"] {
            #expect(try !parsePlaylistsAnswer("{\"active\": true, \"sponsored\": \(other)}").sponsored, "valor \(other)")
        }
        // Fora do contrato: parceria sem o aparelho ativo não vale.
        #expect(try !parsePlaylistsAnswer(#"{"active": false, "sponsored": true}"#).sponsored)
        // Não é o `partner` (que só diz se um parceiro cuida do aparelho pelo painel).
        let managed = try parsePlaylistsAnswer(#"{"active": true, "partner": true}"#)
        #expect(managed.partner == true)
        #expect(!managed.sponsored)
        let sponsored = try parsePlaylistsAnswer(#"{"active": true, "sponsored": true}"#)
        #expect(sponsored.partner == nil)
    }

    @Test("resposta do desconectar do painel")
    func unlinkAnswer() throws {
        #expect(try parseUnlinkAnswer(#"{"ok": true, "unlinked": true, "partner": false}"#).unlinked)
        #expect(try !parseUnlinkAnswer(#"{"ok": true, "unlinked": false}"#).unlinked)
        #expect(try !parseUnlinkAnswer(#"{"ok": true}"#).unlinked)
        #expect(throws: (any Error).self) { try parseUnlinkAnswer("[1]") }
    }

    @Test("o código vai ao servidor sem traços nem espaços, em maiúsculas")
    func activationCodeText() {
        #expect(normalizeActivationCode(" abcd-efgh jkmn ") == "ABCDEFGHJKMN")
        #expect(normalizeActivationCode("AB_CD.EF") == "ABCDEF")
        #expect(formattedActivationCode("ABCDEFGHJKMN") == "ABCD-EFGH-JKMN")
        #expect(formattedActivationCode("ABCDE") == "ABCD-E")
        #expect(formattedActivationCode("ABCD") == "ABCD")
        #expect(formattedActivationCode("") == "")
    }

    @Test("o endereço, o usuário e a senha de uma lista não aparecem em texto nenhum")
    func playlistIsNotPrinted() {
        let list = SitePlaylist(id: 7, name: "Casa", kind: .server, url: "http://servidor.exemplo:8080", username: "ana", password: "segredo")
        var dumped = ""
        dump(list, to: &dumped)
        for text in ["\(list)", String(reflecting: list), dumped, "\([list])"] {
            #expect(!text.contains("segredo"))
            #expect(!text.contains("ana"))
            #expect(!text.contains("servidor.exemplo"))
        }
    }
}
