import Foundation
import Testing
@testable import PlazvoCore

/// Os mesmos casos do app Android (VideoLinkTest), mais o endereço como ele viaja, o limite de
/// tamanho e o nome do servidor só com letras sem acento.
@Suite("Endereço de vídeo digitado pelo usuário")
struct VideoLinkTests {
    @Test("endereço completo passa como está")
    func fullAddress() {
        #expect(VideoLink.normalize("https://exemplo.com/video.mp4") == "https://exemplo.com/video.mp4")
        #expect(VideoLink.normalize("http://exemplo.com/video.m3u8") == "http://exemplo.com/video.m3u8")
    }

    @Test("sem http na frente, assume http")
    func withoutScheme() {
        #expect(VideoLink.normalize("exemplo.com/video.ts") == "http://exemplo.com/video.ts")
        #expect(VideoLink.normalize("192.168.0.10:8080/a.mkv") == "http://192.168.0.10:8080/a.mkv")
    }

    @Test("espaços e quebras de linha em volta são ignorados")
    func trims() {
        #expect(VideoLink.normalize("  http://exemplo.com/a.mp4\n") == "http://exemplo.com/a.mp4")
    }

    @Test("espaço no meio do caminho vira código de espaço")
    func spaceInPath() {
        #expect(VideoLink.normalize("http://exemplo.com/meu video.mp4") == "http://exemplo.com/meu%20video.mp4")
    }

    @Test("HTTP em maiúsculas é aceito e vira minúsculas")
    func upperCaseScheme() {
        #expect(VideoLink.normalize("HTTP://Exemplo.com/A.mp4") == "http://Exemplo.com/A.mp4")
    }

    @Test("usuário, senha, porta e parâmetros são mantidos")
    func keepsEverything() {
        let url = "http://usuario:senha@exemplo.com:8080/pasta/u/s/123.mp4?token=a%20b&x=1#t=10"
        #expect(VideoLink.normalize(url) == url)
    }

    @Test("endereço IPv6 é aceito")
    func ipv6() {
        #expect(VideoLink.normalize("http://[2001:db8::1]:8080/a.ts") == "http://[2001:db8::1]:8080/a.ts")
    }

    @Test("vazio ou só espaços não é endereço")
    func empty() {
        #expect(VideoLink.normalize("") == nil)
        #expect(VideoLink.normalize("   ") == nil)
    }

    @Test("só http e https são aceitos")
    func onlyHttp() {
        #expect(VideoLink.normalize("rtsp://exemplo.com/video") == nil)
        #expect(VideoLink.normalize("ftp://exemplo.com/video.mp4") == nil)
        #expect(VideoLink.normalize("file:///sdcard/video.mp4") == nil)
        #expect(VideoLink.normalize("content://media/external/video/1") == nil)
    }

    @Test("endereço sem servidor válido é recusado")
    func invalidServer() {
        #expect(VideoLink.normalize("http://") == nil)
        #expect(VideoLink.normalize("http:///video.mp4") == nil)
        #expect(VideoLink.normalize("meu video") == nil)
        #expect(VideoLink.normalize("http://exemplo.com:porta/a.mp4") == nil)
        #expect(VideoLink.normalize("http://[2001:db8::1/a.ts") == nil)
        #expect(VideoLink.normalize("...") == nil)
    }

    @Test("quebra de linha no meio é recusada")
    func lineBreakInside() {
        #expect(VideoLink.normalize("http://exemplo.com/a\nb.mp4") == nil)
        #expect(VideoLink.normalize("http://exemplo.com/a\tb.mp4") == nil)
    }

