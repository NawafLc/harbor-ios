import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel

    private struct Rail: Identifiable {
        let addon: Addon
        let catalog: CatalogDef
        var id: String { addon.transportUrl + "|" + catalog.type + "|" + catalog.id }
    }

    /// Every catalog from your addons that can be shown without extra input, in addon order.
    private var rails: [Rail] {
        var out: [Rail] = []
        var seen = Set<String>()
        for addon in app.addons {
            for catalog in addon.manifest.catalogs where catalog.isBrowsable {
                let rail = Rail(addon: addon, catalog: catalog)
                if seen.insert(rail.id).inserted { out.append(rail) }
            }
        }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let error = app.syncError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.dub)
                        .padding(.horizontal)
                }

                if !app.continueWatching.isEmpty {
                    continueWatching
                }

                if app.addons.isEmpty {
                    if app.isSyncing {
                        ProgressView("Loading your addons…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        EmptyStateView(icon: "puzzlepiece.extension",
                                       title: "No addons",
                                       message: "Add addons to your Stremio account (in Harbor on your PC) and pull to refresh.")
                    }
                }

                ForEach(rails) { rail in
                    CatalogRail(addon: rail.addon, catalog: rail.catalog)
                }
            }
            .padding(.vertical)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Harbor")
        .refreshable { await app.sync() }
    }

    private var continueWatching: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailHeader(title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(app.continueWatching) { item in
                        NavigationLink(value: MetaRoute(id: item.id, type: item.type, name: item.name, poster: item.poster)) {
                            PosterCard(meta: item.meta, progress: item.progress)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                app.dismissContinueWatching(item.id)
                            } label: {
                                Label("Remove from Continue Watching", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct CatalogRail: View {
    let addon: Addon
    let catalog: CatalogDef

    @State private var items: [MetaPreview] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Theme.surface)
                                    .frame(width: 112, height: 168)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            } else if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(items) { meta in
                                NavigationLink(value: MetaRoute(id: meta.id, type: meta.type, name: meta.name, poster: meta.poster)) {
                                    PosterCard(meta: meta)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .task(id: addon.transportUrl + catalog.type + catalog.id) {
            guard !loaded else { return }
            let result = (try? await AddonClient.catalog(addon, catalog)) ?? []
            items = result
            loaded = true
        }
    }

    private var header: some View {
        RailHeader(title: catalog.name ?? catalog.id, subtitle: catalog.type.capitalizedType)
    }
}
