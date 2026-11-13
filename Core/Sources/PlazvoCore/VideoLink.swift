import Foundation

/// Tratamento dos endereços de vídeo digitados pelo usuário (o mesmo do app Android, com duas
/// diferenças: o tamanho tem limite e o nome do servidor só aceita letras sem acento).
public enum VideoLink {
    /// O maior endereço aceito, em bytes. (Um endereço de verdade, mesmo com uma chave de acesso
    /// comprida, fica bem abaixo disso; um texto enorme colado por engano travaria a tela.)
    public static let maxLength = 8_192

    /// Devolve o endereço pronto para abrir, ou `nil` se não for um endereço http/https válido.
    /// Sem "http://" na frente, assume http (o servidor redireciona para https quando precisa).
    public static func normalize(_ input: String) -> String? {
        // Com folga para os espaços das pontas; o limite de verdade é conferido logo abaixo.
        guard input.utf8.count <= maxLength * 2 else { return nil }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "%20")
        guard text.utf8.count <= maxLength else { return nil }
        if text.isEmpty || text.unicodeScalars.contains(where: isSpaceOrControl) { return nil }

        let (found, rest) = splitScheme(text)
        let scheme = found ?? "http"
        guard scheme == "http" || scheme == "https" else { return nil }
        guard isValidAuthority(authority(of: rest)) else { return nil }
        return "\(scheme)://\(rest)"
    }

    /// O começo do texto, até o tamanho do maior endereço aceito, sem partir uma letra ao meio.
    /// (Para o campo do endereço: um texto enorme colado por engano não fica nele.)
    public static func fitted(_ text: String) -> String {
        let bytes = text.utf8
        guard bytes.count > maxLength else { return text }
        var end = bytes.index(bytes.startIndex, offsetBy: maxLength)
        while end > bytes.startIndex, end.samePosition(in: text.unicodeScalars) == nil {
            bytes.formIndex(before: &end)
        }
        return String(text[..<end])
    }

    /// Nome para mostrar na lista: o fim do endereço (nunca o caminho todo, que pode ter senha).
    public static func title(_ url: String) -> String {
        let rest = splitScheme(url).rest
        var path = Substring(rest.dropFirst(authority(of: rest).count))
        if let query = path.firstIndex(of: "?") { path = path[..<query] }
        if let fragment = path.firstIndex(of: "#") { path = path[..<fragment] }
        guard let segment = path.split(separator: "/", omittingEmptySubsequences: true).last else { return host(url) }
        // Código de letra que não dá para ler ("100%.mp4"): o nome fica como veio.
        return String(segment).removingPercentEncoding ?? String(segment)
    }

    /// Só o nome do servidor, sem usuário, senha, porta nem caminho.
    public static func host(_ url: String) -> String {
        host(of: authority(of: splitScheme(url).rest))
    }

    /// O endereço como ele viaja: o que um endereço não aceita (letra acentuada, colchete, barra
    /// em pé…) vira o código dele ("%C3%AD"), no usuário e na senha e em tudo o que vem depois do
    /// nome do servidor. O que já é código fica como está; um "%" solto vira "%25".
    public static func encoded(_ url: String) -> String {
        let (scheme, rest) = splitScheme(url)
        let server = authority(of: rest)
        var result = String.UnicodeScalarView()
        result.append(contentsOf: (scheme.map { "\($0)://" } ?? "").unicodeScalars)
        if let at = server.lastIndex(of: "@") {
            // Usuário e senha: um "@" a mais (o da senha) também vira código.
            append(Array(server[..<at].utf8), to: &result, allowed: isAllowedInUserInfo)
            result.append(contentsOf: server[at...].unicodeScalars)
        } else {
            result.append(contentsOf: server.unicodeScalars)
        }
        append(Array(rest.dropFirst(server.count).utf8), to: &result, allowed: isAllowedAfterServer)
        return String(result)
    }

    private static func append(_ bytes: [UInt8], to result: inout String.UnicodeScalarView, allowed: (UInt8) -> Bool) {
        let digits = Array("0123456789ABCDEF".unicodeScalars)
        for (index, byte) in bytes.enumerated() {
            let keep: Bool
            if byte == UInt8(ascii: "%") {
                keep = index + 2 < bytes.count && isHexDigit(bytes[index + 1]) && isHexDigit(bytes[index + 2])
            } else {
                keep = allowed(byte)
            }
            if keep {
                result.append(Unicode.Scalar(byte))
            } else {
                result.append("%")
                result.append(digits[Int(byte >> 4)])
                result.append(digits[Int(byte & 0x0F)])
            }
        }
    }

    // MARK: - Partes do endereço

    /// O começo "nome://" (em minúsculas) e o resto do endereço; sem esse começo, só o resto.
    private static func splitScheme(_ text: String) -> (scheme: String?, rest: String) {
        let scalars = Array(text.unicodeScalars)
        var end = 0
        while end < scalars.count, isSchemeCharacter(scalars[end]) { end += 1 }
        guard end > 0, isASCIILetter(scalars[0]), end + 3 <= scalars.count,
              scalars[end] == ":", scalars[end + 1] == "/", scalars[end + 2] == "/"
        else { return (nil, text) }
        var scheme = String.UnicodeScalarView()
        scheme.append(contentsOf: scalars[..<end])
        var rest = String.UnicodeScalarView()
        rest.append(contentsOf: scalars[(end + 3)...])
        return (String(scheme).lowercased(), String(rest))
    }

    /// O trecho do servidor (com usuário, senha e porta, se houver): tudo antes do caminho.
    private static func authority(of rest: String) -> String {
        String(rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
    }

    private static func hostAndPort(_ authority: String) -> String {
        guard let at = authority.lastIndex(of: "@") else { return authority }
        return String(authority[authority.index(after: at)...])
    }

    private static func host(of authority: String) -> String {
        let hostPort = hostAndPort(authority)
        if hostPort.hasPrefix("[") {
            let inside = hostPort.firstIndex(of: "]").map { String(hostPort[..<$0]) } ?? hostPort
            return inside + "]"
        }
        return String(hostPort.prefix { $0 != ":" })
    }

    private static func isValidAuthority(_ authority: String) -> Bool {
        let hostPort = hostAndPort(authority)
        let host = host(of: authority)
        var port = Substring(hostPort)
        if port.hasPrefix(host) { port = port.dropFirst(host.count) }
        if port.hasPrefix(":") { port = port.dropFirst() }
        // A porta, quando há, é só de algarismos comuns (0 a 9) e vai até 65535.
        if port.unicodeScalars.contains(where: { !("0"..."9").contains($0) }) { return false }
        if !port.isEmpty, port.count > 5 || (Int(port) ?? 0) > 65_535 { return false }
        if host.hasPrefix("[") { return host.count > 2 && hostPort.contains("]") }
        // O nome do servidor: só letras sem acento, algarismos comuns, ponto, traço e sublinhado.
        // (Nome com acento ou com letras de outros alfabetos tem uma forma escrita só com essas
        // letras, e é essa que o endereço leva; o que aparece na tela é igual ao que é aberto.)
        let scalars = host.unicodeScalars
        return scalars.contains(where: isASCIILetterOrDigit)
            && scalars.allSatisfy { isASCIILetterOrDigit($0) || $0 == "." || $0 == "-" || $0 == "_" }
    }

    // MARK: - Letras

    /// O que pode aparecer como está no caminho e nos parâmetros de um endereço.
    private static func isAllowedAfterServer(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return "-._~:/?#@!$&'()*+,;=".utf8.contains(byte)
        }
    }

    /// O que pode aparecer como está no usuário e na senha.
    private static func isAllowedInUserInfo(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        default:
            return "-._~:!$&'()*+,;=".utf8.contains(byte)
        }
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "f"), UInt8(ascii: "A")...UInt8(ascii: "F"):
            return true
        default:
            return false
        }
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private static func isSchemeCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isASCIILetter(scalar) || ("0"..."9").contains(scalar) || scalar == "+" || scalar == "." || scalar == "-"
    }

    private static func isASCIILetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        isASCIILetter(scalar) || ("0"..."9").contains(scalar)
    }

    private static func isSpaceOrControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar.properties.generalCategory == .control
    }
}
