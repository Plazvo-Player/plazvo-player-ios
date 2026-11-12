import PlazvoCore
import SwiftUI

/// O fundo do app: o brilho roxo no alto, que some até 45% da altura.
struct Backdrop: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: PlazvoColors.backgroundGlow, location: 0),
                .init(color: PlazvoColors.background, location: 0.45),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Os ícones do app: os mesmos desenhos do app Android (Material arredondado), guardados como
/// imagens do app e pintados com a cor do texto em volta.
enum PlazvoIcon: String {
    case arrowBack = "icon_arrow_back"
    case check = "icon_check"
    case copy = "icon_content_copy"
    case key = "icon_key"
    case linkOff = "icon_link_off"
    case person = "icon_person"
    case refresh = "icon_refresh"
}

struct IconView: View {
    let icon: PlazvoIcon
    var size: CGFloat = 24

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Marca do Plazvo: o P do logo num quadrado branco arredondado, como o ícone do app.
struct LogoMark: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color.white)
            .frame(width: size, height: size)
            .overlay(
                // O P ocupa 76% da altura do quadrado (ele é mais alto que largo).
                Image("logo_p")
                    .resizable()
                    .scaledToFit()
                    .frame(height: size * 0.76)
            )
            .accessibilityHidden(true)
    }
}

/// O botão responde ao toque ficando mais apagado enquanto está apertado.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Botão redondo só com ícone (barra do alto da tela inicial).
struct RoundIconButton: View {
    let icon: PlazvoIcon
    /// O que o botão faz, para quem usa o leitor de tela.
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon: icon, size: size * 0.5)
                .foregroundColor(PlazvoColors.onSurface)
                .frame(width: size, height: size)
                .background(Circle().fill(PlazvoColors.surface))
                .overlay(Circle().strokeBorder(PlazvoColors.outline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// Botão discreto de copiar (os dois quadradinhos). Logo depois do toque, vira um "certo".
struct CopyButton: View {
    let copied: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon: copied ? .check : .copy, size: 20)
                .foregroundColor(copied ? PlazvoColors.accent : PlazvoColors.onSurfaceMuted)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        // O ícone fica mais perto do canto do painel do que a área de toque deixaria.
        .padding(.trailing, -8)
        .padding(.bottom, -4)
    }
}

/// Painel com o ID e a chave do aparelho, cada um com o botão de copiar.
struct DeviceCodesPanel: View {
    let identity: DeviceIdentity?
    /// Um embaixo do outro e em letras maiores (celular em pé); senão, lado a lado.
    let large: Bool
    /// Qual dos dois acabou de ser copiado.
    let copied: CopyField?
    let onCopy: (CopyField) -> Void

    var body: some View {
        Group {
            if large {
                VStack(alignment: .leading, spacing: 14) {
                    code(.id)
                    code(.key)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    code(.id)
                    Spacer(minLength: 0)
                    code(.key)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(PlazvoColors.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(PlazvoColors.outline, lineWidth: 1))
    }

    private func code(_ field: CopyField) -> some View {
        let value = field == .id ? identity?.id : identity?.key
        let codeStyle = (large ? TextStyle.headlineSmall : TextStyle.titleMedium).weight(.semibold).monospaced()
        return HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(field == .id ? t("device_id_label") : t("device_key_label"))
                    .style(.labelMedium)
                    .foregroundColor(PlazvoColors.onSurfaceMuted)
                Text(value ?? "—")
                    .style(codeStyle)
                    .foregroundColor(PlazvoColors.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .accessibilityElement(children: .combine)
            if large {
                Spacer(minLength: 0)
            }
            if value != nil {
                CopyButton(
                    copied: copied == field,
                    label: field == .id ? t("device_copy_id") : t("device_copy_key"),
                    action: { onCopy(field) }
                )
            }
        }
    }
}

/// Os três botões do aparelho, do mesmo tamanho e lado a lado: Recarregar (o principal, apagado
/// durante a consulta ao servidor), Nova chave e Desconectar do painel.
struct DeviceActionsRow: View {
    let syncing: Bool
    let onReload: () -> Void
    let onNewKey: () -> Void
    let onUnlink: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            DeviceActionButton(
                icon: .refresh,
                text: syncing ? t("playlists_reloading") : t("playlists_reload"),
                primary: true,
                enabled: !syncing,
                action: onReload
            )
            DeviceActionButton(icon: .key, text: t("device_new_key"), action: onNewKey)
            DeviceActionButton(icon: .linkOff, text: t("device_unlink"), action: onUnlink)
        }
        // Os três com a mesma altura, mesmo quando um nome quebra em duas linhas.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Um dos botões do aparelho: ícone em cima, nome embaixo (até duas linhas).
struct DeviceActionButton: View {
    let icon: PlazvoIcon
    let text: String
    var primary = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        // Apagado, o botão continua no lugar; só não faz nada.
        Button(action: { if enabled { action() } }) {
            VStack(spacing: 6) {
                IconView(icon: icon, size: 24)
                Text(text)
                    .style(TextStyle.labelMedium.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundColor(primary ? PlazvoColors.onAccent : PlazvoColors.onSurface)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
            .background(shape.fill(primary ? PlazvoColors.accent : PlazvoColors.surfaceHigh))
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .opacity(enabled ? 1 : 0.55)
    }
}

/// Grupo de linhas: um título pequeno e um painel com uma linha por informação.
struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .style(.labelLarge)
                .foregroundColor(PlazvoColors.accent)
                .padding(.leading, 6)
                .padding(.top, 4)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .background(PlazvoColors.surface)
            .clipShape(shape)
            .overlay(shape.strokeBorder(PlazvoColors.outline, lineWidth: 1))
        }
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(PlazvoColors.outline)
            .frame(height: 1)
    }
}

/// Uma linha de um grupo: nome e, embaixo, o valor ou a explicação. Com `action`, é um botão.
struct SettingRow: View {
    let title: String
    let description: String
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) {
                row
            }
            .buttonStyle(PressStyle())
        } else {
            // Nome e valor formam um item só para o leitor de tela.
            row.accessibilityElement(children: .combine)
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .style(TextStyle.bodyLarge.weight(.medium))
                .foregroundColor(PlazvoColors.onSurface)
            Text(description)
                .style(.bodyMedium)
                .foregroundColor(PlazvoColors.onSurfaceMuted)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }
}

/// O aviso em destaque sobre o fim da ativação ("Seu app vence em menos de 7 dias").
struct ValidityPill: View {
    let text: String
    let expired: Bool

    var body: some View {
        let color = expired ? PlazvoColors.warning : PlazvoColors.expiring
        Text(text)
            .style(TextStyle.bodyMedium.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }
}

/// Aviso curto que aparece embaixo da tela por um instante ("Chave copiada").
struct NoticeView: View {
    let notice: Notice

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        HStack(spacing: 8) {
            if notice.done {
                IconView(icon: .check, size: 18)
                    .foregroundColor(PlazvoColors.accent)
            }
            Text(t(notice.text))
                .style(.labelLarge)
                .foregroundColor(PlazvoColors.onSurface)
                .multilineTextAlignment(.center)
        }
        .padding(.leading, notice.done ? 12 : 16)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .background(shape.fill(PlazvoColors.surfaceHigh))
        .overlay(shape.strokeBorder(PlazvoColors.outline, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 8)
        .padding(.horizontal, 24)
    }
}
