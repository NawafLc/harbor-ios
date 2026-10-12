import Foundation
import Libmpv
import UIKit

/// A track (audio or subtitle) reported by mpv.
struct MPVTrack: Identifiable, Hashable {
    var id: Int
    var type: String
    var title: String?
    var lang: String?
    var codec: String?
    var selected: Bool
    var external: Bool

    var label: String {
        var parts: [String] = []
        if let lang, !lang.isEmpty { parts.append(Self.languageName(lang)) }
        if let title, !title.isEmpty, title.lowercased() != lang?.lowercased() { parts.append(title) }
        if parts.isEmpty { parts.append("Track \(id)") }
        if let codec, !codec.isEmpty, type == "audio" { parts.append(codec.uppercased()) }
        return parts.joined(separator: " · ")
    }

    var isEnglish: Bool {
        guard let lang = lang?.lowercased() else { return false }
        return lang == "en" || lang == "eng" || lang.hasPrefix("en-")
    }

    static func languageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}

@MainActor
protocol MPVPlayerDelegate: AnyObject {
    func mpvTimeChanged(position: Double)
    func mpvDurationChanged(_ duration: Double)
    func mpvPauseChanged(_ paused: Bool)
    func mpvBufferingChanged(_ buffering: Bool)
    func mpvFileLoaded()
    func mpvTracksChanged(_ tracks: [MPVTrack])
    func mpvEnded(error: String?)
}

// MARK: - libmpv wrapper (runs off the main thread)

