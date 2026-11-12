import PlazvoCore
import SwiftUI

/// Tela inicial da versão 0.1: a barra com a marca, a hora, a data e o botão
/// Conta; a situação do aparelho; o ID e a chave em destaque; os três botões do aparelho; e o
/// rodapé com a validade e a versão.
///
/// - Tela estreita (celular em pé) e média (tablet em pé): a barra em duas linhas e o ID e a
///   chave um embaixo do outro, em letras maiores.
/// - Tela larga (deitado, tablet grande): a barra numa linha só e o ID e a chave lado a lado.
struct HomeScreen: View {
    @ObservedObject var model: AppModel
    /// O tamanho da janela, que escolhe o arranjo.
    let window: CGSize

    var body: some View {
        let wide = ScreenLayout.home(width: window.width, height: window.height) == .wide
        let site = model.state.site
        VStack(alignment: .leading, spacing: 0) {
            // Refaz a barra a cada minuto, para a hora andar.
            TimelineView(.everyMinute) { tick in
                HomeHeader(
                    wide: wide,
                    narrow: !wide && ScreenLayout.isNarrowHeader(width: window.width),
                    clock: model.clockText(at: tick.date),
                    onAccount: { model.app.openAccount() }
                )
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let status = ScreenTexts.status(site) {
                        Text(t(status))
                            .style(.bodyLarge)
                            .foregroundColor(PlazvoColors.onSurfaceMuted)
                    }
                    if let problem = ScreenTexts.problem(site) {
                        Text(t(problem))
                            .style(.bodyMedium)
                            .foregroundColor(PlazvoColors.onSurfaceMuted)
                    }
                    DeviceCodesPanel(
                        identity: model.state.identity,
                        large: !wide,
                        copied: model.state.copied,
                        onCopy: { model.app.copy($0) }
                    )
                    DeviceActionsRow(
                        syncing: site.syncing,
                        onReload: { model.reload() },
                        onNewKey: { model.app.openNewKeyDialog() },
                        onUnlink: { model.app.openUnlinkDialog() }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            HomeFooter(site: site, now: model.now, version: model.version)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: wide ? 1100 : 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Barra do alto: marca, nome, hora e data, e o botão Conta.
private struct HomeHeader: View {
    let wide: Bool
    /// Celular estreito: o logo, o nome e o botão um pouco menores, para o nome não ser cortado.
    let narrow: Bool
    let clock: ClockText
    let onAccount: () -> Void

    var body: some View {
        if wide {
            HStack(spacing: 0) {
                LogoMark(size: 40)
                Text(t("app_name"))
                    .style(TextStyle.titleLarge.weight(.bold))
                    .foregroundColor(PlazvoColors.onSurface)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, 12)
                // A hora e, embaixo, a data numa linha só, no espaço entre o nome e o botão.
                VStack(alignment: .trailing, spacing: 0) {
                    ClockTime(text: clock.time)
                    ClockDate(text: clock.date, singleLine: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                RoundIconButton(icon: .person, label: t("home_account"), size: 44, action: onAccount)
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    LogoMark(size: narrow ? 32 : 36)
                    Text(t("app_name"))
                        .style((narrow ? TextStyle.titleMedium : TextStyle.titleLarge).weight(.bold))
                        .foregroundColor(PlazvoColors.onSurface)
                        .lineLimit(1)
                        .padding(.leading, 10)
                    Spacer(minLength: 8)
                    RoundIconButton(icon: .person, label: t("home_account"), size: narrow ? 38 : 42, action: onAccount)
                }
                HStack(spacing: 10) {
                    ClockTime(text: clock.time)
                    ClockDate(text: clock.date, singleLine: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.top, 6)
            }
        }
    }
}

/// A hora, como "02:35 PM".
private struct ClockTime: View {
    let text: String

    var body: some View {
        Text(text)
            .style(TextStyle.titleMedium.weight(.semibold))
            .foregroundColor(PlazvoColors.onSurface)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A data por extenso, como "Sexta-feira, 02 de Outubro de 2026", alinhada ao fim da linha.
/// Com `singleLine`, nunca quebra: se não couber, a letra diminui.
private struct ClockDate: View {
    let text: String
    let singleLine: Bool

    var body: some View {
        Text(text)
            .style(.labelMedium)
            .foregroundColor(PlazvoColors.onSurfaceMuted)
            .multilineTextAlignment(.trailing)
            .lineLimit(singleLine ? 1 : 2)
            .minimumScaleFactor(singleLine ? 0.75 : 1)
    }
}

/// Rodapé: o aviso de vencimento (quando falta pouco ou já venceu), "Ativo até dd/mm/aaaa" e a versão.
private struct HomeFooter: View {
    let site: SiteListsState
    let now: Date
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let warning = Validity.warning(site, now: now) {
                ValidityPill(text: t(ScreenTexts.validityWarning(warning)), expired: warning == .expired)
            }
            HStack(alignment: .center, spacing: 12) {
                Text(activeUntil)
                    .style(.bodyMedium)
                    .foregroundColor(PlazvoColors.onSurfaceMuted)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(t("version_short", version) + " · " + t("site"))
                    .style(.labelMedium)
                    .foregroundColor(PlazvoColors.onSurfaceMuted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.top, 6)
    }

    private var activeUntil: String {
        guard let text = ScreenTexts.activeUntil(site, datePattern: t("playlists_date_pattern")) else { return "" }
        return t(text)
    }
}
