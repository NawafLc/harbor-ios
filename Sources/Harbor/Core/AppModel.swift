import Foundation
import Security
import SwiftUI

/// App-wide state: your Stremio session, addons and library.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var authKey: String? = nil
    @Published private(set) var email: String? = nil
    @Published private(set) var addons: [Addon] = []
    @Published private(set) var library: [String: LibraryItem] = [:]
    @Published private(set) var isSyncing = false
    @Published var syncError: String? = nil
    @Published private(set) var lastSync: Date? = nil

    private let defaults = UserDefaults.standard
    private var pendingPush: [String: LibraryItem] = [:]

    init() {
        authKey = Keychain.read("authKey") ?? defaults.string(forKey: "authKey")
        email = defaults.string(forKey: "email")
        loadCache()
        if authKey != nil {
            Task { await sync() }
        }
    }

    var isLoggedIn: Bool { authKey != nil }

    var continueWatching: [LibraryItem] {
        library.values
            .filter(\.isInContinueWatching)
            .sorted { $0.mtime > $1.mtime }
    }

    var libraryItems: [LibraryItem] {
        library.values
            .filter(\.isInLibrary)
            .sorted { $0.mtime > $1.mtime }
    }

    func libraryItem(id: String) -> LibraryItem? { library[id] }

    // MARK: Account

    func login(email: String, password: String) async throws {
        let session = try await StremioAPI.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        authKey = session.authKey
        self.email = session.email
        if !Keychain.write("authKey", session.authKey) {
            defaults.set(session.authKey, forKey: "authKey")
        }
        defaults.set(session.email, forKey: "email")
        await sync()
    }

    func logout() {
        if let key = authKey { Task { await StremioAPI.logout(authKey: key) } }
        authKey = nil
        email = nil
        addons = []
        library = [:]
        pendingPush = [:]
        Keychain.delete("authKey")
        defaults.removeObject(forKey: "authKey")
        defaults.removeObject(forKey: "email")
        try? FileManager.default.removeItem(at: cacheURL)
    }

    // MARK: Sync

    /// Pulls your addons and library from your Stremio account (what Harbor on your PC uses).
    func sync() async {
        guard let key = authKey, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await flushPending()
        do {
            async let addonsTask = StremioAPI.addons(authKey: key)
            async let libraryTask = StremioAPI.library(authKey: key)
            let (newAddons, items) = try await (addonsTask, libraryTask)
            addons = newAddons
            var dict: [String: LibraryItem] = [:]
            for item in items {
                // Keep whichever copy is newer (a local change may not have reached the server yet).
                if let local = library[item.id], local.mtime > item.mtime {
                    dict[item.id] = local
                    pendingPush[item.id] = local
                } else {
                    dict[item.id] = item
                }
            }
            // Local-only entries (e.g. something watched while offline).
            for (id, local) in library where dict[id] == nil && pendingPush[id] != nil {
                dict[id] = local
            }
            library = dict
            lastSync = Date()
            syncError = nil
            saveCache()
            if !pendingPush.isEmpty { await flushPending() }
        } catch {
            if case .server(let msg)? = error as? HarborError, msg.lowercased().contains("session") {
                // Auth key expired — sign out so you can log in again.
                logout()
                syncError = "Your session expired. Please log in again."
            } else {
                syncError = error.localizedDescription
            }
        }
    }

    // MARK: Library edits

    func update(_ item: LibraryItem, push: Bool) {
        library[item.id] = item
        pendingPush[item.id] = item
        if push { Task { await flushPending() } }
    }

    func flushPending() async {
        guard let key = authKey, !pendingPush.isEmpty else { return }
        let items = Array(pendingPush.values)
        pendingPush = [:]
        do {
            try await StremioAPI.putLibrary(authKey: key, items: items)
            saveCache()
        } catch {
            // Try again next time.
            for item in items where pendingPush[item.id] == nil { pendingPush[item.id] = item }
        }
    }

    func toggleLibrary(_ meta: MetaPreview) {
        var item = library[meta.id] ?? LibraryItem(meta: meta, videoId: nil)
        if item.isInLibrary {
            item.removed = true
        } else {
            item.removed = false
            item.temp = false
        }
        item.touch()
        update(item, push: true)
    }

    func dismissContinueWatching(_ id: String) {
        guard var item = library[id] else { return }
        item.dismissFromContinueWatching()
        update(item, push: true)
    }

    /// Called by the player every few seconds. Positions are in seconds.
    func recordProgress(meta: MetaPreview, videoId: String, position: Double, duration: Double,
                        watchedSeconds: Double, push: Bool) {
        var item = library[meta.id] ?? LibraryItem(meta: meta, videoId: videoId)
        // For movies Stremio stores the meta id itself as the video id.
        item.recordProgress(videoId: videoId, position: position, duration: duration, watchedSeconds: watchedSeconds)
        if duration > 0, position / duration >= 0.9 {
            item.markFinished(isMovie: meta.type == "movie")
        }
        update(item, push: push)
    }

    /// Where to resume `videoId`, in seconds (0 if not started).
    func resumePosition(metaId: String, videoId: String) -> Double {
        guard let item = library[metaId], item.videoId == videoId, item.timeOffset > 0 else { return 0 }
        if item.duration > 0, item.timeOffset / item.duration > 0.95 { return 0 }
        return item.timeOffset / 1000
    }

    // MARK: Offline cache (so Home shows instantly on launch)

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("account-cache.json")
    }

    /// Only the library is cached; addons are re-fetched on every launch.
    private func saveCache() {
        let obj: [String: Any] = ["library": library.values.map(\.raw)]
        if JSONSerialization.isValidJSONObject(obj), let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["library"] as? [[String: Any]] else { return }
        var dict: [String: LibraryItem] = [:]
        for raw in items {
            let item = LibraryItem(raw: raw)
            if !item.id.isEmpty { dict[item.id] = item }
        }
        library = dict
    }
}

// MARK: - User settings

enum SettingsKey {
    static let torrentServer = "torrentServer"
    static let preferEnglishAudio = "preferEnglishAudio"
    static let subtitleLanguage = "subtitleLanguage"
    static let autoSubtitles = "autoSubtitles"
}

// MARK: - Keychain

enum Keychain {
    private static let service = "com.nawaf.harbor.mobile"

    @discardableResult
    static func write(_ key: String, _ value: String) -> Bool {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
