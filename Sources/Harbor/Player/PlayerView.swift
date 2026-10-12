import SwiftUI
import UIKit

/// Shows mpv's video layer inside SwiftUI.
struct MPVVideoView: UIViewControllerRepresentable {
    let model: PlayerModel

    func makeUIViewController(context: Context) -> MPVViewController {
        let player = model
        let vc = MPVViewController(core: player.core, options: player.options)
        vc.onReady = { [weak player] in player?.ready() }
        vc.onStartError = { [weak player] msg in player?.startFailed(msg) }
        return vc
    }

    func updateUIViewController(_ uiViewController: MPVViewController, context: Context) {}
}

struct PlayerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PlayerModel

    @State private var controlsVisible = true
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hideTask: Task<Void, Never>?
    @State private var seekFlash: String?

    init(item: PlayItem) {
        _model = StateObject(wrappedValue: PlayerModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MPVVideoView(model: model)
                .ignoresSafeArea()

            // Tap zones: single tap toggles controls, double tap on a side skips 10s.
            HStack(spacing: 0) {
                tapZone(seek: -10)
                tapZone(seek: 10)
            }
            .ignoresSafeArea()

            if model.buffering && model.errorMessage == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }

            if let flash = seekFlash {
                Text(flash)
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .allowsHitTesting(false)
            }

            if controlsVisible && model.errorMessage == nil {
                controls
                    .transition(.opacity)
            }

            if let error = model.errorMessage {
                errorOverlay(error)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            model.app = app
            UIApplication.shared.isIdleTimerDisabled = true
            Orientation.lock(.landscape)
            scheduleHide()
        }
        .onDisappear {
            model.close()
            UIApplication.shared.isIdleTimerDisabled = false
            Orientation.lock(.portrait)
        }
        .onChange(of: model.ended) { _, ended in
            if ended { close() }
        }
        .onChange(of: model.paused) { _, paused in
            if paused { withAnimation { controlsVisible = true } } else { scheduleHide() }
        }
    }

    // MARK: Controls

    private var controls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                topBar
                Spacer()
                centerButtons
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.item.title)
                    .font(.headline)
                    .lineLimit(1)
                if let sub = model.item.subtitle {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            audioMenu
            subtitleMenu

            Button {
                model.toggleFill()
                scheduleHide()
            } label: {
                Image(systemName: model.fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
        }
        .foregroundStyle(.white)
    }

    private var audioMenu: some View {
        Menu {
            Section("Audio") {
                ForEach(model.audioTracks) { track in
                    Button {
                        model.selectAudio(track)
                    } label: {
                        if track.selected {
                            Label(track.label, systemImage: "checkmark")
                        } else {
                            Text(track.label)
                        }
                    }
                }
            }
            Section("Audio sync (\(String(format: "%+.1f", model.audioDelay))s)") {
                Button("Audio 0.1s earlier") { model.shiftAudio(-0.1) }
                Button("Audio 0.1s later") { model.shiftAudio(0.1) }
                Button("Reset sync") { model.resetAudioDelay() }
            }
        } label: {
            Image(systemName: "waveform")
                .font(.title3)
                .frame(width: 40, height: 40)
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Section("Subtitles") {
                Button {
                    model.selectSubtitle(nil)
                } label: {
                    if !model.subtitleTracks.contains(where: \.selected) {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }
                ForEach(model.subtitleTracks) { track in
                    Button {
                        model.selectSubtitle(track)
                    } label: {
                        if track.selected {
                            Label(track.label, systemImage: "checkmark")
                        } else {
                            Text(track.label)
                        }
                    }
                }
            }
            Section("Subtitle sync (\(String(format: "%+.1f", model.subtitleDelay))s)") {
                Button("Subtitles 0.1s earlier") { model.shiftSubtitles(-0.1) }
                Button("Subtitles 0.1s later") { model.shiftSubtitles(0.1) }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.title3)
                .frame(width: 40, height: 40)
        }
    }

    private var centerButtons: some View {
        HStack(spacing: 56) {
            Button {
                model.skip(-10)
                scheduleHide()
            } label: {
                Image(systemName: "gobackward.10").font(.system(size: 30))
            }

            Button {
                model.togglePause()
                scheduleHide()
            } label: {
                Image(systemName: model.paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 44))
                    .frame(width: 64, height: 64)
            }
            .opacity(model.buffering ? 0 : 1)

            Button {
                model.skip(10)
                scheduleHide()
            } label: {
                Image(systemName: "goforward.10").font(.system(size: 30))
            }
        }
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        let shown = scrubbing ? scrubValue : model.position
        return HStack(spacing: 12) {
            Text(Self.format(shown))
                .monospacedDigit()
                .font(.footnote)
            Slider(value: Binding(
                get: { scrubbing ? scrubValue : model.position },
                set: { scrubValue = $0 }
            ), in: 0...max(model.duration, 1)) { editing in
                if editing {
                    scrubValue = model.position
                    scrubbing = true
                    hideTask?.cancel()
                } else {
                    model.seek(to: scrubValue)
                    scrubbing = false
                    scheduleHide()
                }
            }
            .tint(Theme.accent)
            Text("-" + Self.format(max(0, model.duration - shown)))
                .monospacedDigit()
                .font(.footnote)
        }
        .foregroundStyle(.white)
    }

    private func tapZone(seek: Double) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                model.skip(seek)
                flash(seek > 0 ? "+10s" : "−10s")
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
                if controlsVisible { scheduleHide() }
            }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Theme.dub)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Button("Back to streams", action: close)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
    }

    // MARK: Helpers

    private func close() {
        dismiss()
    }

    private func flash(_ text: String) {
        withAnimation { seekFlash = text }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation { seekFlash = nil }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, !model.paused, !scrubbing else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
