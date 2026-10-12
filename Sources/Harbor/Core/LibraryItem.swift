import Foundation

/// A Stremio library entry. Kept as the raw JSON dictionary so that fields this app
/// doesn't know about survive a round trip back to your account untouched.
struct LibraryItem: Identifiable {
    var raw: [String: Any]

    init(raw: [String: Any]) {
        self.raw = raw
    }

    /// Creates a new "watched but not added" entry, the same way Stremio does when you
    /// start watching something that isn't in your library yet.
    init(meta: MetaPreview, videoId: String?) {
        let now = DateParsing.format(Date())
        raw = [
            "_id": meta.id,
            "name": meta.name,
            "type": meta.type,
            "poster": meta.poster ?? "",
            "posterShape": meta.posterShape ?? "poster",
            "removed": true,
            "temp": true,
            "_ctime": now,
            "_mtime": now,
            "state": [
                "lastWatched": now,
                "timeWatched": 0,
                "timeOffset": 0,
                "overallTimeWatched": 0,
                "timesWatched": 0,
                "flaggedWatched": 0,
                "duration": 0,
                "video_id": (videoId as Any?) ?? NSNull(),
                "watched": NSNull(),
                "noNotif": false,
            ] as [String: Any],
            "behaviorHints": [
                "defaultVideoId": NSNull(),
                "featuredVideoId": NSNull(),
                "hasScheduledVideos": false,
            ] as [String: Any],
        ]
    }

    var id: String { raw["_id"] as? String ?? "" }
    var name: String { raw["name"] as? String ?? "" }
    var type: String { raw["type"] as? String ?? "movie" }

    var poster: String? {
        guard let p = raw["poster"] as? String, !p.isEmpty else { return nil }
        return p
    }

    var removed: Bool {
        get { Self.bool(raw["removed"]) }
        set { raw["removed"] = newValue }
    }

    var temp: Bool {
        get { Self.bool(raw["temp"]) }
        set { raw["temp"] = newValue }
    }

    var mtime: Date {
        (raw["_mtime"] as? String).flatMap(DateParsing.parse) ?? .distantPast
    }

    mutating func touch() {
        raw["_mtime"] = DateParsing.format(Date())
    }

    var state: [String: Any] {
        get { raw["state"] as? [String: Any] ?? [:] }
        set { raw["state"] = newValue }
    }

    /// Milliseconds.
    var timeOffset: Double { Self.number(state["timeOffset"]) }
    /// Milliseconds.
    var duration: Double { Self.number(state["duration"]) }

    var videoId: String? {
        guard let v = state["video_id"] as? String, !v.isEmpty else { return nil }
        return v
    }

    var lastWatched: Date? {
        (state["lastWatched"] as? String).flatMap(DateParsing.parse)
    }

    /// 0...1
    var progress: Double {
        guard timeOffset > 0, duration > 0 else { return 0 }
        return min(1, timeOffset / duration)
    }

    /// Same rule as stremio-core.
    var isInContinueWatching: Bool {
        type != "other" && (!removed || temp) && timeOffset > 0
    }

    var isInLibrary: Bool { !removed && !temp }

    var meta: MetaPreview {
        var m = MetaPreview(id: id, type: type, name: name, poster: poster)
        m.posterShape = raw["posterShape"] as? String
        return m
    }

    // MARK: Mutations

    mutating func setState(_ key: String, _ value: Any) {
        var s = state
        s[key] = value
        state = s
    }

    /// Records playback progress. Positions are in seconds.
    mutating func recordProgress(videoId: String?, position: Double, duration: Double, watchedSeconds: Double) {
        // Watching something that was removed from the library brings it back into
        // Continue Watching without re-adding it (same as Stremio).
        if removed && !temp { temp = true }
        var s = state
        let now = DateParsing.format(Date())
        if let videoId {
            if (s["video_id"] as? String) != videoId {
                // New episode: reset per-video counters like Stremio does.
                s["timeWatched"] = 0
            }
            s["video_id"] = videoId
        }
        s["timeOffset"] = Int64(max(0, position) * 1000)
        if duration > 0 { s["duration"] = Int64(duration * 1000) }
        s["lastWatched"] = now
        let add = Int64(max(0, watchedSeconds) * 1000)
        s["timeWatched"] = Int64(Self.number(s["timeWatched"])) + add
        s["overallTimeWatched"] = Int64(Self.number(s["overallTimeWatched"])) + add
        state = s
        touch()
    }

    /// Called when you get to the end (>= 90%) of a movie or episode.
    mutating func markFinished(isMovie: Bool) {
        var s = state
        s["timesWatched"] = Int64(Self.number(s["timesWatched"])) + 1
        if isMovie { s["flaggedWatched"] = 1 }
        // Drop it from Continue Watching.
        s["timeOffset"] = 0
        state = s
        touch()
    }

    mutating func dismissFromContinueWatching() {
        setState("timeOffset", 0)
        touch()
    }

    // MARK: Helpers

    static func number(_ any: Any?) -> Double {
        if let n = any as? NSNumber { return n.doubleValue }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) ?? 0 }
        return 0
    }

    static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }
}
