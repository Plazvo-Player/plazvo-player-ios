import PlazvoCore
import SwiftUI
import UIKit

/// A janela do app: o fundo, a tela aberta (inicial ou Conta), a caixa por cima dela e o aviso curto.
struct RootView: View {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Backdrop()
            // As telas não se mexem quando o teclado abre; só a caixa do código sobe.
            GeometryReader { proxy in
                screens(window: windowSize(proxy))
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            dialog
            notice
        }
        .animation(.easeInOut(duration: 0.25), value: model.state.screen)
        .animation(.easeOut(duration: 0.15), value: model.state.dialog)
        .animation(.easeOut(duration: 0.2), value: model.state.notice)
        .preferredColorScheme(.dark)
        .task {
            await model.start()
        }
        .onChange(of: scenePhase) { phase in
            // Ao voltar para o app: se a ativação venceu com ele aberto, a tela mostra.
            if phase == .active { model.app.checkExpiry() }
        }
        .onChange(of: model.state.notice) { notice in
            // O leitor de tela também diz o aviso.
            if let notice {
                UIAccessibility.post(notification: .announcement, argument: t(notice.text))
            }
        }
    }

    /// O tamanho da janela inteira (com as margens de segurança), que escolhe o arranjo das telas.
    private func windowSize(_ proxy: GeometryProxy) -> CGSize {
        let insets = proxy.safeAreaInsets
        return CGSize(
            width: proxy.size.width + insets.leading + insets.trailing,
            height: proxy.size.height + insets.top + insets.bottom
        )
    }

    private func screens(window: CGSize) -> some View {
        let onAccount = model.state.screen == .account
        return ZStack {
            HomeScreen(model: model, window: window)
                // Com a Conta por cima, a tela inicial não recebe toques nem é lida.
                .allowsHitTesting(!onAccount)
                .accessibilityHidden(onAccount)
            if onAccount {
                AccountScreen(model: model, window: window)
                    .background(Backdrop())
                    .overlay(BackSwipeEdge(action: { model.app.back() }), alignment: .leading)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private var dialog: some View {
        switch model.state.dialog {
        case .some(.code):
            ActivationCodeDialog(
                initialCode: model.typedCode,
                sending: model.state.activating,
                error: codeError,
                onActivate: { model.activate($0) },
                onDismiss: { model.app.closeDialog() }
            )
            .transition(.opacity)
            .zIndex(2)
        case .some(.newKey):
            NewKeyDialog(
                onConfirm: { model.confirmNewKey() },
                onDismiss: { model.app.closeDialog() }
            )
            .transition(.opacity)
            .zIndex(2)
        case .some(.unlink):
            UnlinkDialog(
                partner: model.state.site.partner,
                unlinking: model.state.unlinking,
                result: model.state.unlinkResult,
                onConfirm: { model.unlink() },
                onDismiss: { model.app.closeDialog() }
            )
            .transition(.opacity)
            .zIndex(2)
        case .none:
            EmptyView()
        }
    }

    /// O aviso do último código que não ativou o aparelho.
    private var codeError: String? {
        guard let result = model.state.codeResult, let problem = ScreenTexts.codeProblem(result) else { return nil }
        return t(problem)
    }

    @ViewBuilder
    private var notice: some View {
        if let notice = model.state.notice {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                NoticeView(notice: notice)
            }
            .padding(.bottom, 40)
            .allowsHitTesting(false)
            .transition(.opacity)
            .zIndex(3)
        }
    }
}

/// O gesto de voltar do iPhone: arrastar da borda esquerda da tela para a direita.
private struct BackSwipeEdge: View {
    let action: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12).onEnded { drag in
                    if drag.translation.width > 60, abs(drag.translation.height) < 80 { action() }
                }
            )
            .ignoresSafeArea(.container, edges: .leading)
            .frame(width: 20)
            // Abaixo da seta de voltar, para não tomar o toque dela.
            .padding(.top, 64)
            .accessibilityHidden(true)
    }
}
