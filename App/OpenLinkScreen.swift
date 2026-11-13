import PlazvoCore
import SwiftUI
import UIKit

/// Abrir link de vídeo: um campo para colar ou digitar o endereço. Abre já pronto para digitar.
/// Se o último endereço tentado não chegou a tocar, ele volta ao campo, para corrigir sem digitar
/// tudo de novo; o que tocou não volta (está na lista de recentes, sem o endereço à mostra).
struct OpenLinkScreen: View {
    @ObservedObject var model: AppModel

    @State private var text: String
    @FocusState private var focused: Bool

    init(model: AppModel) {
        self.model = model
        _text = State(initialValue: model.typedLink.isEmpty ? model.app.lastLink : model.typedLink)
    }

    var body: some View {
        let invalid = model.state.linkInvalid
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: t("media_open_link"), onBack: { model.app.back() })
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    LinkField(text: $text, invalid: invalid, focused: $focused, onSubmit: { open() })
                        // Espaço para o nome do campo, que fica em cima da borda.
                        .padding(.top, 6)
                    // A dica de preenchimento ou, depois de um endereço errado, o aviso.
                    Text(invalid ? t("link_invalid") : t("link_hint"))
                        .style(.bodyMedium)
                        .foregroundColor(invalid ? PlazvoColors.warning : PlazvoColors.onSurfaceMuted)
                    HStack(spacing: 12) {
                        OutlinedButton(text: t("link_paste"), action: { paste() })
                        FilledButton(text: t("link_open"), action: { open() })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: text) { changed in
            // Um texto enorme colado por engano não fica no campo (travaria a tela).
            if changed.utf8.count > VideoLink.maxLength {
                text = VideoLink.fitted(changed)
                return
            }
            // Mexeu no campo: o aviso de endereço errado some.
            if model.state.linkInvalid { model.app.linkEdited() }
        }
        .task {
            // Abre já pronto para digitar (logo depois de a tela entrar).
            try? await Task.sleep(nanoseconds: 350_000_000)
            focused = true
        }
    }

    private func open() {
        model.app.openLink(text)
    }

    /// Botão Colar: põe no campo o texto que está na área de transferência.
    private func paste() {
        guard let copied = UIPasteboard.general.string else { return }
        let pasted = VideoLink.fitted(copied).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.isEmpty else { return }
        text = pasted
        focused = true
    }
}

/// O campo do endereço: o contorno, o nome que fica na borda e o botão de apagar. O "ir" do
/// teclado abre o vídeo.
private struct LinkField: View {
    @Binding var text: String
    let invalid: Bool
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        let active = focused.wrappedValue
        // O nome fica na borda quando o campo está em uso ou tem algo escrito.
        let raised = active || !text.isEmpty
        let line = invalid ? PlazvoColors.warning : (active ? PlazvoColors.accent : PlazvoColors.outline)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(line, lineWidth: active || invalid ? 2 : 1)
                // A borda abre um vão onde fica o nome do campo (o fundo da tela aparece nele).
                .mask(
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                        if raised {
                            // O vão tem o tamanho e o lugar do nome (com a folga dos lados dele).
                            name(raised: true, color: Color.black, patch: Color.black)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                )
            if active && text.isEmpty {
                Text(verbatim: "http://")
                    .style(.bodyLarge)
                    .foregroundColor(PlazvoColors.onSurfaceMuted)
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 0) {
                TextField("", text: $text)
                    .font(TextStyle.bodyLarge.font)
                    .foregroundColor(PlazvoColors.onSurface)
                    .tint(PlazvoColors.accent)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused(focused)
                    .onSubmit { onSubmit() }
                    .padding(.leading, 16)
                    .padding(.trailing, text.isEmpty ? 16 : 0)
                    .frame(height: 56)
                    .accessibilityLabel(t("link_field_label"))
                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        IconView(icon: .clear, size: 24)
                            .foregroundColor(invalid ? PlazvoColors.warning : PlazvoColors.onSurfaceMuted)
                            .frame(width: 48, height: 56)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(t("link_clear"))
                }
            }
            name(raised: raised, color: invalid ? PlazvoColors.warning : (active ? PlazvoColors.accent : PlazvoColors.onSurfaceMuted))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: 56)
    }

    /// O nome do campo: dentro dele, em letra grande, ou em cima da borda, em letra pequena.
    /// - Parameter patch: a cor de fundo do nome (só no molde do vão da borda). Entra antes do
    ///   deslocamento, para ir junto com o nome.
    private func name(raised: Bool, color: Color, patch: Color = Color.clear) -> some View {
        Text(t("link_field_label"))
            .style(raised ? .bodySmall : .bodyLarge)
            .foregroundColor(color)
            .padding(.horizontal, raised ? 4 : 0)
            .background(patch)
            .offset(x: raised ? 12 : 16, y: raised ? -8 : 16)
    }
}