    @Test("a porta só aceita algarismos comuns, até 65535")
    func portDigits() {
        #expect(VideoLink.normalize("http://exemplo.com:8080/a.mp4") == "http://exemplo.com:8080/a.mp4")
        // Algarismos de outra escrita (árabe-índicos) não são uma porta.
        #expect(VideoLink.normalize("http://exemplo.com:\u{0668}\u{0660}/a.mp4") == nil)
        #expect(VideoLink.normalize("http://exemplo.com:65535/a.mp4") == "http://exemplo.com:65535/a.mp4")
        #expect(VideoLink.normalize("http://exemplo.com:65536/a.mp4") == nil)
        #expect(VideoLink.normalize("http://exemplo.com:080800/a.mp4") == nil)
        #expect(VideoLink.normalize("http://exemplo.com:99999999999999999999/a.mp4") == nil)
        // Dois pontos sem número: vale a porta de sempre.
        #expect(VideoLink.normalize("http://exemplo.com:/a.mp4") == "http://exemplo.com:/a.mp4")
    }

    @Test("o nome do servidor só aceita letras sem acento, algarismos comuns, ponto, traço e sublinhado")
    func plainServerName() {
        #expect(VideoLink.normalize("http://Meu-Servidor_2.exemplo.com/a.mp4") == "http://Meu-Servidor_2.exemplo.com/a.mp4")
        #expect(VideoLink.normalize("http://vídeo.exemplo.com/a.mp4") == nil)
        #expect(VideoLink.normalize("http://日本.exemplo/a.mp4") == nil)
        // Algarismos de outra escrita, que o sistema leria como 127.0.0.1: o que aparece na tela
        // tem de ser igual ao que é aberto.
        #expect(VideoLink.normalize("http://\u{FF11}\u{FF12}\u{FF17}.\u{FF10}.\u{FF10}.\u{FF11}/a.mp4") == nil)
        #expect(VideoLink.normalize("http://exemplo\u{3002}com/a.mp4") == nil)
        // No usuário, na senha e no caminho o acento continua valendo (viaja em código).
        #expect(VideoLink.normalize("http://usuário:señha@exemplo.com/vídeo.mp4") == "http://usuário:señha@exemplo.com/vídeo.mp4")
    }

    @Test("endereço grande demais é recusado, sem travar a tela")
    func tooLong() {
        let start = "http://exemplo.com/"
        let fits = start + String(repeating: "a", count: VideoLink.maxLength - start.utf8.count)
        #expect(VideoLink.normalize(fits) == fits)
        #expect(VideoLink.normalize(fits + "a") == nil)
        // O limite é em bytes: letra acentuada conta por duas.
        let accented = start + String(repeating: "é", count: (VideoLink.maxLength - start.utf8.count) / 2 + 1)
        #expect(VideoLink.normalize(accented) == nil)
        // Texto enorme colado por engano (5 MB): recusado na hora.
        let huge = String(repeating: "exemplo.com/a b ", count: 320_000)
        let started = Date()
        #expect(VideoLink.normalize(huge) == nil)
        #expect(VideoLink.normalize(" " + huge) == nil)
        #expect(Date().timeIntervalSince(started) < 1)
    }

    @Test("o campo do endereço fica só com o começo de um texto enorme, sem partir uma letra ao meio")
    func fitted() {
        #expect(VideoLink.fitted("http://exemplo.com/a.mp4") == "http://exemplo.com/a.mp4")
        #expect(VideoLink.fitted("") == "")
        let exact = String(repeating: "a", count: VideoLink.maxLength)
        #expect(VideoLink.fitted(exact) == exact)
        #expect(VideoLink.fitted(exact + "b") == exact)
        // Letras de 2, 3 e 4 bytes na divisa: o corte recua até o fim da letra anterior.
        for letter in ["é", "日", "😀", "e\u{301}", "👨‍👩‍👧"] {
            for lead in 0..<4 {
                let text = String(repeating: "a", count: lead) + String(repeating: letter, count: VideoLink.maxLength)
                let cut = VideoLink.fitted(text)
                #expect(cut.utf8.count <= VideoLink.maxLength, "começo \(lead)")
                #expect(cut.utf8.count > VideoLink.maxLength - 4, "começo \(lead)")
                // É o começo do texto, byte a byte (o corte pode ficar entre a letra e o acento solto dela).
                #expect(text.utf8.starts(with: cut.utf8), "letra \(letter.unicodeScalars.map { String($0.value, radix: 16) }), começo \(lead)")
                #expect(!cut.unicodeScalars.contains("\u{FFFD}"), "começo \(lead)")
                // Cortar de novo não muda nada (a tela não fica cortando sem parar).
                #expect(VideoLink.fitted(cut).utf8.elementsEqual(cut.utf8), "começo \(lead)")
            }
        }
        // 5 MB colados por engano: na hora.
        let huge = String(repeating: "exemplo.com/a b ", count: 320_000)
        let started = Date()
        #expect(VideoLink.fitted(huge).utf8.count == VideoLink.maxLength)
        #expect(Date().timeIntervalSince(started) < 1)
    }

