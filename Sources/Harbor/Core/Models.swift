import Foundation

// MARK: - Lenient decoding helpers

/// Decodes `T` but never throws: a broken element becomes `nil` instead of failing the whole list.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { stringValue = string; intValue = nil }
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

extension KeyedDecodingContainer where Key == AnyKey {
    /// Reads a value that addons sometimes send as a string and sometimes as a number.
    func looseString(_ key: String) -> String? {
        let k = AnyKey(key)
        if let s = try? decodeIfPresent(String.self, forKey: k) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return String(d) }
        return nil
    }

    func looseInt(_ key: String) -> Int? {
        let k = AnyKey(key)
        if let i = try? decodeIfPresent(Int.self, forKey: k) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Int(s) }
        return nil
    }

    func looseInt64(_ key: String) -> Int64? {
        let k = AnyKey(key)
        if let i = try? decodeIfPresent(Int64.self, forKey: k) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: k) { return Int64(d) }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return Int64(s) }
        return nil
    }

    func stringArray(_ key: String) -> [String]? {
        let k = AnyKey(key)
        if let a = try? decodeIfPresent([Lossy<String>].self, forKey: k) { return a.compactMap(\.value) }
        if let s = try? decodeIfPresent(String.self, forKey: k) { return [s] }
        return nil
    }
}

// MARK: - Addons

struct AddonResource: Decodable, Hashable {
    var name: String
    var types: [String]?
    var idPrefixes: [String]?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self.name = name
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = try c.decode(String.self, forKey: AnyKey("name"))
        types = c.stringArray("types")
        idPrefixes = c.stringArray("idPrefixes")
    }
}

struct CatalogExtra: Decodable, Hashable {
    var name: String
    var isRequired: Bool
    var options: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = try c.decode(String.self, forKey: AnyKey("name"))
        isRequired = (try? c.decodeIfPresent(Bool.self, forKey: AnyKey("isRequired"))) ?? false
        options = c.stringArray("options") ?? []
    }
}

struct CatalogDef: Decodable, Hashable {
    var type: String
    var id: String
    var name: String?
    var extra: [CatalogExtra]
    var extraRequired: [String]
    var extraSupported: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        type = try c.decode(String.self, forKey: AnyKey("type"))
        id = try c.decode(String.self, forKey: AnyKey("id"))
        name = c.looseString("name")
        extra = ((try? c.decodeIfPresent([Lossy<CatalogExtra>].self, forKey: AnyKey("extra"))) ?? nil)?
            .compactMap(\.value) ?? []
        extraRequired = c.stringArray("extraRequired") ?? []
        extraSupported = c.stringArray("extraSupported") ?? []
    }

    var requiredExtras: [String] {
        extra.filter(\.isRequired).map(\.name) + extraRequired
    }

    /// Catalogs that can be shown on Home without any user input.
    var isBrowsable: Bool { requiredExtras.isEmpty }

    var supportsSearch: Bool {
        extra.contains { $0.name == "search" } || extraSupported.contains("search")
    }

    /// Search works only if "search" is the sole required extra (or nothing is required).
    var isSearchable: Bool {
        supportsSearch && requiredExtras.allSatisfy { $0 == "search" }
    }
}

struct AddonManifest: Decodable, Hashable {
    var id: String
    var name: String
    var version: String?
    var description: String?
    var logo: String?
    var types: [String]
    var idPrefixes: [String]?
    var resources: [AddonResource]
    var catalogs: [CatalogDef]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.looseString("id") ?? UUID().uuidString
        name = c.looseString("name") ?? "Addon"
        version = c.looseString("version")
        description = c.looseString("description")
        logo = c.looseString("logo")
        types = c.stringArray("types") ?? []
        idPrefixes = c.stringArray("idPrefixes")
        resources = ((try? c.decodeIfPresent([Lossy<AddonResource>].self, forKey: AnyKey("resources"))) ?? nil)?
            .compactMap(\.value) ?? []
        catalogs = ((try? c.decodeIfPresent([Lossy<CatalogDef>].self, forKey: AnyKey("catalogs"))) ?? nil)?
            .compactMap(\.value) ?? []
    }
}

