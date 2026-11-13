import PlazvoCore
import SwiftUI
import UIKit

/// O reprodutor em tela cheia: o vídeo, os controles (voltar e avançar 10 segundos, pausar, barra
/// de tempo, legendas, áudio e velocidade) e, quando o vídeo não abre, a mensagem com "Tentar de
/// novo" e "Voltar". Um toque no vídeo mostra ou esconde os controles; com o vídeo rodando, eles
/// somem sozinhos.
///
/// No iPhone a tela acompanha o vídeo: deita com um vídeo deitado e fica em pé com um vídeo
/// gravado em pé. Enquanto o vídeo roda, a tela do aparelho não apaga (quem cuida disso é o motor
/// de vídeo).
struct PlayerScreen: View {
    @ObservedObject var player: PlayerModel
    /// Fecha esta tela.
    let onExit: () -> Void

    var body: some View {
        let state = player.state
        let controls = state.controlsVisible && state.problem == nil
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let surface = player.surface {
                VideoSurface(surface: surface)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            // Um toque no vídeo mostra ou esconde os controles.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { player.controller.tapVideo() }
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(t("player_controls"))
                .accessibilityAddTraits(.isButton)
            if state.waiting && !controls {
                Spinner()
                    .allowsHitTesting(false)
            }
            // Os controles ficam sempre montados (um menu aberto não some com eles); escondidos,
            // não aparecem nem recebem toques.
            PlayerControls(state: state, controller: player.controller)
                .opacity(controls ? 1 : 0)
                .allowsHitTesting(controls)
                .accessibilityHidden(!controls)
            if let problem = state.problem {
                ProblemOverlay(
                    problem: problem,
                    onRetry: { player.controller.retry() },
                    onExit: onExit
                )
            }
            // O nome do vídeo aparece junto com os controles e também com a mensagem de erro.
            if controls || state.problem != nil {
                PlayerTopBar(
                    title: state.title,
                    // A licença do vídeo de demonstração pede o crédito junto com o vídeo.
                    credit: state.kind == .demo ? t("media_demo_credit") : nil,
                    onBack: onExit
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: controls)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { ScreenRotation.follow(portraitVideo: state.portraitVideo) }
        .onChange(of: state.portraitVideo) { portrait in
            ScreenRotation.follow(portraitVideo: portrait)
        }
        .onDisappear { ScreenRotation.release() }
    }
}

/// A área onde o motor de vídeo desenha a imagem.
private struct VideoSurface: UIViewRepresentable {
    let surface: UIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if surface.superview !== container {
            attach(to: container)
        }
    }

    private func attach(to container: UIView) {
        surface.removeFromSuperview()
        surface.frame = container.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(surface)
    }
}

/// A rodinha de espera: o vídeo ainda não chegou.
private struct Spinner: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .tint(Color.white)
            .scaleEffect(1.6)
            .accessibilityLabel(t("player_loading"))
    }
}

