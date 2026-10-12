import SwiftUI

struct StreamsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKey.torrentServer) private var torrentServer = ""

    let route: StreamRoute

    @State private var groups: [StreamGroup] = []
    @State private var pending = 0
    @State private var started = false
    @State private var dubOnly = false
    @State private var playItem: PlayItem?
    @State private var notice: String?

    struct StreamGroup: Identifiable {
        let id: String
        let addonName: String
        let order: Int
        var streams: [StreamItem]
        var error: String?
    }

    private var serverURL: String? {
        let s = torrentServer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let withScheme = s.hasPrefix("http") ? s : "http://" + s
        return withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
    }

    private func visible(_ streams: [StreamItem]) -> [StreamItem] {
        streams.filter { s in
            if s.isTorrentOnly && serverURL == nil { return false }
            if dubOnly && DubDetector.detect(s) == nil { return false }
            return true
        }
    }

    private var hiddenTorrents: Int {
        guard serverURL == nil else { return 0 }
        return groups.reduce(0) { $0 + $1.streams.filter(\.isTorrentOnly).count }
    }

    private var dubCount: Int {
        groups.reduce(0) { $0 + $1.streams.filter { DubDetector.detect($0) != nil }.count }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.title).font(.headline)
                    if let sub = route.subtitle {
                        Text(sub).font(.subheadline).foregroundStyle(.secondary)
                    }
                    let resume = app.resumePosition(metaId: route.meta.id, videoId: route.videoId)
                    if resume > 0 {
                        Label("Resumes at \(PlayerView.format(resume))", systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .listRowBackground(Color.clear)

                Picker("Filter", selection: $dubOnly) {
                    Text("All streams").tag(false)
                    Text("EN DUB (\(dubCount))").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if let notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.dub)
                }
            }

            ForEach(groups.sorted { $0.order < $1.order }) { group in
                let streams = visible(group.streams)
                if !streams.isEmpty {
                    Section(group.addonName) {
                        ForEach(streams) { stream in
                            Button {
                                play(stream)
                            } label: {
                                StreamRow(stream: stream)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if pending > 0 {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Asking \(pending) more addon\(pending == 1 ? "" : "s")…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if started && groups.allSatisfy({ visible($0.streams).isEmpty }) {
                Section {
                    EmptyStateView(icon: "play.slash",
                                   title: dubOnly ? "No EN DUB streams" : "No streams found",
                                   message: dubOnly ? "Switch to All streams to see everything." : "None of your addons returned a playable link for this.")
                }
                .listRowBackground(Color.clear)
            }

            if hiddenTorrents > 0 {
                Section {
                    Text("\(hiddenTorrents) torrent-only stream\(hiddenTorrents == 1 ? " is" : "s are") hidden. Set a streaming server in Settings to play them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Streams")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .fullScreenCover(item: $playItem) { item in
            PlayerView(item: item)
                .environmentObject(app)
        }
    }

    // MARK: Loading

    private func load(force: Bool) async {
        if started && !force { return }
        started = true
        groups = []
        let type = route.meta.type
        let videoId = route.videoId
        let addons = app.addons.enumerated().filter { $0.element.supports("stream", type: type, id: videoId) }
        if addons.isEmpty {
            notice = "None of your addons provide streams for this title."
            return
        }
        notice = nil
        pending = addons.count
        await withTaskGroup(of: StreamGroup.self) { tasks in
            for (index, addon) in addons {
                tasks.addTask {
                    do {
                        let streams = try await AddonClient.streams(addon, type: type, videoId: videoId)
                        return StreamGroup(id: addon.transportUrl, addonName: addon.manifest.name, order: index, streams: streams)
                    } catch {
                        return StreamGroup(id: addon.transportUrl, addonName: addon.manifest.name, order: index,
                                           streams: [], error: error.localizedDescription)
                    }
                }
            }
            for await group in tasks {
                groups.append(group)
                pending -= 1
            }
        }
    }

    // MARK: Playing

    private func play(_ stream: StreamItem) {
        if let url = stream.url, let parsed = URL(string: url), parsed.scheme != nil {
            open(url: url, headers: stream.requestHeaders)
        } else if let hash = stream.infoHash, let server = serverURL {
            var url = "\(server)/\(hash)/\(stream.fileIdx ?? -1)"
            let trackers = stream.sources.filter { $0.hasPrefix("tracker:") }.map { String($0.dropFirst("tracker:".count)) }
            if !trackers.isEmpty {
                url += "?" + trackers.map { "tr=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0) }
                    .joined(separator: "&")
            }
            open(url: url, headers: [:])
        } else if let ext = stream.externalUrl, let u = URL(string: ext) {
            openURL(u)
        } else if let yt = stream.ytId, let u = URL(string: "https://www.youtube.com/watch?v=\(yt)") {
            openURL(u)
        } else {
            notice = "This stream can't be played on iPhone."
        }
    }

    private func open(url: String, headers: [String: String]) {
        playItem = PlayItem(
            url: url,
            headers: headers,
            meta: route.meta,
            videoId: route.videoId,
            title: route.title,
            subtitle: route.subtitle,
            startAt: app.resumePosition(metaId: route.meta.id, videoId: route.videoId)
        )
    }
}

struct StreamRow: View {
    let stream: StreamItem

    var body: some View {
        let dub = DubDetector.detect(stream)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stream.displayName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(3)
                HStack(spacing: 5) {
                    if let dub { DubBadge(result: dub) }
                    if let q = stream.quality { Pill(text: q, color: Theme.accent.opacity(0.25), foreground: Theme.accent) }
                    if let size = stream.sizeText { Pill(text: size) }
                    if stream.isTorrentOnly { Pill(text: "TORRENT", color: .purple.opacity(0.35)) }
                }
            }
            .frame(width: 130, alignment: .leading)

            Text(stream.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
