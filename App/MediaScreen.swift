import PlazvoCore
import SwiftUI

/// Mídia: procurar um vídeo no aparelho, abrir um link, ver o vídeo de demonstração e voltar aos
/// vídeos recentes. Em pé, em lista; na tela larga (deitado, iPad), lado a lado.
struct MediaScreen: View {
    @ObservedObject var model: AppModel
    /// O tamanho da janela, que escolhe o arranjo.
    let window: CGSize

    /// O seletor de arquivos do sistema está aberto.
    @State private var picking = false

    var body: some View {
        Group {
            if ScreenLayout.isWide(width: window.width, height: window.height) {
                wide
            } else {
                tall
            }
        }
        // O seletor de arquivos do sistema: não pede permissão para ver os arquivos do aparelho;
        // o app só recebe o arquivo que o usuário escolher.
        .fileImporter(isPresented: $picking, allowedContentTypes: DeviceMediaAccess.videoTypes) { result in
            if case .success(let url) = result {
                model.pickedFile(url)
            }
        }
    }

    private var tall: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: t("home_media"), onBack: { model.app.back() })
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ActionCard(
                        icon: .folder,
                        title: t("media_pick_file"),
                        description: t("media_pick_file_description"),
                        action: { picking = true }
                    )
                    ActionCard(
                        icon: .link,
                        title: t("media_open_link"),
                        description: t("media_open_link_description"),
                        action: { model.app.openLinkScreen() }
                    )
                    ActionCard(
                        icon: .playArrow,
                        title: t("media_demo"),
                        description: t("media_demo_description"),
                        action: { model.playDemo() }
                    )
                    if !model.state.recents.isEmpty {
                        RecentsHeader(onClear: { model.app.clearRecents() })
                        ForEach(Array(model.state.recents.enumerated()), id: \.offset) { _, item in
                            RecentCard(item: item, compact: false, action: { model.app.openRecent(item) })
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Tela larga: os três caminhos lado a lado e os recentes numa fila que desliza para o lado.
    private var wide: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: t("home_media"), onBack: { model.app.back() })
            HStack(spacing: 12) {
                TileCard(
                    icon: .folder,
                    title: t("media_pick_file"),
                    description: t("media_pick_file_description"),
                    action: { picking = true }
                )
                TileCard(
                    icon: .link,
                    title: t("media_open_link"),
                    description: t("media_open_link_description"),
                    action: { model.app.openLinkScreen() }
                )
                TileCard(
                    icon: .playArrow,
                    title: t("media_demo"),
                    description: t("media_demo_description"),
                    action: { model.playDemo() }
                )
            }
            .padding(.vertical, 8)
            // Os blocos crescem com a tela até certa altura e ficam no meio do espaço que sobra.
            .frame(maxHeight: 236)
            .frame(maxHeight: .infinity)
            if !model.state.recents.isEmpty {
                RecentsHeader(onClear: { model.app.clearRecents() })
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(model.state.recents.enumerated()), id: \.offset) { _, item in
                            RecentCard(item: item, compact: true, action: { model.app.openRecent(item) })
                                .frame(width: 240)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// "Recentes" e, do outro lado, "Limpar".
private struct RecentsHeader: View {
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(t("media_recents"))
                .style(TextStyle.titleMedium.weight(.semibold))
                .foregroundColor(PlazvoColors.onSurface)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: onClear) {
                Text(t("media_recents_clear"))
                    .style(.labelLarge)
                    .foregroundColor(PlazvoColors.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }
}

/// Um vídeo recente: nome, de onde veio e quanto já foi assistido. Tocar continua de onde parou.
/// Com `compact` (cartão estreito), mostra só o tempo assistido ou, se não houver, de onde veio.
private struct RecentCard: View {
    let item: RecentMedia
    let compact: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let progress = ScreenTexts.recentProgress(item, pattern: t("media_recent_progress"))
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .style(TextStyle.titleSmall.weight(.semibold))
                    .foregroundColor(PlazvoColors.onSurface)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !compact || progress == nil {
                        // De um link, só o nome do servidor aparece (o endereço pode ter senha).
                        Text(t(ScreenTexts.recentSource(item)))
                            .style(.bodySmall)
                            .foregroundColor(PlazvoColors.onSurfaceMuted)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let progress {
                        Text(progress)
                            .style(.bodySmall)
                            .foregroundColor(PlazvoColors.onSurfaceMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if let watched = item.progress {
                    ProgressBar(value: watched)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(PlazvoColors.surface))
            .overlay(shape.strokeBorder(PlazvoColors.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
    }
}
