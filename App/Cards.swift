import PlazvoCore
import SwiftUI

/// A seta de voltar e o título das telas internas, fixos no alto.
struct ScreenHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                IconView(icon: .arrowBack, size: 24)
                    .foregroundColor(PlazvoColors.onSurface)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(t("back"))
            // A seta fica alinhada com a borda do conteúdo.
            .padding(.leading, -12)
            .padding(.trailing, 4)
            Text(title)
                .style(.titleLarge)
                .foregroundColor(PlazvoColors.onSurface)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// Cartão da tela inicial com um degradê escuro: ícone e nome numa linha (Mídia).
struct GradientCard: View {
    let icon: PlazvoIcon
    let title: String
    let from: Color
    let to: Color
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                IconView(icon: icon, size: 26)
                    .foregroundColor(Color.white.opacity(0.9))
                Text(title)
                    .style(TextStyle.titleMedium.weight(.bold))
                    .foregroundColor(Color.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
            .background(shape.fill(LinearGradient(colors: [from, to], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
    }
}

/// Ícone dentro de um quadrado arredondado, na cor de destaque.
struct IconBadge: View {
    let icon: PlazvoIcon
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(PlazvoColors.accent.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                IconView(icon: icon, size: 24)
                    .foregroundColor(PlazvoColors.accent)
            )
    }
}

/// Cartão clicável com ícone, título e descrição (a tela Mídia em pé).
struct ActionCard: View {
    let icon: PlazvoIcon
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            HStack(spacing: 16) {
                IconBadge(icon: icon, size: 52)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .style(TextStyle.titleMedium.weight(.semibold))
                        .foregroundColor(PlazvoColors.onSurface)
                    Text(description)
                        .style(.bodyMedium)
                        .foregroundColor(PlazvoColors.onSurfaceMuted)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(PlazvoColors.surface))
            .overlay(shape.strokeBorder(PlazvoColors.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
    }
}

/// Bloco clicável das telas largas: ícone em cima, título e descrição embaixo. Ocupa o espaço que
/// receber; se ficar baixo demais, mostra só o ícone e o título.
struct TileCard: View {
    let icon: PlazvoIcon
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            GeometryReader { proxy in
                let roomy = proxy.size.height >= 136
                VStack(alignment: .leading, spacing: 0) {
                    IconBadge(icon: icon, size: roomy ? 48 : 40)
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .style(TextStyle.titleMedium.weight(.semibold))
                            .foregroundColor(PlazvoColors.onSurface)
                            .lineLimit(roomy ? 2 : 1)
                        if roomy {
                            Text(description)
                                .style(.bodyMedium)
                                .foregroundColor(PlazvoColors.onSurfaceMuted)
                                .lineLimit(2)
                        }
                    }
                    .multilineTextAlignment(.leading)
                }
                .padding(16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .background(shape.fill(PlazvoColors.surface))
            .overlay(shape.strokeBorder(PlazvoColors.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
    }
}

/// Barra fina que mostra quanto de um vídeo já foi visto (`value` de 0 a 1).
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PlazvoColors.outline)
                Capsule()
                    .fill(PlazvoColors.accent)
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Botão comprido de cantos redondos com contorno ("Colar").
struct OutlinedButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .style(.labelLarge)
                .foregroundColor(PlazvoColors.accent)
                .padding(.horizontal, 24)
                .frame(minHeight: 40)
                .overlay(Capsule().strokeBorder(PlazvoColors.outline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Botão comprido de cantos redondos na cor de destaque ("Abrir").
struct FilledButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .style(.labelLarge)
                .foregroundColor(PlazvoColors.onAccent)
                .padding(.horizontal, 24)
                .frame(minHeight: 40)
                .background(Capsule().fill(PlazvoColors.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}
