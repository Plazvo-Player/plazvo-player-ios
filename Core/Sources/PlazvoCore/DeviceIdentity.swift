import Foundation

/// Identificação deste aparelho: o que o usuário informa no site ou ao parceiro.
public struct DeviceIdentity: Equatable, Sendable {
    /// Formato de MAC, ex.: `a3:7f:12:9c:04:e1`.
    public let id: String
    /// 6 dígitos.
    public let key: String

    public init(id: String, key: String) {
        self.id = id
        self.key = key
    }
}

/// O que o app apresenta ao servidor: o ID, a chave e o segredo do aparelho.
/// O segredo nunca aparece na tela nem em registros: por isso a descrição mostra só o ID.
public struct DeviceCredentials: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let id: String
    public let key: String
    /// 64 caracteres hexadecimais em minúsculas.
    public let secret: String

    public init(id: String, key: String, secret: String) {
        self.id = id
        self.key = key
        self.secret = secret
    }

    public var description: String { "DeviceCredentials(id: \(id))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["id": id]) }
}

/// De onde vêm os números sorteados. Nos testes, uma fonte previsível.
public struct RandomSource {
    /// `count` bytes sorteados.
    public var bytes: (_ count: Int) -> [UInt8]
    /// Um número sorteado dentro do intervalo.
    public var number: (_ range: Range<Int>) -> Int

    public init(bytes: @escaping (Int) -> [UInt8], number: @escaping (Range<Int>) -> Int) {
        self.bytes = bytes
        self.number = number
    }

    /// O gerador do sistema (próprio para segredos).
    public static var system: RandomSource {
        RandomSource(
            bytes: { count in
                var generator = SystemRandomNumberGenerator()
                return (0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
            },
            number: { range in
                var generator = SystemRandomNumberGenerator()
                return Int.random(in: range, using: &generator)
            }
        )
    }
}

/// Cria o ID, a chave e o segredo, nos mesmos formatos do app Android.
/// No iPhone não existe um número do aparelho que o app possa ler: os três são sorteados.
public enum DeviceIdGenerator {
    /// ID no formato de MAC: 6 bytes em hexadecimal, separados por dois-pontos.
    public static func newId(_ random: RandomSource = .system) -> String {
        random.bytes(6).map(hex).joined(separator: ":")
    }

    /// Chave de 6 dígitos, sem zero à esquerda (evita que o zero se perca ao digitar).
    public static func newKey(_ random: RandomSource = .system) -> String {
        String(random.number(100_000..<1_000_000))
    }

    /// Segredo: 32 bytes em hexadecimal (64 caracteres).
    public static func newSecret(_ random: RandomSource = .system) -> String {
        random.bytes(32).map(hex).joined()
    }

    public static func isValidId(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 6 && parts.allSatisfy { $0.count == 2 && $0.allSatisfy(isLowerHex) }
    }

    public static func isValidKey(_ text: String) -> Bool {
        text.count == 6 && text.allSatisfy { $0.isASCII && $0.isNumber } && text.first != "0"
    }

    public static func isValidSecret(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy(isLowerHex)
    }

    private static func hex(_ byte: UInt8) -> String {
        let digits = Array("0123456789abcdef")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
    }

    private static func isLowerHex(_ character: Character) -> Bool {
        ("0"..."9").contains(character) || ("a"..."f").contains(character)
    }
}