/// Owns the libmpv handle. Events are read on a private queue and forwarded to the main actor.
final class MPVCore: @unchecked Sendable {
    weak var delegate: MPVPlayerDelegate?

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "harbor.mpv.events", qos: .userInitiated)
    private let lock = NSLock()

    private var mpv: OpaquePointer? {
        lock.lock(); defer { lock.unlock() }
        return handle
    }

    /// Creates mpv and makes it render into `layer`.
    func start(layer: CAMetalLayer, options: [String: String]) -> String? {
        guard let h = mpv_create() else { return "Player failed to start." }

        mpv_request_log_messages(h, "no")
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(h, "wid", MPV_FORMAT_INT64, &wid)

        let base: [(String, String)] = [
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            ("video-rotate", "no"),
            ("keep-open", "yes"),
            ("cache", "yes"),
            ("demuxer-max-bytes", "150MiB"),
            ("demuxer-max-back-bytes", "50MiB"),
            ("network-timeout", "30"),
            ("subs-fallback", "yes"),
            ("user-agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Harbor-iOS/1.0"),
        ]
        for (k, v) in base { mpv_set_option_string(h, k, v) }
        for (k, v) in options { mpv_set_option_string(h, k, v) }

        let status = mpv_initialize(h)
        if status < 0 {
            mpv_terminate_destroy(h)
            return "Player failed to start: \(String(cString: mpv_error_string(status)))"
        }

        mpv_observe_property(h, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(h, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(h, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(h, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(h, 0, "track-list/count", MPV_FORMAT_INT64)
        mpv_observe_property(h, 0, "aid", MPV_FORMAT_STRING)
        mpv_observe_property(h, 0, "sid", MPV_FORMAT_STRING)

        lock.lock(); handle = h; lock.unlock()

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(h, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVCore>.fromOpaque(ctx).takeUnretainedValue().drainEvents()
        }, ctx)
        return nil
    }

    /// Stops playback and frees mpv. Safe to call more than once.
    /// Runs asynchronously so the main thread is never blocked waiting on mpv.
    func shutdown() {
        queue.async {
            self.lock.lock()
            let h = self.handle
            self.handle = nil
            self.lock.unlock()
            guard let h else { return }
            mpv_set_wakeup_callback(h, nil, nil)
            mpv_terminate_destroy(h)
        }
    }

    deinit {
        if let h = handle {
            mpv_set_wakeup_callback(h, nil, nil)
            mpv_terminate_destroy(h)
        }
    }

    // MARK: Commands

    func load(url: String, headers: [String: String], start: Double) {
        if headers.isEmpty {
            setProperty("http-header-fields", "")
        } else {
            let fields = headers.map { "\($0.key): \($0.value.replacingOccurrences(of: ",", with: "\\,"))" }
            setProperty("http-header-fields", fields.joined(separator: ","))
        }
        setProperty("start", start > 1 ? String(format: "%.1f", start) : "none")
        command("loadfile", [url, "replace"])
    }

    func addSubtitle(url: String, title: String, lang: String, select: Bool) {
        command("sub-add", [url, select ? "select" : "auto", title, lang])
    }

    func setPaused(_ paused: Bool) { setFlag("pause", paused) }

    func seek(to seconds: Double) {
        command("seek", [String(format: "%.2f", max(0, seconds)), "absolute"])
    }

    func seek(by seconds: Double) {
        command("seek", [String(format: "%.2f", seconds), "relative"])
    }

    func selectAudio(_ id: Int) { setProperty("aid", String(id)) }

    func selectSubtitle(_ id: Int?) { setProperty("sid", id.map { String($0) } ?? "no") }

    func addAudioDelay(_ delta: Double) { command("add", ["audio-delay", String(format: "%.2f", delta)]) }

    func addSubtitleDelay(_ delta: Double) { command("add", ["sub-delay", String(format: "%.2f", delta)]) }

    func setFill(_ fill: Bool) { setProperty("panscan", fill ? "1.0" : "0.0") }

    func setProperty(_ name: String, _ value: String) {
        guard let h = mpv else { return }
        mpv_set_property_string(h, name, value)
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let h = mpv else { return }
        var data: Int32 = flag ? 1 : 0
        mpv_set_property(h, name, MPV_FORMAT_FLAG, &data)
    }

    private func command(_ name: String, _ args: [String]) {
        guard let h = mpv else { return }
        var cargs: [UnsafePointer<CChar>?] = ([name] + args).map { UnsafePointer(strdup($0)) }
        cargs.append(nil)
        defer {
            for ptr in cargs { if let ptr { free(UnsafeMutablePointer(mutating: ptr)) } }
        }
        _ = cargs.withUnsafeMutableBufferPointer { buf in
            mpv_command(h, buf.baseAddress)
        }
    }

    private func getString(_ h: OpaquePointer, _ name: String) -> String? {
        guard let cstr = mpv_get_property_string(h, name) else { return nil }
        defer { mpv_free(cstr) }
        return String(cString: cstr)
    }

    // MARK: Events

    private func drainEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while let h = self.mpv {
                guard let event = mpv_wait_event(h, 0) else { break }
                if event.pointee.event_id == MPV_EVENT_NONE { break }
                self.handle(event.pointee, h)
            }
        }
    }

    private func onMain(_ body: @escaping @MainActor (MPVPlayerDelegate) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let d = self?.delegate else { return }
                body(d)
            }
        }
    }

    private func handle(_ event: mpv_event, _ h: OpaquePointer) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let raw = event.data else { return }
            let prop = raw.assumingMemoryBound(to: mpv_event_property.self).pointee
            let name = String(cString: prop.name)
            let format = prop.format
            if name == "track-list/count" || name == "aid" || name == "sid" {
                let tracks = readTracks(h)
                onMain { $0.mpvTracksChanged(tracks) }
                return
            }
            guard let data = prop.data else { return }
            if format == MPV_FORMAT_DOUBLE {
                let v = data.assumingMemoryBound(to: Double.self).pointee
                if name == "time-pos" { onMain { $0.mpvTimeChanged(position: v) } }
                if name == "duration" { onMain { $0.mpvDurationChanged(v) } }
            } else if format == MPV_FORMAT_FLAG {
                let v = data.assumingMemoryBound(to: Int32.self).pointee != 0
                if name == "pause" { onMain { $0.mpvPauseChanged(v) } }
                if name == "paused-for-cache" { onMain { $0.mpvBufferingChanged(v) } }
            }
        case MPV_EVENT_FILE_LOADED:
            let tracks = readTracks(h)
            onMain {
                $0.mpvFileLoaded()
                $0.mpvTracksChanged(tracks)
            }
        case MPV_EVENT_END_FILE:
            guard let raw = event.data else { return }
            let info = raw.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            if info.reason == MPV_END_FILE_REASON_ERROR {
                let msg = String(cString: mpv_error_string(info.error))
                onMain { $0.mpvEnded(error: "Couldn't play this stream (\(msg)). Try another one.") }
            } else if info.reason == MPV_END_FILE_REASON_EOF {
                onMain { $0.mpvEnded(error: nil) }
            }
        default:
            break
        }
    }

    private func readTracks(_ h: OpaquePointer) -> [MPVTrack] {
        let count = Int(getString(h, "track-list/count") ?? "0") ?? 0
        var tracks: [MPVTrack] = []
        for i in 0..<count {
            let p = "track-list/\(i)/"
            guard let type = getString(h, p + "type"), type == "audio" || type == "sub",
                  let id = Int(getString(h, p + "id") ?? "") else { continue }
            tracks.append(MPVTrack(
                id: id,
                type: type,
                title: getString(h, p + "title"),
                lang: getString(h, p + "lang"),
                codec: getString(h, p + "codec"),
                selected: getString(h, p + "selected") == "yes",
                external: getString(h, p + "external") == "yes"
            ))
        }
        return tracks
    }
}

// MARK: - Fixes a MoltenVK quirk that can leave the drawable at 1x1 (from the MPVKit demo)

final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync { super.wantsExtendedDynamicRangeContent = newValue }
            }
        }
    }
}

// MARK: - The view controller that shows the video

final class MPVViewController: UIViewController {
    let core: MPVCore
    private let metalLayer = MPVMetalLayer()
    private let options: [String: String]
    private var started = false
    var onStartError: ((String) -> Void)?
    var onReady: (() -> Void)?

    init(core: MPVCore, options: [String: String]) {
        self.core = core
        self.options = options
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)

        NotificationCenter.default.addObserver(self, selector: #selector(enterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        CATransaction.commit()
    }

    /// mpv is started once the view has a real size.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        if let error = core.start(layer: metalLayer, options: options) {
            onStartError?(error)
        } else {
            onReady?()
        }
    }

    @objc private func enterBackground() {
        core.setPaused(true)
        core.setProperty("vid", "no")
    }

    @objc private func enterForeground() {
        core.setProperty("vid", "auto")
    }
}
