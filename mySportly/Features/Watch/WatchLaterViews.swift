import SwiftUI

/// "Watch Later" on a movie or show page.
struct WatchLaterButton: View {
    @Environment(AppStore.self) private var store
    let item: WatchLaterItem

    var body: some View {
        let saved = store.isInWatchLater(item.itemID)
        Button(saved ? "In Watch Later" : "Watch Later", systemImage: saved ? "bookmark.fill" : "bookmark") {
            store.toggleWatchLater(item)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .font(.headline)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHint(saved ? "Removes it from Watch Later" : "Saves it to watch later")
        .accessibilityIdentifier("vod-watch-later")
    }
}

/// The Watch Later action for a long-press menu.
struct WatchLaterMenuItem: View {
    @Environment(AppStore.self) private var store
    let item: WatchLaterItem

    var body: some View {
        if store.isInWatchLater(item.itemID) {
            Button("Remove from Watch Later", systemImage: "bookmark.slash") { store.removeFromWatchLater(item.itemID) }
        } else {
            Button("Add to Watch Later", systemImage: "bookmark") { store.toggleWatchLater(item) }
        }
    }
}

/// A saved title's poster. Opens its page once the catalog has it; a title
/// the provider no longer offers can still be removed.
struct WatchLaterCard: View {
    @Environment(AppStore.self) private var store
    let item: WatchLaterItem
    var width: CGFloat? = 112

    var body: some View {
        if item.kind == .movie, let movie = store.vod.movie(item.itemID) {
            MovieLink(movie: movie, width: width)
        } else if item.kind == .show, let show = store.vod.show(item.itemID) {
            ShowLink(show: show, width: width)
        } else {
            PosterCard(title: item.title, artwork: item.artwork, progress: nil, width: width)
                .opacity(store.vod.state == .ready ? 0.5 : 1)
                .contextMenu {
                    Button("Remove from Watch Later", systemImage: "bookmark.slash", role: .destructive) { store.removeFromWatchLater(item.itemID) }
                }
                .accessibilityHint(store.vod.state == .ready ? "Your provider no longer offers this title" : "")
                .accessibilityIdentifier("watch-later-\(item.itemID)")
        }
    }
}

/// Watch Later in My Stuff: a row per saved title.
struct WatchLaterSection: View {
    @Environment(AppStore.self) private var store
    let items: [WatchLaterItem]

    var body: some View {
        Section("Watch Later") {
            ForEach(items) { item in
                Group {
                    if item.kind == .movie, let movie = store.vod.movie(item.itemID) {
                        NavigationLink { MovieDetailView(movie: movie) } label: { label(item) }
                    } else if item.kind == .show, let show = store.vod.show(item.itemID) {
                        NavigationLink { SeriesDetailView(show: show) } label: { label(item) }
                    } else {
                        label(item).foregroundStyle(store.vod.state == .ready ? .secondary : .primary)
                    }
                }
                .swipeActions { Button("Remove", role: .destructive) { store.removeFromWatchLater(item.itemID) } }
                .contextMenu {
                    Button("Remove from Watch Later", systemImage: "bookmark.slash", role: .destructive) { store.removeFromWatchLater(item.itemID) }
                }
                .accessibilityIdentifier("my-stuff-later-\(item.itemID)")
            }
        }
        // The catalog decides which saved titles can open.
        .task { await store.loadVOD() }
    }

    private func label(_ item: WatchLaterItem) -> some View {
        HStack(spacing: 12) {
            Poster(url: item.artwork, title: item.title).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(2)
                Text([item.kind == .movie ? "Movie" : "TV Show", item.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
