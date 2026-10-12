import Foundation

enum HarborError: LocalizedError {
    case server(String)
    case badResponse
    case noAddon(String)

    var errorDescription: String? {
        switch self {
        case .server(let m): return m
        case .badResponse: return "Unexpected response from the server."
        case .noAddon(let what): return "None of your addons can provide \(what)."
        }
    }
}

/// Talks to your Stremio account (api.strem.io) — the same account Harbor on your PC syncs with.
enum StremioAPI {
    private static let base = URL(string: "https://api.strem.io/api/")!

    private static func call(_ method: String, _ body: [String: Any]) async throws -> Any {
        var req = URLRequest(url: base.appendingPathComponent(method))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HarborError.badResponse
        }
        if let err = obj["error"] as? [String: Any] {
            throw HarborError.server(err["message"] as? String ?? "Unknown error")
        }
        if let err = obj["error"] as? String {
            throw HarborError.server(err)
        }
        guard let result = obj["result"] else { throw HarborError.badResponse }
        return result
    }

    struct Session {
        var authKey: String
        var email: String
    }

    static func login(email: String, password: String) async throws -> Session {
        let result = try await call("login", [
            "type": "Login",
            "email": email,
            "password": password,
            "facebook": false,
        ])
        guard let dict = result as? [String: Any], let key = dict["authKey"] as? String else {
            throw HarborError.badResponse
        }
        let user = dict["user"] as? [String: Any]
        return Session(authKey: key, email: user?["email"] as? String ?? email)
    }

    static func logout(authKey: String) async {
        _ = try? await call("logout", ["type": "Logout", "authKey": authKey])
    }

    static func addons(authKey: String) async throws -> [Addon] {
        let result = try await call("addonCollectionGet", [
            "type": "AddonCollectionGet",
            "authKey": authKey,
            "update": true,
        ])
        guard let dict = result as? [String: Any], let list = dict["addons"] else {
            throw HarborError.badResponse
        }
        let data = try JSONSerialization.data(withJSONObject: list)
        return try JSONDecoder().decode([Lossy<Addon>].self, from: data).compactMap(\.value)
    }

    static func library(authKey: String) async throws -> [LibraryItem] {
        let result = try await call("datastoreGet", [
            "authKey": authKey,
            "collection": "libraryItem",
            "ids": [String](),
            "all": true,
        ])
        guard let list = result as? [[String: Any]] else { throw HarborError.badResponse }
        return list.map(LibraryItem.init(raw:)).filter { !$0.id.isEmpty }
    }

    static func putLibrary(authKey: String, items: [LibraryItem]) async throws {
        guard !items.isEmpty else { return }
        _ = try await call("datastorePut", [
            "authKey": authKey,
            "collection": "libraryItem",
            "changes": items.map(\.raw),
        ])
    }
}

/// Talks to Stremio addons directly (catalogs, metadata, streams, subtitles).
enum AddonClient {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 40
        cfg.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: cfg)
    }()

    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/?#")
        return set
    }()

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: pathAllowed) ?? s
    }

    private static func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw HarborError.badResponse }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HarborError.server("Addon returned HTTP \(http.statusCode)")
        }
        return data
    }

    private struct MetasResponse: Decodable {
        var metas: [Lossy<MetaPreview>]?
    }

    private struct MetaResponse: Decodable {
        var meta: MetaDetail
    }

    private struct StreamsResponse: Decodable {
        var streams: [Lossy<StreamItem>]?
    }

    private struct SubtitlesResponse: Decodable {
        var subtitles: [Lossy<SubtitleItem>]?
    }

    static func catalog(_ addon: Addon, _ catalog: CatalogDef, search: String? = nil, skip: Int = 0) async throws -> [MetaPreview] {
        var extras: [String] = []
        if let search { extras.append("search=\(encode(search))") }
        if skip > 0 { extras.append("skip=\(skip)") }
        var url = "\(addon.baseURL)/catalog/\(encode(catalog.type))/\(encode(catalog.id))"
        if !extras.isEmpty { url += "/" + extras.joined(separator: "&") }
        url += ".json"
        let data = try await get(url)
        let res = try JSONDecoder().decode(MetasResponse.self, from: data)
        return (res.metas ?? []).compactMap(\.value).map { item in
            var m = item
            if m.type.isEmpty { m.type = catalog.type }
            return m
        }
    }

    /// Asks each addon that can describe this title, in your addon order, until one answers.
    static func meta(addons: [Addon], type: String, id: String) async throws -> MetaDetail {
        let candidates = addons.filter { $0.supports("meta", type: type, id: id) }
        guard !candidates.isEmpty else { throw HarborError.noAddon("details for this title") }
        var lastError: Error = HarborError.badResponse
        for addon in candidates {
            do {
                let data = try await get("\(addon.baseURL)/meta/\(encode(type))/\(encode(id)).json")
                let meta = try JSONDecoder().decode(MetaResponse.self, from: data).meta
                return meta
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func streams(_ addon: Addon, type: String, videoId: String) async throws -> [StreamItem] {
        let data = try await get("\(addon.baseURL)/stream/\(encode(type))/\(encode(videoId)).json")
        let res = try JSONDecoder().decode(StreamsResponse.self, from: data)
        return (res.streams ?? []).compactMap(\.value).map { s in
            var copy = s
            copy.addonName = addon.manifest.name
            return copy
        }
    }

    static func subtitles(addons: [Addon], type: String, videoId: String) async -> [SubtitleItem] {
        let candidates = addons.filter { $0.supports("subtitles", type: type, id: videoId) }
        return await withTaskGroup(of: [SubtitleItem].self) { group in
            for addon in candidates {
                group.addTask {
                    guard let data = try? await get("\(addon.baseURL)/subtitles/\(encode(type))/\(encode(videoId)).json"),
                          let res = try? JSONDecoder().decode(SubtitlesResponse.self, from: data) else { return [] }
                    return (res.subtitles ?? []).compactMap(\.value)
                }
            }
            var all: [SubtitleItem] = []
            for await list in group { all += list }
            return all
        }
    }
}
