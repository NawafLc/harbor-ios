import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var app: AppModel
    @State private var query = ""
    @State private var results: [SearchGroup] = []
    @State private var searching = false

    struct SearchGroup: Identifiable {
        let id: String
        let title: String
        let type: String
        let items: [MetaPreview]
        let order: Int
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    EmptyStateView(icon: "magnifyingglass",
                                   title: "Search your addons",
                                   message: "Movies, series and anime from every addon on your account.")
                } else if searching && results.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if !searching && results.isEmpty {
                    EmptyStateView(icon: "questionmark.circle", title: "No results for \u{201C}\(query)\u{201D}")
                }

                ForEach(results) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        RailHeader(title: group.title, subtitle: group.type.capitalizedType)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(group.items) { meta in
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
            .padding(.vertical)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search titles")
        .autocorrectionDisabled()
        .task(id: query) {
            await runSearch()
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            searching = false
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }

        searching = true
        results = []
        var targets: [(Int, Addon, CatalogDef)] = []
        var order = 0
        for addon in app.addons {
            for catalog in addon.manifest.catalogs where catalog.isSearchable {
                targets.append((order, addon, catalog))
                order += 1
            }
        }

        await withTaskGroup(of: SearchGroup?.self) { group in
            for (index, addon, catalog) in targets {
                group.addTask {
                    guard let items = try? await AddonClient.catalog(addon, catalog, search: q), !items.isEmpty else {
                        return nil
                    }
                    return SearchGroup(id: addon.transportUrl + catalog.type + catalog.id,
                                       title: catalog.name ?? addon.manifest.name,
                                       type: catalog.type,
                                       items: items,
                                       order: index)
                }
            }
            for await result in group {
                guard !Task.isCancelled else { return }
                if let result {
                    results.append(result)
                    results.sort { $0.order < $1.order }
                }
            }
        }
        if !Task.isCancelled { searching = false }
    }
}