/// O nome do vídeo e a seta de voltar, no alto.
private struct PlayerTopBar: View {
    let title: String
    let credit: String?
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                IconView(icon: .arrowBack, size: 24)
                    .foregroundColor(Color.white)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(t("back"))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .style(.titleMedium)
                    .foregroundColor(Color.white)
                    .lineLimit(1)
                if let credit {
                    Text(credit)
                        .style(.bodySmall)
                        .foregroundColor(Color.white.opacity(0.78))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Os controles por cima do vídeo: no meio, voltar 10 segundos, pausar ou continuar e avançar 10
/// segundos; embaixo, a barra de tempo, o tempo, as legendas e as configurações.
private struct PlayerControls: View {
    let state: PlayerState
    let controller: PlayerController

    /// O ponto para onde o usuário está arrastando a barra de tempo (de 0 a 1), enquanto arrasta.
    @State private var scrub: Double?

    var body: some View {
        ZStack {
            // O vídeo escurece um pouco, para os controles aparecerem bem.
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            HStack(spacing: 56) {
                SkipButton(icon: .replay10, label: t("player_rewind"), enabled: state.seekable) {
                    controller.skip(seconds: -PlayerController.skipSeconds)
                }
                Button(action: { controller.togglePlay() }) {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 76, height: 76)
                        .overlay(playMark)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(playLabel)
                SkipButton(icon: .forward10, label: t("player_forward"), enabled: state.seekable) {
                    controller.skip(seconds: PlayerController.skipSeconds)
                }
            }
            VStack(spacing: 10) {
                TimeBar(
                    positionMs: state.positionMs,
                    durationMs: state.durationMs,
                    enabled: state.seekable && state.durationMs > 0,
                    scrub: $scrub,
                    onScrub: { controller.keepControls() },
                    onSeek: { controller.seek(toMs: $0) },
                    onStep: { controller.skip(seconds: $0) }
                )
                HStack(spacing: 0) {
                    Text(ScreenTexts.playerTime(positionMs: shownPositionMs, durationMs: state.durationMs))
                        .style(.labelLarge)
                        .foregroundColor(Color.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !state.subtitleTracks.isEmpty {
                        subtitlesMenu
                    }
                    settingsMenu
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// O desenho do botão do meio: a rodinha enquanto o vídeo não chega; senão, o que o toque faz.
    @ViewBuilder
    private var playMark: some View {
        if state.waiting {
            Spinner()
        } else {
            IconView(icon: playIcon, size: 52)
                .foregroundColor(Color.white)
        }
    }

    private var playIcon: PlazvoIcon {
        switch state.status {
        case .ended: return .replay
        case .paused: return .playArrow
        case .opening, .buffering, .playing: return .pause
        }
    }

    private var playLabel: String {
        switch state.status {
        case .ended: return t("player_replay")
        case .paused: return t("player_play")
        case .opening, .buffering, .playing: return t("player_pause")
        }
    }

    /// O ponto que o tempo embaixo da barra mostra: durante o arrasto, o do dedo.
    private var shownPositionMs: Int64 {
        guard let scrub, state.durationMs > 0 else { return state.positionMs }
        return Int64((scrub * Double(state.durationMs)).rounded())
    }

    private var subtitlesMenu: some View {
        Menu {
            Button(action: { controller.selectSubtitle(nil) }) {
                MenuOption(text: t("player_subtitles_off"), selected: state.subtitleTrack == nil)
            }
            ForEach(state.subtitleTracks, id: \.id) { track in
                Button(action: { controller.selectSubtitle(track.id) }) {
                    MenuOption(text: track.name, selected: state.subtitleTrack == track.id)
                }
            }
        } label: {
            ControlIcon(icon: .closedCaption)
        }
        .accessibilityLabel(t("player_subtitles"))
    }

    private var settingsMenu: some View {
        Menu {
            Menu(t("player_speed")) {
                ForEach(PlayerController.rates, id: \.self) { rate in
                    Button(action: { controller.setRate(rate) }) {
                        MenuOption(text: ScreenTexts.rateLabel(rate) ?? t("player_speed_normal"), selected: state.rate == rate)
                    }
                }
            }
            if state.audioTracks.count > 1 {
                Menu(t("player_audio")) {
                    ForEach(state.audioTracks, id: \.id) { track in
                        Button(action: { controller.selectAudio(track.id) }) {
                            MenuOption(text: track.name, selected: state.audioTrack == track.id)
                        }
                    }
                }
            }
        } label: {
            ControlIcon(icon: .settings)
        }
        .accessibilityLabel(t("player_settings"))
    }
}

/// Uma opção de um menu do reprodutor, com o sinal de "certo" na que está valendo.
private struct MenuOption: View {
    let text: String
    let selected: Bool

    var body: some View {
        if selected {
            Label(text, systemImage: "checkmark")
        } else {
            Text(text)
        }
    }
}

/// Um ícone da linha de baixo dos controles (legendas, configurações).
private struct ControlIcon: View {
    let icon: PlazvoIcon

    var body: some View {
        IconView(icon: icon, size: 24)
            .foregroundColor(Color.white)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// Botão de voltar ou avançar 10 segundos. Apagado quando o vídeo não deixa ir a outro ponto.
private struct SkipButton: View {
    let icon: PlazvoIcon
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            IconView(icon: icon, size: 40)
                .foregroundColor(Color.white)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .opacity(enabled ? 1 : 0.38)
        .accessibilityLabel(label)
    }
}

/// A barra de tempo: quanto do vídeo já passou e, com o dedo, para onde ir. Só quando o dedo
/// solta é que o vídeo vai para o ponto escolhido.
private struct TimeBar: View {
    let positionMs: Int64
    let durationMs: Int64
    /// O vídeo deixa ir a outro ponto e a duração é conhecida.
    let enabled: Bool
    @Binding var scrub: Double?
    /// O usuário está mexendo na barra.
    let onScrub: () -> Void
    let onSeek: (Int64) -> Void
    /// Volta ou avança tantos segundos (para quem usa o leitor de tela).
    let onStep: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let played = width * CGFloat(fraction)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: width, height: 4)
                Capsule()
                    .fill(PlazvoColors.accent)
                    .frame(width: played, height: 4)
                if enabled {
                    Circle()
                        .fill(PlazvoColors.accent)
                        .frame(width: 14, height: 14)
                        .offset(x: played - 7)
                }
            }
            .frame(width: width, height: 28, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard enabled, width > 0 else { return }
                        scrub = Double(min(max(drag.location.x / width, 0), 1))
                        onScrub()
                    }
                    .onEnded { drag in
                        defer { scrub = nil }
                        guard enabled, width > 0 else { return }
                        let chosen = Double(min(max(drag.location.x / width, 0), 1))
                        onSeek(Int64((chosen * Double(durationMs)).rounded()))
                    }
            )
        }
        .frame(height: 28)
        .accessibilityElement()
        .accessibilityLabel(t("player_position"))
        .accessibilityValue(ScreenTexts.playerTime(positionMs: positionMs, durationMs: durationMs))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            onStep(direction == .increment ? PlayerController.skipSeconds : -PlayerController.skipSeconds)
        }
    }

    /// A parte do vídeo que já passou, de 0 a 1 (durante o arrasto, a do dedo).
    private var fraction: Double {
        if let scrub { return scrub }
        guard durationMs > 0 else { return 0 }
        return min(max(Double(positionMs) / Double(durationMs), 0), 1)
    }
}

/// Mensagem de falha por cima do vídeo, com "Tentar de novo" e "Voltar".
private struct ProblemOverlay: View {
    let problem: PlaybackProblem
    let onRetry: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(t(problem.message))
                .style(.titleMedium)
                .foregroundColor(Color.white)
                .multilineTextAlignment(.center)
            Text(t("player_error_code", String(problem.code)))
                .style(.bodySmall)
                .foregroundColor(PlazvoColors.onSurfaceMuted)
                .padding(.top, 6)
            HStack(spacing: 12) {
                OverlayButton(text: t("player_retry"), action: onRetry)
                OverlayButton(text: t("back"), action: onExit)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.86)
                .ignoresSafeArea()
        )
    }
}

/// Botão comprido de cantos redondos das mensagens por cima do vídeo.
private struct OverlayButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .style(.labelLarge)
                .foregroundColor(PlazvoColors.onSurface)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(PlazvoColors.surfaceHigh))
                .overlay(Capsule().strokeBorder(PlazvoColors.outline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}
