import PlazvoCore
import SwiftUI

/// Caixa por cima da tela (um fundo escurecido e um cartão no meio), igual à do app Android.
/// Tocar fora do cartão fecha. Se o cartão não couber (teclado aberto, tela deitada), ele rola.
struct OverlayDialog<Content: View, Buttons: View>: View {
    let title: String
    let onDismiss: () -> Void
    let content: Content
    let buttons: Buttons

    init(
        title: String,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder buttons: () -> Buttons
    ) {
        self.title = title
        self.onDismiss = onDismiss
        self.content = content()
        self.buttons = buttons()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    card
                        .padding(24)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { onDismiss() }
                }
            }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .style(TextStyle.titleLarge.weight(.semibold))
                .foregroundColor(PlazvoColors.onSurface)
                .accessibilityAddTraits(.isHeader)
            content
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                buttons
            }
            .padding(.top, 16)
        }
        .padding(22)
        .frame(maxWidth: 420, alignment: .leading)
        .background(shape.fill(PlazvoColors.surface))
        .overlay(shape.strokeBorder(PlazvoColors.outline, lineWidth: 1))
        .contentShape(shape)
        // O cartão não fecha ao ser tocado.
        .onTapGesture {}
        .accessibilityAddTraits(.isModal)
    }
}

/// Botão de texto das caixas (Cancelar, Ativar…).
struct DialogButton: View {
    let text: String
    /// O botão que confirma sai na cor de destaque.
    var accent = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .style(.labelLarge)
                .foregroundColor(accent ? PlazvoColors.accent : PlazvoColors.onSurfaceMuted)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
    }
}

/// O texto de uma caixa de pergunta.
struct DialogText: View {
    let text: String

    var body: some View {
        Text(text)
            .style(.bodyMedium)
            .foregroundColor(PlazvoColors.onSurface)
            .padding(.top, 10)
    }
}

/// Aviso de erro dentro de uma caixa.
struct ErrorText: View {
    let text: String

    var body: some View {
        Text(text)
            .style(.bodyMedium)
            .foregroundColor(PlazvoColors.warning)
            .padding(.top, 8)
    }
}

/// O campo do código de ativação: o contorno, o nome que fica na borda e os traços, que aparecem
/// sozinhos enquanto a pessoa digita ("ABCD-EFGH-JKMN").
private struct CodeField: View {
    /// Só as letras e os números (até 12), em maiúsculas.
    @Binding var code: String
    let enabled: Bool
    let onSubmit: () -> Void

    /// O que o campo mostra: o código com os traços.
    @State private var shown: String
    @FocusState private var focused: Bool

    init(code: Binding<String>, enabled: Bool, onSubmit: @escaping () -> Void) {
        _code = code
        self.enabled = enabled
        self.onSubmit = onSubmit
        _shown = State(initialValue: formattedActivationCode(code.wrappedValue))
    }

    var body: some View {
        // O nome fica na borda quando o campo está em uso ou tem algo escrito.
        let raised = focused || !shown.isEmpty
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(focused ? PlazvoColors.accent : PlazvoColors.outline, lineWidth: focused ? 2 : 1)
            if focused && shown.isEmpty {
                Text(verbatim: "ABCD-EFGH-JKMN")
                    .style(.bodyLarge)
                    .foregroundColor(PlazvoColors.onSurfaceMuted)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .accessibilityHidden(true)
            }
            TextField("", text: $shown)
                .font(TextStyle.bodyLarge.font)
                .foregroundColor(PlazvoColors.onSurface)
                .tint(PlazvoColors.accent)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { onSubmit() }
                .disabled(!enabled)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .accessibilityLabel(t("code_field"))
            Text(t("code_field"))
                .style(raised ? .bodySmall : .bodyLarge)
                .foregroundColor(focused ? PlazvoColors.accent : PlazvoColors.onSurfaceMuted)
                .padding(.horizontal, raised ? 4 : 0)
                .background(raised ? PlazvoColors.surface : Color.clear)
                .offset(x: raised ? 12 : 16, y: raised ? -8 : 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: 56)
        .onChange(of: shown) { text in
            // Fica só o código em si; traços e espaços colados junto são ignorados, e o que
            // passar de 12 não entra.
            let clean = acceptedActivationCodeInput(text) ?? code
            if clean != code { code = clean }
            let formatted = formattedActivationCode(clean)
            if formatted != text { shown = formatted }
        }
        .task {
            // Abre já pronto para digitar (logo depois de a caixa aparecer).
            try? await Task.sleep(nanoseconds: 350_000_000)
            if enabled { focused = true }
        }
        .onChange(of: enabled) { enabled in
            // Depois de um código que não ativou, o campo volta pronto para a correção.
            if enabled { focused = true }
        }
    }
}