    @Test("título é o fim do endereço, sem parâmetros")
    func title() {
        #expect(VideoLink.title("http://exemplo.com:8080/pasta/usuario/senha/123.mp4?token=abc") == "123.mp4")
        #expect(VideoLink.title("https://exemplo.com/meu%20v%C3%ADdeo.mp4#t=5") == "meu vídeo.mp4")
        #expect(VideoLink.title("https://exemplo.com/pasta/a+b.mkv") == "a+b.mkv")
        #expect(VideoLink.title("http://exemplo.com/ao-vivo/") == "ao-vivo")
    }

    @Test("título de endereço sem caminho é o nome do servidor")
    func titleWithoutPath() {
        #expect(VideoLink.title("http://exemplo.com") == "exemplo.com")
        #expect(VideoLink.title("http://usuario:senha@exemplo.com:8080/?a=1") == "exemplo.com")
    }

    @Test("título com código inválido fica como veio")
    func titleWithBadCode() {
        #expect(VideoLink.title("http://exemplo.com/100%.mp4") == "100%.mp4")
    }

    @Test("servidor nunca mostra usuário, senha, porta nem caminho")
    func host() {
        #expect(VideoLink.host("http://usuario:senha@exemplo.com:8080/pasta/u/s/1.mp4") == "exemplo.com")
        #expect(VideoLink.host("http://192.168.0.10:8080/a.ts") == "192.168.0.10")
        #expect(VideoLink.host("http://[2001:db8::1]:8080/a.ts") == "[2001:db8::1]")
        // Senha com arroba: vale o último, e a senha continua de fora.
        #expect(VideoLink.host("http://usuario:se@nha@exemplo.com/a.mp4") == "exemplo.com")
    }

    // MARK: - O endereço como ele viaja

    @Test("endereço comum viaja como está")
    func encodedPlain() {
        let url = "http://usuario:senha@exemplo.com:8080/pasta/u/s/123.mp4?token=a%20b&x=1#t=10"
        #expect(VideoLink.encoded(url) == url)
        #expect(VideoLink.encoded("https://exemplo.com/pasta/a+b.mkv") == "https://exemplo.com/pasta/a+b.mkv")
        #expect(VideoLink.encoded("http://[2001:db8::1]:8080/a.ts") == "http://[2001:db8::1]:8080/a.ts")
    }

    @Test("letra acentuada, colchete e barra em pé viram o código deles")
    func encodedSpecial() {
        #expect(VideoLink.encoded("http://exemplo.com/meu vídeo.mp4") == "http://exemplo.com/meu%20v%C3%ADdeo.mp4")
        #expect(VideoLink.encoded("http://exemplo.com/a[1].mp4") == "http://exemplo.com/a%5B1%5D.mp4")
        #expect(VideoLink.encoded("http://exemplo.com/a|b.ts?x=\"y\"") == "http://exemplo.com/a%7Cb.ts?x=%22y%22")
        #expect(VideoLink.encoded("http://exemplo.com/日本.mp4") == "http://exemplo.com/%E6%97%A5%E6%9C%AC.mp4")
    }

    @Test("o que já é código fica como está; um \"%\" solto vira \"%25\"")
    func encodedPercent() {
        #expect(VideoLink.encoded("http://exemplo.com/meu%20v%C3%ADdeo.mp4") == "http://exemplo.com/meu%20v%C3%ADdeo.mp4")
        #expect(VideoLink.encoded("http://exemplo.com/100%.mp4") == "http://exemplo.com/100%25.mp4")
        #expect(VideoLink.encoded("http://exemplo.com/a%2") == "http://exemplo.com/a%252")
        #expect(VideoLink.encoded("http://exemplo.com/a%zz.ts") == "http://exemplo.com/a%25zz.ts")
    }

