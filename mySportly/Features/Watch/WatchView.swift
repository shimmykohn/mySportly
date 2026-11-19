import SwiftUI

/// The Watch tab: the provider's movies and shows, in poster shelves.
struct WatchView: View {
    enum Shelf: String, CaseIterable, Identifiable { case movies = "Movies", shows = "TV Shows"; var id: Self { self } }
    @Environment(AppStore.self) private var store
    @State private var shelf = Shelf.movies
    @State private var filter = VODFilter()
    @State private var filtered = Filtered()
    @State private var decades: [Int] = []

    /// Filter results, worked out off the main thread: catalogs can be large.
    struct Filtered { var movies: [Movie] = []; var shows: [Series] = []; var ready = false }
    private struct FilterKey: Equatable { let filter: VODFilter; let shelf: Shelf; let revision: Int; let watched: Set<String> }

    var body: some View {
        let library = store.vod
        let watched = watchedIDs
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Picker("Show", selection: $shelf) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityIdentifier("watch-shelf")

                if filter.isActive {
                    FilteredGrid(shelf: shelf, filtered: filtered) { filter = VODFilter() }
                } else {
                    shelves(library)
                }
                if let problem = library.refreshProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
        .overlay { emptyState }
        .navigationTitle("Watch")
        .toolbar {
            if library.refreshing { ToolbarItem(placement: .topBarTrailing) { ProgressView() } }
            ToolbarItem(placement: .topBarTrailing) { filterMenu(library) }
        }
        .refreshable { await store.loadVOD(force: true) }
        .task { await store.loadVOD() }
        .onChange(of: shelf) { _, _ in filter.category = nil; filter.decade = nil }
        .task(id: FilterKey(filter: filter, shelf: shelf, revision: library.revision, watched: watched)) {
            let filter = filter, movieRows = library.movieRows, seriesRows = library.seriesRows, shelf = shelf, genres = library.genres
            let result = await Task.detached(priority: .userInitiated) {
                shelf == .movies
                    ? (Filtered(movies: filter.isActive ? filter.apply(movieRows, watched: watched, genres: genres) : [], ready: true), VODFilter.decades(movieRows.flatMap(\.items)))
                    : (Filtered(shows: filter.isActive ? filter.apply(seriesRows, watched: watched, genres: genres) : [], ready: true), VODFilter.decades(seriesRows.flatMap(\.items)))
            }.value
            guard !Task.isCancelled else { return }
            (filtered, decades) = result
        }
        .accessibilityIdentifier("watch-root")
    }

    /// Finished movies, and shows with any episode started or finished.
    private var watchedIDs: Set<String> {
        guard filter.unwatched else { return [] }
        let progress = store.watchProgress.values
        return shelf == .movies ? Set(progress.filter { $0.kind == .movie && $0.isFinished }.map(\.itemID)) : Set(progress.compactMap(\.seriesID))
    }

