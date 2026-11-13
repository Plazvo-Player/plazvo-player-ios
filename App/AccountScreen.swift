import PlazvoCore
import SwiftUI

/// Conta: o ID e a chave deste aparelho, até quando ele está ativo e os três botões do aparelho.
/// Aparelho que não está ativo tem "Tenho um código de ativação", que abre a caixa do código.
struct AccountScreen: View {
    @ObservedObject var model: AppModel
    /// O tamanho da janela, que escolhe o arranjo.
    let window: CGSize

    var body: some View {
        let wide = ScreenLayout.isWide(width: window.width, height: window.height)
        let site = model.state.site
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: t("home_account"), onBack: { model.app.back() })
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    DeviceCodesPanel(
                        identity: model.state.identity,
                        large: !wide,
                        copied: model.state.copied,
                        onCopy: { model.app.copy($0) }
                    )
                    SettingsGroup(title: t("account_device")) {
                        SettingRow(title: t("account_status"), description: statusText(site))
                        if let problem = ScreenTexts.problem(site) {
                            RowDivider()
                            SettingRow(title: t("account_last_check"), description: t(problem))
                        }
                        if let activated = activatedText {
                            RowDivider()
                            SettingRow(title: t("code_title"), description: activated)
                        }
                        if site.status != .active && site.status != .blocked {
                            RowDivider()
                            SettingRow(
                                title: t("code_row"),
                                description: t("code_row_description"),
                                action: { model.app.openCodeDialog() }
                            )
                        }
                    }
                    DeviceActionsRow(
                        syncing: site.syncing,
                        onReload: { model.reload() },
                        onNewKey: { model.app.openNewKeyDialog() },
                        onUnlink: { model.app.openUnlinkDialog() }
                    )
                }
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// "Ativo até 02/10/2027" (ou "Ativo por parceiro"), ou a frase sobre a situação do aparelho.
    private func statusText(_ site: SiteListsState) -> String {
        if let until = ScreenTexts.activeUntil(site, datePattern: t("playlists_date_pattern")) { return t(until) }
        if let status = ScreenTexts.status(site) { return t(status) }
        return t("playlists_loading")
    }

    /// "Aparelho ativado por 30 dias.", depois de um código aceito (sem os dias se o aparelho está
    /// ativo por uma parceria).
    private var activatedText: String? {
        guard case .activated(let days)? = model.state.codeResult else { return nil }
        return t(ScreenTexts.activated(days: days, sponsored: model.state.site.sponsored))
    }
}