struct Addon: Decodable, Identifiable, Hashable {
    var transportUrl: String
    var manifest: AddonManifest

    var id: String { transportUrl }

    /// Addon base URL without the trailing `/manifest.json`.
    var baseURL: String {
        var s = transportUrl
        if s.hasPrefix("stremio://") { s = "https://" + s.dropFirst("stremio://".count) }
        if let r = s.range(of: "/manifest.json", options: .backwards) { s = String(s[..<r.lowerBound]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func supports(_ resource: String, type: String, id: String) -> Bool {
        for r in manifest.resources where r.name == resource {
            let types = r.types ?? manifest.types
            guard types.contains(type) else { continue }
            if let prefixes = r.idPrefixes ?? manifest.idPrefixes, !prefixes.isEmpty {
                guard prefixes.contains(where: { id.hasPrefix($0) }) else { continue }
            }
            return true
        }
        return false
    }
}

// MARK: - Metadata

struct MetaPreview: Decodable, Identifiable, Hashable {
    var id: String
    var type: String
    var name: String
    var poster: String?
    var posterShape: String?
    var background: String?
    var releaseInfo: String?
    var imdbRating: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.looseString("id") ?? c.looseString("imdb_id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "meta without id"))
        }
        self.id = id
        type = c.looseString("type") ?? ""
        name = c.looseString("name") ?? ""
        poster = c.looseString("poster")
        posterShape = c.looseString("posterShape")
        background = c.looseString("background")
        releaseInfo = c.looseString("releaseInfo") ?? c.looseString("year")
        imdbRating = c.looseString("imdbRating")
    }

    init(id: String, type: String, name: String, poster: String?) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
    }
}

struct Video: Decodable, Identifiable, Hashable {
    var id: String
    var title: String
    var season: Int?
    var episode: Int?
    var released: Date?
    var thumbnail: String?
    var overview: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.looseString("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "video without id"))
        }
        self.id = id
        season = c.looseInt("season")
        episode = c.looseInt("episode") ?? c.looseInt("number")
        title = c.looseString("title") ?? c.looseString("name") ?? ""
        released = c.looseString("released").flatMap(DateParsing.parse)
        thumbnail = c.looseString("thumbnail")
        overview = c.looseString("overview") ?? c.looseString("description")
    }

    var label: String {
        if let s = season, let e = episode {
            return s == 0 ? "Special \(e)" : "S\(s) E\(e)"
        }
        if let e = episode { return "Episode \(e)" }
        return title
    }
}

struct MetaDetail: Decodable, Hashable {
    var id: String
    var type: String
    var name: String
    var poster: String?
    var background: String?
    var logo: String?
    var description: String?
    var releaseInfo: String?
    var imdbRating: String?
    var runtime: String?
    var genres: [String]
    var videos: [Video]
    var defaultVideoId: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.looseString("id") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "meta without id"))
        }
        self.id = id
        type = c.looseString("type") ?? "movie"
        name = c.looseString("name") ?? ""
        poster = c.looseString("poster")
        background = c.looseString("background")
        logo = c.looseString("logo")
        description = c.looseString("description")
        releaseInfo = c.looseString("releaseInfo") ?? c.looseString("year")
        imdbRating = c.looseString("imdbRating")
        runtime = c.looseString("runtime")
        genres = c.stringArray("genres") ?? c.stringArray("genre") ?? []
        videos = ((try? c.decodeIfPresent([Lossy<Video>].self, forKey: AnyKey("videos"))) ?? nil)?
            .compactMap(\.value) ?? []
        if let hints = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("behaviorHints")) {
            defaultVideoId = hints.looseString("defaultVideoId")
        }
    }

    /// True when the title has episodes to choose from.
    var hasEpisodes: Bool { !videos.isEmpty && defaultVideoId == nil }

    var seasons: [Int] {
        let set = Set(videos.compactMap(\.season))
        // Specials (season 0) go last, like Stremio.
        return set.sorted { a, b in
            if a == 0 { return false }
            if b == 0 { return true }
            return a < b
        }
    }

    func episodes(in season: Int?) -> [Video] {
        let list = season == nil ? videos : videos.filter { $0.season == season }
        return list.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    var preview: MetaPreview { MetaPreview(id: id, type: type, name: name, poster: poster) }
}