    private func filterMenu(_ library: VODLibrary) -> some View {
        Menu {
            Picker("Sort By", selection: $filter.sort) {
                ForEach(VODFilter.Sort.allCases, id: \.self) { sort in
                    if sort != .recent || shelf == .movies { Text(sort.rawValue).tag(sort) }
                }
            }
            Picker("Category", selection: $filter.category) {
                Text("All Categories").tag(String?.none)
                ForEach((shelf == .movies ? library.movieRows.map(\.title) : library.seriesRows.map(\.title)), id: \.self) { Text($0).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            if !library.genreList.isEmpty {
                Picker("Genre", selection: $filter.genre) {
                    Text("All Genres").tag(String?.none)
                    ForEach(library.genreList, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            if !decades.isEmpty {
                Picker("Decade", selection: $filter.decade) {
                    Text("Any Year").tag(Int?.none)
                    ForEach(decades, id: \.self) { Text("\(String($0))s").tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }
            Toggle(shelf == .movies ? "Unwatched Only" : "Not Started Only", isOn: $filter.unwatched)
            if filter.isActive {
                Button("Reset", systemImage: "arrow.counterclockwise", role: .destructive) { filter = VODFilter() }
            }
        } label: {
            Label("Filter", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("watch-filter")
    }

    @ViewBuilder private func shelves(_ library: VODLibrary) -> some View {
        let saved = Downloads.shared.list(shelf == .movies ? .movie : .episode)
        if !saved.isEmpty {
            HomeRow(title: "Downloads", identifier: "watch-downloads") {
                ForEach(saved) { DownloadCard(record: $0) }
            }
        }
        let continuing = store.continueWatching.filter { shelf == .movies ? $0.kind == .movie : $0.kind == .episode }
        if !continuing.isEmpty {
            HomeRow(title: "Continue Watching", identifier: "watch-continue") {
                ForEach(continuing) { ContinueCard(item: $0) }
            }
        }
        if library.hasContent ? (shelf == .movies ? library.movieRows.isEmpty : library.seriesRows.isEmpty) : !Downloads.shared.records.isEmpty {
            shelfStatus(library)
        }
        switch shelf {
        case .movies:
            if !library.recentMovies.isEmpty {
                HomeRow(title: VODShelf.recentlyAdded, identifier: "watch-recent") {
                    ForEach(library.recentMovies) { MovieLink(movie: $0) }
                }
            }
            ForEach(library.movieRows) { row in
                ShelfRow(title: row.title, identifier: "watch-row-\(row.id)") {
                    ForEach(row.items.prefix(20)) { MovieLink(movie: $0) }
                } all: { VODGrid(title: row.title, movies: row.items) }
            }
        case .shows:
            ForEach(library.seriesRows) { row in
                ShelfRow(title: row.title, identifier: "watch-row-\(row.id)") {
                    ForEach(row.items.prefix(20)) { ShowLink(show: $0) }
                } all: { VODGrid(title: row.title, shows: row.items) }
            }
        }
    }

    /// This side has nothing to show while the other may: say why, and offer a refresh.
    @ViewBuilder private func shelfStatus(_ library: VODLibrary) -> some View {
        Group {
            switch library.state {
            case .idle, .loading: ProgressView("Loading movies and shows…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t Load", systemImage: "wifi.exclamationmark")
                } description: { Text(message) } actions: {
                    Button("Try Again") { Task { await store.loadVOD(force: true) } }.buttonStyle(.bordered)
                }
            case .ready:
                ContentUnavailableView {
                    Label(shelf == .movies ? "No Movies" : "No TV Shows", systemImage: "film.stack")
                } description: {
                    Text("Your provider didn’t send any \(shelf == .movies ? "movies" : "shows") this time.")
                } actions: {
                    Button("Refresh") { Task { await store.loadVOD(force: true) } }.buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityIdentifier("watch-shelf-status")
    }

    @ViewBuilder private var emptyState: some View {
        let library = store.vod
        // Downloads stay reachable offline, without the catalog.
        if !library.hasContent && Downloads.shared.records.isEmpty {
            if !store.demo && !store.sources.contains(where: { $0.kind == .xtream }) {
                ContentUnavailableView {
                    Label("Movies and Shows", systemImage: "play.rectangle.on.rectangle")
                } description: {
                    Text("Connect an Xtream source to watch its movies and TV shows.")
                } actions: {
                    Button("Connect a Source") { store.showSetup = true }.buttonStyle(.borderedProminent)
                }
            } else {
                switch library.state {
                case .idle, .loading: ProgressView("Loading movies and shows…")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Load", systemImage: "wifi.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try Again") { Task { await store.loadVOD(force: true) } }.buttonStyle(.bordered)
                    }
                case .ready:
                    ContentUnavailableView("No Movies or Shows", systemImage: "film.stack",
                                           description: Text("Your provider doesn’t offer movies or TV shows."))
                }
            }
        }
    }
}

/// Filter results as a poster grid, with the count and a way back.
private struct FilteredGrid: View {
    let shelf: WatchView.Shelf
    let filtered: WatchView.Filtered
    let reset: () -> Void

    var body: some View {
        let count = shelf == .movies ? filtered.movies.count : filtered.shows.count
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(filtered.ready ? "\(count.formatted()) \(count == 1 ? "Title" : "Titles")" : "Filtering…").font(.headline)
                Spacer()
                Button("Clear Filters", action: reset).font(.subheadline)
            }
            .padding(.horizontal)
            if filtered.ready && count == 0 {
                ContentUnavailableView("No Matches", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try fewer filters."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], spacing: 18) {
                if shelf == .movies { ForEach(filtered.movies) { MovieLink(movie: $0, width: nil) } }
                else { ForEach(filtered.shows) { ShowLink(show: $0, width: nil) } }
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier("watch-filtered")
    }
}

/// A shelf whose title opens the whole category.
private struct ShelfRow<Content: View, All: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder let content: Content
    @ViewBuilder let all: All

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { all } label: {
                HStack(spacing: 4) {
                    Text(title).font(.headline)
                    Image(systemName: "chevron.forward").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) { content }
                    .scrollTargetLayout()
                    .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// Every title in a category.
struct VODGrid: View {
    let title: String
    var movies: [Movie] = []
    var shows: [Series] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], spacing: 18) {
                ForEach(movies) { MovieLink(movie: $0, width: nil) }
                ForEach(shows) { ShowLink(show: $0, width: nil) }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MovieLink: View {
    @Environment(AppStore.self) private var store
    let movie: Movie
    var width: CGFloat? = 112
    var body: some View {
        NavigationLink { MovieDetailView(movie: movie) } label: {
            PosterCard(title: movie.title, artwork: movie.poster, progress: store.progress(for: movie.id), width: width)
        }
        .buttonStyle(.plain)
        .contextMenu { MovieMenu(movie: movie) }
        .accessibilityIdentifier("movie-\(movie.id)")
    }
}

struct ShowLink: View {
    @Environment(AppStore.self) private var store
    let show: Series
    var width: CGFloat? = 112
    var body: some View {
        NavigationLink { SeriesDetailView(show: show) } label: {
            PosterCard(title: show.title, artwork: show.poster, progress: nil, width: width)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { store.playNext(of: show) }
        }
        .accessibilityIdentifier("show-\(show.id)")
    }
}

/// Long-press actions for a movie, wherever it appears.
struct MovieMenu: View {
    @Environment(AppStore.self) private var store
    let movie: Movie
    var body: some View {
        let progress = store.progressItem(for: movie)
        Button(progress.resumePosition != nil ? "Resume" : "Play", systemImage: "play.fill") { store.play(movie) }
        if progress.resumePosition != nil {
            Button("Play from Beginning", systemImage: "arrow.counterclockwise") { store.play(movie, fromStart: true) }
        }
        Button(progress.isFinished ? "Mark as Unwatched" : "Mark as Watched", systemImage: progress.isFinished ? "circle" : "checkmark.circle") {
            store.setWatched(progress, !progress.isFinished)
        }
        DownloadMenuItems(item: progress)
        ExternalPlayItems(item: progress)
    }
}

/// A 2:3 poster with its title under it, and a progress bar once started.
struct PosterCard: View {
    let title: String
    let artwork: URL?
    let progress: WatchProgress?
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Poster(url: artwork, title: title)
                .overlay(alignment: .bottom) {
                    if let progress, progress.resumePosition != nil {
                        ProgressView(value: progress.fraction).tint(.white).padding(8)
                    } else if progress?.isFinished == true {
                        Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .tint)
                            .padding(6).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            Text(title).font(.caption).lineLimit(1).foregroundStyle(.primary)
        }
        .frame(width: width)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Artwork, or a quiet stand-in with the title when the provider has none.
struct Poster: View {
    let url: URL?
    let title: String
    var ratio: CGFloat = 2 / 3

    var body: some View {
        Rectangle().fill(.fill.tertiary)
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else {
                        VStack(spacing: 6) {
                            Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
                            Text(title).font(.caption2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3).foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

/// A started title: tap to pick up where it stopped.
struct ContinueCard: View {
    @Environment(AppStore.self) private var store
    let item: WatchProgress

    var body: some View {
        Button { store.resume(item) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Poster(url: item.artwork, title: item.title)
                    .overlay(alignment: .bottom) { ProgressView(value: item.fraction).tint(.white).padding(8) }
                Text(item.title).font(.caption).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(width: 112)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Mark as Watched", systemImage: "checkmark.circle") { store.setWatched(item, true) }
            DownloadMenuItems(item: item)
            Button("Remove from Continue Watching", systemImage: "minus.circle", role: .destructive) { store.clearProgress(item) }
        }
        .accessibilityLabel("Resume \(item.title)")
        .accessibilityIdentifier("continue-\(item.itemID)")
    }
}

extension Double {
    /// "1 hr 52 min" / "48 min"
    var watchDuration: String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = self >= 3600 ? [.hours, .minutes] : [.minutes]
        return Duration.seconds(self).formatted(.units(allowed: units, width: .abbreviated))
    }
}
