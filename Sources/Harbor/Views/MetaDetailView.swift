import SwiftUI

struct MetaDetailView: View {
    @EnvironmentObject private var app: AppModel
    let route: MetaRoute

    @State private var meta: MetaDetail?
    @State private var error: String?
    @State private var season: Int?
    @State private var expanded = false

    private var libraryItem: LibraryItem? { app.libraryItem(id: route.id) }
    private var inLibrary: Bool { libraryItem?.isInLibrary ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let meta {
                    content(meta)
                } else if let error {
                    EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn't load details", message: error)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.toggleLibrary(meta?.preview ?? MetaPreview(id: route.id, type: route.type, name: route.name, poster: route.poster))
                } label: {
                    Image(systemName: inLibrary ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .task(id: route.id) { await load() }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: meta?.background ?? meta?.poster ?? route.poster)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(
                    LinearGradient(colors: [.clear, Theme.background.opacity(0.6), Theme.background],
                                   startPoint: .top, endPoint: .bottom)
                )

            HStack(alignment: .bottom, spacing: 14) {
                RemoteImage(url: meta?.poster ?? route.poster)
                    .frame(width: 96, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(radius: 10)

                VStack(alignment: .leading, spacing: 6) {
                    if let logo = meta?.logo {
                        RemoteImage(url: logo, contentMode: .fit)
                            .frame(maxWidth: 200, maxHeight: 60, alignment: .leading)
                    } else {
                        Text(meta?.name ?? route.name)
                            .font(.title2.weight(.heavy))
                            .lineLimit(3)
                    }
                    HStack(spacing: 8) {
                        if let r = meta?.releaseInfo { Text(r) }
                        if let rt = meta?.runtime { Text(rt) }
                        if let rating = meta?.imdbRating {
                            Label(rating, systemImage: "star.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ meta: MetaDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            playButton(meta)
                .padding(.horizontal)

            if !meta.genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(meta.genres, id: \.self) { Pill(text: $0) }
                    }
                    .padding(.horizontal)
                }
            }

            if let desc = meta.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(expanded ? nil : 4)
                    .onTapGesture { withAnimation { expanded.toggle() } }
                    .padding(.horizontal)
            }

            if meta.hasEpisodes {
                episodes(meta)
            }
        }
    }

    /// Resume / play button for the right video.
    @ViewBuilder
    private func playButton(_ meta: MetaDetail) -> some View {
        if let route = playRoute(meta) {
            NavigationLink(value: route.route) {
                HStack {
                    Image(systemName: "play.fill")
                    Text(route.label).fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
            }
        }
    }

    private func playRoute(_ meta: MetaDetail) -> (route: StreamRoute, label: String)? {
        let preview = meta.preview
        if !meta.hasEpisodes {
            let videoId = meta.defaultVideoId ?? meta.id
            let resume = app.resumePosition(metaId: meta.id, videoId: videoId)
            let label = resume > 0 ? "Resume from \(PlayerView.format(resume))" : "Play"
            return (StreamRoute(meta: preview, videoId: videoId, title: meta.name, subtitle: nil), label)
        }
        let eps = meta.episodes(in: nil).filter { ($0.season ?? 1) != 0 }
        // Continue where you left off, else the first episode.
        if let item = libraryItem, let vid = item.videoId, let video = meta.videos.first(where: { $0.id == vid }) {
            let resume = app.resumePosition(metaId: meta.id, videoId: vid)
            if resume > 0 {
                return (episodeRoute(meta, video), "Resume \(video.label) · \(PlayerView.format(resume))")
            }
            // Finished that one: offer the next episode.
            if let idx = eps.firstIndex(where: { $0.id == vid }), idx + 1 < eps.count {
                let next = eps[idx + 1]
                return (episodeRoute(meta, next), "Next: \(next.label)")
            }
        }
        if let first = eps.first ?? meta.videos.first {
            return (episodeRoute(meta, first), "Play \(first.label)")
        }
        return nil
    }

    private func episodeRoute(_ meta: MetaDetail, _ video: Video) -> StreamRoute {
        let sub = video.title.isEmpty ? video.label : "\(video.label) · \(video.title)"
        return StreamRoute(meta: meta.preview, videoId: video.id, title: meta.name, subtitle: sub)
    }

    // MARK: Episodes

    @ViewBuilder
    private func episodes(_ meta: MetaDetail) -> some View {
        let seasons = meta.seasons
        let current = season ?? defaultSeason(meta)
        VStack(alignment: .leading, spacing: 12) {
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { s in
                            Button {
                                season = s
                            } label: {
                                Text(s == 0 ? "Specials" : "Season \(s)")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(current == s ? Theme.accent : Theme.surface, in: Capsule())
                                    .foregroundStyle(current == s ? Color.black : Color.white)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            LazyVStack(spacing: 10) {
                ForEach(meta.episodes(in: seasons.isEmpty ? nil : current)) { video in
                    NavigationLink(value: episodeRoute(meta, video)) {
                        EpisodeRow(video: video,
                                   isCurrent: libraryItem?.videoId == video.id,
                                   progress: libraryItem?.videoId == video.id ? libraryItem?.progress ?? 0 : 0)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func defaultSeason(_ meta: MetaDetail) -> Int? {
        if let vid = libraryItem?.videoId, let s = meta.videos.first(where: { $0.id == vid })?.season {
            return s
        }
        return meta.seasons.first
    }

    private func load() async {
        guard meta == nil else { return }
        do {
            meta = try await AddonClient.meta(addons: app.addons, type: route.type, id: route.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EpisodeRow: View {
    let video: Video
    var isCurrent: Bool
    var progress: Double

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private var unreleased: Bool {
        guard let r = video.released else { return false }
        return r > Date()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: video.thumbnail)
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottom) {
                    if progress > 0 {
                        GeometryReader { geo in
                            Rectangle().fill(Theme.accent).frame(width: geo.size.width * progress)
                        }
                        .frame(height: 3)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(video.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isCurrent ? Theme.accent : Color.secondary)
                    if unreleased { Pill(text: "UPCOMING") }
                }
                Text(video.title.isEmpty ? video.label : video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let date = video.released {
                    Text(Self.dateFormat.string(from: date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(isCurrent ? Theme.surfaceStrong : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .opacity(unreleased ? 0.5 : 1)
    }
}
