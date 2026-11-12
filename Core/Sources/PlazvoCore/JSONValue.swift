import Foundation

/// Um valor JSON qualquer, para ler as respostas do servidor campo a campo, com a mesma
/// tolerância do app Android (número onde se espera texto, campo que falta, campo nulo).
enum JSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// As respostas da API têm três níveis (objeto › lista › objeto). Muito mais que isso é
    /// resposta estranha, e ler um texto com milhares de níveis derrubaria o app.
    static let maxDepth = 16

    /// O texto tem listas e objetos demais, uns dentro dos outros.
    struct TooDeep: Error, Equatable {}

    /// Lê um texto JSON. Lança se não for JSON ou se passar de `maxDepth` níveis.
    static func parse(_ text: String) throws -> JSONValue {
        guard nestingDepth(of: text) <= maxDepth else { throw TooDeep() }
        return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// Quantos níveis de listas e objetos, uns dentro dos outros, o texto chega a abrir (o que
    /// está entre aspas não conta).
    static func nestingDepth(of text: String) -> Int {
        var depth = 0
        var deepest = 0
        var inString = false
        var escaped = false
        for byte in text.utf8 {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
                deepest = max(deepest, depth)
            case UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
            default:
                break
            }
        }
        return deepest
    }

    /// Os campos, se o valor é um objeto.
    var fields: [String: JSONValue]? {
        if case .object(let fields) = self { return fields }
        return nil
    }

    /// O valor como texto (número e verdadeiro/falso viram texto), ou `nil` se é nulo, lista ou objeto.
    var text: String? {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null, .array, .object: return nil
        }
    }

    /// O valor como verdadeiro/falso (aceita os textos "true" e "false"), ou `nil`.
    var flag: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value):
            switch value.lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        default: return nil
        }
    }

    /// O valor como número inteiro (aceita texto só com algarismos), ou `nil`.
    var whole: Int? {
        switch self {
        case .integer(let value): return Int(exactly: value)
        case .number(let value): return Int(exactly: value.rounded(.towardZero))
        case .string(let value): return Int(value)
        default: return nil
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    /// Texto de um campo, ou `nil` se o campo não veio ou veio nulo.
    func text(_ name: String) -> String? {
        self[name]?.text
    }
}
