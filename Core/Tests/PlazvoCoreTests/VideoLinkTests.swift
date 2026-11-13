import Foundation
import Testing
@testable import PlazvoCore

/// Os mesmos casos do app Android (VideoLinkTest), mais o endereço como ele viaja.
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
        let url = "http://usuario:senha@exemplo.com:8080/filme/u/s/123.mp4?token=a%20b&x=1#t=10"
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

    @Test("a porta só aceita algarismos comuns")
    func portDigits() {
        #expect(VideoLink.normalize("http://exemplo.com:8080/a.mp4") == "http://exemplo.com:8080/a.mp4")
        // Algarismos de outra escrita (árabe-índicos) não são uma porta.
        #expect(VideoLink.normalize("http://exemplo.com:\u{0668}\u{0660}/a.mp4") == nil)
    }

    @Test("título é o fim do endereço, sem parâmetros")
    func title() {
        #expect(VideoLink.title("http://exemplo.com:8080/filme/usuario/senha/123.mp4?token=abc") == "123.mp4")
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
        #expect(VideoLink.host("http://usuario:senha@exemplo.com:8080/filme/u/s/1.mp4") == "exemplo.com")
        #expect(VideoLink.host("http://192.168.0.10:8080/a.ts") == "192.168.0.10")
        #expect(VideoLink.host("http://[2001:db8::1]:8080/a.ts") == "[2001:db8::1]")
        // Senha com arroba: vale o último, e a senha continua de fora.
        #expect(VideoLink.host("http://usuario:se@nha@exemplo.com/a.mp4") == "exemplo.com")
    }

    // MARK: - O endereço como ele viaja

    @Test("endereço comum viaja como está")
    func encodedPlain() {
        let url = "http://usuario:senha@exemplo.com:8080/filme/u/s/123.mp4?token=a%20b&x=1#t=10"
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

    @Test("o endereço que o app aceita sempre vira um endereço que o sistema entende")
    func encodedIsAlwaysAURL() throws {
        let typed = [
            "exemplo.com/meu vídeo [final] (1).mp4",
            "http://usuario:senha@exemplo.com:8080/live/u/s/1.ts?a=1&b=é",
            "https://exemplo.com/a|b/c^d/{e}.m3u8",
            "http://192.168.0.10:8080/100%.mkv",
        ]
        for text in typed {
            let url = try #require(VideoLink.normalize(text))
            let parsed = try #require(URL(string: VideoLink.encoded(url)), "endereço: \(text)")
            #expect(parsed.scheme == "http" || parsed.scheme == "https")
            #expect(parsed.host == VideoLink.host(url))
        }
    }
}
