import SwiftUI
import UIKit

/// Paleta da marca Plazvo (a mesma do app Android). O app tem um único tema, escuro.
enum PlazvoColors {
    static let background = Color(hex: 0x0B0B14)
    static let backgroundGlow = Color(hex: 0x1B1738)
    static let surface = Color(hex: 0x151523)
    static let surfaceHigh = Color(hex: 0x1F1F35)
    static let outline = Color(hex: 0x2B2B47)
    static let onSurface = Color(hex: 0xF1F1F8)
    static let onSurfaceMuted = Color(hex: 0xA3A3BD)
    static let accent = Color(hex: 0x9C8CFF)
    static let onAccent = Color(hex: 0x14103A)
    /// Avisos de erro em texto (código inválido, ativação vencida).
    static let warning = Color(hex: 0xFF8A8A)
    /// Aviso de que a ativação vence logo.
    static let expiring = Color(hex: 0xFFC069)
}

extension Color {
    /// Cor a partir do número dela (0xRRGGBB).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Um estilo de letra: os tamanhos e as alturas de linha do app Android, em pontos, com a letra
/// do sistema. O tamanho é fixo, como no desenho das telas.
struct TextStyle {
    let size: CGFloat
    let weight: Font.Weight
    let lineHeight: CGFloat
    var tracking: CGFloat = 0
    var fixedWidth = false

    static let headlineSmall = TextStyle(size: 24, weight: .regular, lineHeight: 32)
    static let titleLarge = TextStyle(size: 22, weight: .regular, lineHeight: 28)
    static let titleMedium = TextStyle(size: 16, weight: .medium, lineHeight: 24)
    static let bodyLarge = TextStyle(size: 16, weight: .regular, lineHeight: 24)
    static let bodyMedium = TextStyle(size: 14, weight: .regular, lineHeight: 20)
    static let bodySmall = TextStyle(size: 12, weight: .regular, lineHeight: 16)
    static let labelLarge = TextStyle(size: 14, weight: .medium, lineHeight: 20)
    static let labelMedium = TextStyle(size: 12, weight: .medium, lineHeight: 16, tracking: 0.3)

    /// O mesmo estilo com outro peso.
    func weight(_ weight: Font.Weight) -> TextStyle {
        TextStyle(size: size, weight: weight, lineHeight: lineHeight, tracking: tracking, fixedWidth: fixedWidth)
    }

    /// O mesmo estilo com letra de largura fixa (ID e chave).
    func monospaced() -> TextStyle {
        TextStyle(size: size, weight: weight, lineHeight: lineHeight, tracking: tracking, fixedWidth: true)
    }

    var font: Font {
        Font.system(size: size, weight: weight, design: fixedWidth ? .monospaced : .default)
    }

    /// O que falta para a linha ter a altura do estilo (a linha da letra do sistema é mais baixa).
    var extraLineHeight: CGFloat {
        let natural = fixedWidth
            ? UIFont.monospacedSystemFont(ofSize: size, weight: .regular).lineHeight
            : UIFont.systemFont(ofSize: size).lineHeight
        return max(0, lineHeight - natural)
    }
}

extension Text {
    /// Aplica um estilo de letra, com a altura de linha dele.
    func style(_ style: TextStyle) -> some View {
        let extra = style.extraLineHeight
        return font(style.font)
            .tracking(style.tracking)
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}
