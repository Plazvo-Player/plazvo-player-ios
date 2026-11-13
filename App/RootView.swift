import PlazvoCore
import SwiftUI
import UIKit

/// A janela do app: o fundo, a tela aberta (inicial, Conta, Mídia ou Abrir link), a caixa por cima
/// dela, o aviso curto e, por cima de tudo, o reprodutor do vídeo aberto.
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
            // Com o vídeo por cima, as telas não são lidas.
            .accessibilityHidden(model.player != nil)
            dialog
            notice
            if let player = model.player {
                // Entrar e sair do vídeo é imediato, sem animação.
                PlayerScreen(player: player, onExit: { model.app.closePlayer() })
                    .transition(.identity)
                    .zIndex(4)
            }
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
            // Ao sair do app: o vídeo pausa e o ponto dele fica guardado.
            if phase == .background { model.app.player?.enterBackground() }
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
        let screen = model.state.screen
        let onMedia = screen == .media || screen == .openLink
        return ZStack {
            HomeScreen(model: model, window: window)
                // Com outra tela por cima, a tela inicial não recebe toques nem é lida.
                .allowsHitTesting(screen == .home)
                .accessibilityHidden(screen != .home)
            if screen == .account {
                AccountScreen(model: model, window: window)
                    .background(Backdrop())
                    .overlay(BackSwipeEdge(action: { model.app.back() }), alignment: .leading)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
            if onMedia {
                // A Mídia continua embaixo de "Abrir link", que entra por cima dela.
                MediaScreen(model: model, window: window)
                    .allowsHitTesting(screen == .media)
                    .accessibilityHidden(screen != .media)
                    .background(Backdrop())
                    .overlay(BackSwipeEdge(action: { model.app.back() }), alignment: .leading)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
            if screen == .openLink {
                OpenLinkScreen(model: model)
                    .background(Backdrop())
                    .overlay(BackSwipeEdge(action: { model.app.back() }), alignment: .leading)
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
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
