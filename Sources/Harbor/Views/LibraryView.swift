import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var filter = "all"

    private var types: [String] {
        let set = Set(app.libraryItems.map(\.type))
        return ["all"] + set.sorted()
    }

    private var items: [LibraryItem] {
        filter == "all" ? app.libraryItems : app.libraryItems.filter { $0.type == filter }
    }

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if types.count > 2 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(types, id: \.self) { type in
                                Button {
                                    filter = type
                                } label: {
                                    Text(type == "all" ? "All" : type.capitalizedType)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(filter == type ? Theme.accent : Theme.surface, in: Capsule())
                                        .foregroundStyle(filter == type ? Color.black : Color.white)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if items.isEmpty {
                    EmptyStateView(icon: "books.vertical",
                                   title: app.isSyncing ? "Loading…" : "Your library is empty",
                                   message: "Titles you add in Harbor on your PC (or here) show up in this tab.")
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            NavigationLink(value: MetaRoute(id: item.id, type: item.type, name: item.name, poster: item.poster)) {
                                PosterCard(meta: item.meta, width: 104, progress: item.isInContinueWatching ? item.progress : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Library")
        .refreshable { await app.sync() }
    }
}
