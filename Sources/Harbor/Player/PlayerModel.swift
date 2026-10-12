import Foundation
import SwiftUI

/// Everything the player needs to start a stream.
struct PlayItem: Identifiable {
    let id = UUID()
    var url: String
    var headers: [String: String]
    var meta: MetaPreview
    var videoId: String
    var title: String
    var subtitle: String?
    var startAt: Double
}

@MainActor
final class PlayerModel: ObservableObject, MPVPlayerDelegate {
    let item: PlayItem
    let core = MPVCore()
    weak var app: AppModel?

    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var paused = false
    @Published var buffering = true
    @Published var loaded = false
    @Published var audioTracks: [MPVTrack] = []
    @Published var subtitleTracks: [MPVTrack] = []
    @Published var errorMessage: String?
    @Published var ended = false
    @Published var fill = false
    @Published var audioDelay: Double = 0
    @Published var subtitleDelay: Double = 0

    private var lastTrackedPosition: Double?
    private var tick = 0
    private var progressTimer: Timer?
    private var subtitlesAdded = false

    init(item: PlayItem) {
        self.item = item
        core.delegate = self
    }

    /// mpv options derived from Settings.
    var options: [String: String] {
        let d = UserDefaults.standard
        let preferEnglish = d.object(forKey: SettingsKey.preferEnglishAudio) as? Bool ?? true
        let subLang = d.string(forKey: SettingsKey.subtitleLanguage) ?? "eng,en"
        var o: [String: String] = [:]
        if subLang == "none" {
            o["sid"] = "no"
        } else {
            o["slang"] = subLang
        }
        if preferEnglish { o["alang"] = "eng,en,en-US" }
        return o
    }

    // MARK: Lifecycle

    func ready() {
        core.load(url: item.url, headers: item.headers, start: item.startAt)
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportProgress(push: false) }
        }
    }

    func close() {
        reportProgress(push: true)
        progressTimer?.invalidate()
        progressTimer = nil
        core.delegate = nil
        core.shutdown()
    }

    private func reportProgress(push: Bool) {
        guard loaded, duration > 0, let app else { return }
        tick += 1
        var watched: Double = 0
        if let last = lastTrackedPosition {
            let delta = position - last
            // Count only normal playback, not seeks.
            if delta > 0 && delta < 15 { watched = delta }
        }
        lastTrackedPosition = position
        app.recordProgress(meta: item.meta, videoId: item.videoId, position: position, duration: duration,
                           watchedSeconds: watched, push: push || tick % 6 == 0)
    }

    // MARK: Controls

    func togglePause() { core.setPaused(!paused) }

    func seek(to seconds: Double) {
        position = seconds
        lastTrackedPosition = nil
        core.seek(to: seconds)
    }

    func skip(_ seconds: Double) {
        lastTrackedPosition = nil
        core.seek(by: seconds)
    }

    func selectAudio(_ track: MPVTrack) { core.selectAudio(track.id) }

    func selectSubtitle(_ track: MPVTrack?) { core.selectSubtitle(track?.id) }

    func toggleFill() {
        fill.toggle()
        core.setFill(fill)
    }

    func shiftAudio(_ delta: Double) {
        audioDelay = ((audioDelay + delta) * 10).rounded() / 10
        core.addAudioDelay(delta)
    }

    func resetAudioDelay() {
        core.addAudioDelay(-audioDelay)
        audioDelay = 0
    }

    func shiftSubtitles(_ delta: Double) {
        subtitleDelay = ((subtitleDelay + delta) * 10).rounded() / 10
        core.addSubtitleDelay(delta)
    }

    // MARK: MPVPlayerDelegate

    func mpvTimeChanged(position: Double) { self.position = position }

    func mpvDurationChanged(_ duration: Double) { self.duration = duration }

    func mpvPauseChanged(_ paused: Bool) { self.paused = paused }

    func mpvBufferingChanged(_ buffering: Bool) { self.buffering = buffering }

    func mpvFileLoaded() {
        loaded = true
        buffering = false
        errorMessage = nil
        Task { await addAddonSubtitles() }
    }

    func mpvTracksChanged(_ tracks: [MPVTrack]) {
        audioTracks = tracks.filter { $0.type == "audio" }
        subtitleTracks = tracks.filter { $0.type == "sub" }
    }

    func mpvEnded(error: String?) {
        if let error {
            errorMessage = error
        } else {
            ended = true
            reportProgress(push: true)
        }
    }

    func startFailed(_ message: String) {
        errorMessage = message
    }

    // MARK: Subtitles from your addons (e.g. OpenSubtitles)

    private func addAddonSubtitles() async {
        guard !subtitlesAdded, let app else { return }
        subtitlesAdded = true
        let subs = await AddonClient.subtitles(addons: app.addons, type: item.meta.type, videoId: item.videoId)
        guard !subs.isEmpty else { return }
        let wanted = (UserDefaults.standard.string(forKey: SettingsKey.subtitleLanguage) ?? "eng,en")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        // Your languages first, at most 4 per language and 12 overall.
        var perLang: [String: Int] = [:]
        let sorted = subs.sorted { a, b in
            let ia = wanted.firstIndex(of: a.lang.lowercased()) ?? Int.max
            let ib = wanted.firstIndex(of: b.lang.lowercased()) ?? Int.max
            return ia < ib
        }
        // Turn one on only if the file had no subtitle in your language.
        var shouldSelect = !wanted.contains("none") && !subtitleTracks.contains(where: \.selected)
        var added = 0
        for sub in sorted where added < 12 {
            let lang = sub.lang.lowercased()
            if perLang[lang, default: 0] >= 4 { continue }
            perLang[lang, default: 0] += 1
            added += 1
            let name = MPVTrack.languageName(sub.lang)
            let select = shouldSelect && wanted.contains(lang)
            if select { shouldSelect = false }
            core.addSubtitle(url: sub.url, title: "\(name) (addon) \(perLang[lang]!)", lang: sub.lang, select: select)
        }
    }
}