/// Caixa de Conta › "Tenho um código de ativação": o usuário digita o código que recebeu e o app
/// manda ao servidor. `error` é o aviso da última tentativa; enquanto `sending`, o botão espera.
struct ActivationCodeDialog: View {
    let sending: Bool
    let error: String?
    let onActivate: (String) -> Void
    let onDismiss: () -> Void

    @State private var code: String
    @State private var tooShort = false

    init(
        initialCode: String,
        sending: Bool,
        error: String?,
        onActivate: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.sending = sending
        self.error = error
        self.onActivate = onActivate
        self.onDismiss = onDismiss
        _code = State(initialValue: initialCode)
    }

    var body: some View {
        OverlayDialog(title: t("code_title"), onDismiss: onDismiss) {
            Text(t("code_hint"))
                .style(.bodyMedium)
                .foregroundColor(PlazvoColors.onSurfaceMuted)
                .padding(.top, 8)
            CodeField(code: $code, enabled: !sending, onSubmit: { send() })
                .padding(.top, 20)
            if tooShort {
                ErrorText(text: t("code_incomplete"))
            } else if let error {
                ErrorText(text: error)
            }
        } buttons: {
            DialogButton(text: t("cancel"), action: onDismiss)
            DialogButton(
                text: sending ? t("code_sending") : t("code_activate"),
                accent: true,
                enabled: !sending,
                action: { send() }
            )
        }
        .onChange(of: code) { _ in
            tooShort = false
        }
    }

    private func send() {
        guard !sending else { return }
        if code.count == activationCodeLength {
            onActivate(code)
        } else {
            tooShort = true
        }
    }
}

/// "Gerar uma nova chave?": a chave atual deixa de valer; o resto continua como está.
struct NewKeyDialog: View {
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        OverlayDialog(title: t("new_key_title"), onDismiss: onDismiss) {
            DialogText(text: t("new_key_text"))
        } buttons: {
            DialogButton(text: t("cancel"), action: onDismiss)
            DialogButton(text: t("new_key_confirm"), accent: true, action: onConfirm)
        }
    }
}

/// "Desconectar do painel?": explica o que muda e pede confirmação; mostra "Desconectando…"
/// durante o pedido e, no fim, o resultado com o botão Fechar. Aparelho que o servidor disse não
/// estar em nenhum painel: só o aviso e Fechar.
struct UnlinkDialog: View {
    /// Um parceiro cuida do aparelho? `nil`: o servidor não disse.
    let partner: Bool?
    let unlinking: Bool
    let result: UnlinkResult?
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let result {
            closeOnly(t(ScreenTexts.unlinkResult(result)))
        } else if partner == false {
            closeOnly(t("unlink_not_linked"))
        } else {
            OverlayDialog(title: t("unlink_title"), onDismiss: onDismiss) {
                DialogText(text: t("unlink_text"))
            } buttons: {
                DialogButton(text: t("cancel"), enabled: !unlinking, action: onDismiss)
                DialogButton(
                    text: unlinking ? t("unlink_sending") : t("unlink_confirm"),
                    accent: true,
                    enabled: !unlinking,
                    action: onConfirm
                )
            }
        }
    }

    private func closeOnly(_ text: String) -> some View {
        OverlayDialog(title: t("unlink_title"), onDismiss: onDismiss) {
            DialogText(text: text)
        } buttons: {
            DialogButton(text: t("close"), accent: true, action: onDismiss)
        }
    }
}