    @Test("usuário e senha com acento, arroba ou símbolo viajam em código")
    func encodedUserAndPassword() {
        #expect(VideoLink.encoded("http://usuário:señha@exemplo.com/a.mp4") == "http://usu%C3%A1rio:se%C3%B1ha@exemplo.com/a.mp4")
        // Arroba na senha: o último é o que separa do servidor.
        #expect(VideoLink.encoded("http://usuario:se@nha@exemplo.com/a.mp4") == "http://usuario:se%40nha@exemplo.com/a.mp4")
        #expect(VideoLink.encoded("http://u:a[1]{2}|3@exemplo.com:8080/a.mp4") == "http://u:a%5B1%5D%7B2%7D%7C3@exemplo.com:8080/a.mp4")
        #expect(VideoLink.encoded("http://u:100%@exemplo.com/a.mp4") == "http://u:100%25@exemplo.com/a.mp4")
        // O que já é código fica como está, e o que o endereço aceita também.
        #expect(VideoLink.encoded("http://u:p%20w@exemplo.com/a.mp4") == "http://u:p%20w@exemplo.com/a.mp4")
        #expect(VideoLink.encoded("http://a.b-c_d~e:p!$&'()*+,;=q@exemplo.com/a.mp4") == "http://a.b-c_d~e:p!$&'()*+,;=q@exemplo.com/a.mp4")
        // Sem usuário, o servidor fica como está.
        #expect(VideoLink.encoded("http://exemplo.com:8080/a@b.mp4") == "http://exemplo.com:8080/a@b.mp4")
    }

    @Test("o endereço que o app aceita vira sempre um endereço que o sistema entende sem mexer em nada")
    func encodedIsAlwaysAURL() throws {
        let users = ["", "usuario:senha@", "usuário:señha@", "u:se@nha@", "u:100%@", "a b:c d@", "u:p[1]{2}|3^4`5@", "😀:🔑@", "só-usuário@", ":só-senha@"]
        let servers = ["exemplo.com", "exemplo.com:8080", "192.168.0.10:8080", "[2001:db8::1]:8080", "Meu-Servidor_2.exemplo"]
        let paths = [
            "", "/", "/meu vídeo [final] (1).mp4", "/a|b/c^d/{e}.m3u8", "/100%.mkv", "/pasta/u/s/1.ts?a=1&b=é",
            "/日本.mp4#t=10", "/a%20b%zz%2", "/\"aspas\"<x>`y`.ts", "/😀.mp4", "?x=1&y=á b", "/a\\b.ts", "/a@b:c.ts",
        ]
        var checked = 0
        for user in users {
            for server in servers {
                for path in paths {
                    let typed = "http://" + user + server + path
                    let url = try #require(VideoLink.normalize(typed), "digitado: \(typed)")
                    let sent = VideoLink.encoded(url)
                    // Só letras e sinais comuns: nada que mude de um sistema para outro.
                    #expect(sent.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }, "digitado: \(typed)")
                    // Codificar de novo não muda nada.
                    #expect(VideoLink.encoded(sent) == sent, "digitado: \(typed)")
                    let parsed = try #require(URL(string: sent), "digitado: \(typed)")
                    // O sistema lê o endereço como ele está, sem reescrever.
                    #expect(parsed.absoluteString == sent, "digitado: \(typed)")
                    #expect(parsed.scheme == "http")
                    let host = VideoLink.host(url).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    #expect(parsed.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) == host, "digitado: \(typed)")
                    checked += 1
                }
            }
        }
        #expect(checked == 650)

        // O usuário e a senha chegam ao servidor como foram digitados.
        let parts = try #require(URLComponents(string: VideoLink.encoded("http://usuário:se@nha@exemplo.com/a.mp4")))
        #expect(parts.user == "usuário")
        #expect(parts.password == "se@nha")
        #expect(parts.host == "exemplo.com")
    }
}