// MARK: - Streams & subtitles

struct StreamItem: Decodable, Identifiable, Hashable {
    let id = UUID()
    var name: String?
    var title: String?
    var description: String?
    var url: String?
    var infoHash: String?
    var fileIdx: Int?
    var externalUrl: String?
    var ytId: String?
    var filename: String?
    var bingeGroup: String?
    var videoSize: Int64?
    var requestHeaders: [String: String]
    var sources: [String]
    var addonName: String = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.looseString("name")
        title = c.looseString("title")
        description = c.looseString("description")
        url = c.looseString("url")
        infoHash = c.looseString("infoHash")?.lowercased()
        fileIdx = c.looseInt("fileIdx")
        externalUrl = c.looseString("externalUrl")
        ytId = c.looseString("ytId")
        sources = c.stringArray("sources") ?? []
        requestHeaders = [:]
        if let hints = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("behaviorHints")) {
            filename = hints.looseString("filename") ?? hints.looseString("fileName")
            bingeGroup = hints.looseString("bingeGroup")
            videoSize = hints.looseInt64("videoSize")
            if let proxy = try? hints.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("proxyHeaders")),
               let req = try? proxy.decodeIfPresent([String: String].self, forKey: AnyKey("request")) {
                requestHeaders = req
            }
        }
        if url == nil && infoHash == nil && externalUrl == nil && ytId == nil {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "stream without source"))
        }
    }

    static func == (a: StreamItem, b: StreamItem) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Everything a human would read about this release.
    var allText: String {
        [filename, title, description, name].compactMap { $0 }.joined(separator: "\n")
    }

    var displayName: String {
        (name ?? addonName).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var detailText: String {
        (title ?? description ?? filename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isTorrentOnly: Bool { url == nil && infoHash != nil }

    var quality: String? {
        let t = allText.lowercased()
        if t.contains("2160p") || t.contains("4k") || t.contains("uhd") { return "4K" }
        if t.contains("1440p") { return "1440p" }
        if t.contains("1080p") { return "1080p" }
        if t.contains("720p") { return "720p" }
        if t.contains("480p") { return "480p" }
        return nil
    }

    var sizeText: String? {
        if let s = videoSize, s > 0 {
            return ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
        }
        let rx = try? NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*(TB|GB|MB|TiB|GiB|MiB)\b"#, options: [.caseInsensitive])
        let t = allText
        if let m = rx?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let r = Range(m.range, in: t) {
            return String(t[r])
        }
        return nil
    }
}

struct SubtitleItem: Decodable, Hashable {
    var id: String
    var url: String
    var lang: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let url = c.looseString("url") else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "subtitle without url"))
        }
        self.url = url
        id = c.looseString("id") ?? url
        lang = c.looseString("lang") ?? "und"
    }
}

// MARK: - Navigation routes

struct MetaRoute: Hashable {
    var id: String
    var type: String
    var name: String
    var poster: String?
}

struct StreamRoute: Hashable {
    var meta: MetaPreview
    var videoId: String
    var title: String
    var subtitle: String?
}

// MARK: - Dates

enum DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s)
    }

    /// Stremio stores dates like `2026-10-12T15:04:05.123Z`.
    static func format(_ d: Date) -> String {
        withFraction.string(from: d)
    }
}
