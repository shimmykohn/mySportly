import SwiftUI

/// A movie: artwork, Play or Resume, then the details. With a TMDB token,
/// also TMDB's backdrops, logo, rating, trailer, cast and related titles.
struct MovieDetailView: View {
    @Environment(AppStore.self) private var store
    let movie: Movie
    @State private var detail: MovieDetail?
    @State private var tmdb: TMDBTitle?
    /// TMDB's recommendations and the collection's other parts, from the library.
    @State private var similar: [Movie] = []
    @State private var collection: LibraryShelf<Movie>?

    var body: some View {
        let progress = store.progressItem(for: movie)
        let duration = detail?.duration ?? (progress.duration > 0 ? progress.duration : nil)
        ScrollView {
            VODHero(artwork: movie.poster, backdrop: detail?.backdrop, tmdb: tmdb, title: movie.title,
                    facts: [(movie.year ?? detail?.year).map(String.init), duration?.watchDuration, detail?.genre.nonEmpty, tmdb?.certification,
                            tmdb?.ratingText ?? movie.rating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" }])
            VStack(alignment: .leading, spacing: 20) {
                PlayRow(progress: progress) { store.play(movie) } fromStart: { store.play(movie, fromStart: true) }
                if let trailer = tmdb?.trailerURL { TrailerButton(url: trailer) }
                if let plot = detail?.plot.nonEmpty ?? tmdb?.overview.nonEmpty { Text(plot).font(.body) }
                if let director = detail?.director.nonEmpty { LabeledContent("Director", value: director).font(.subheadline) }
                // TMDB's cast row takes the place of the provider's list.
                if tmdb?.cast.isEmpty != false, let cast = detail?.cast.nonEmpty {
                    LabeledContent("Cast") { Text(cast).multilineTextAlignment(.trailing) }.font(.subheadline)
                }
                let versions = store.vod.versions(of: movie)
                if !versions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Other Versions").font(.headline)
                        ForEach(versions) { version in
                            Button { store.play(version) } label: { Label(version.rawTitle, systemImage: "play.circle") }
                                .contextMenu { MovieMenu(movie: version) }
                        }
                    }
                    .accessibilityIdentifier("movie-versions")
                }
            }
            .padding()
            if let tmdb {
                TMDBRows(cast: tmdb.cast) {
                    if let collection {
                        HomeRow(title: collection.title, identifier: "vod-collection") { ForEach(collection.items) { MovieLink(movie: $0) } }
                    }
                    if !similar.isEmpty {
                        HomeRow(title: "More Like This", identifier: "vod-more-like-this") { ForEach(similar) { MovieLink(movie: $0) } }
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task(id: store.tmdbEnabled) { await load() }
    }

    /// The provider's details, then TMDB's; a saved TMDB copy shows meanwhile.
    private func load() async {
        if tmdb == nil, let saved = await store.savedTMDBTitle(movie.id, kind: .movie), !Task.isCancelled { tmdb = saved }
        let loaded = await store.vod.detail(for: movie, provider: store.provider, demo: store.demo)
        guard !Task.isCancelled else { return }
        detail = loaded
        let found = await store.tmdbTitle(for: .movie(movie, detail: loaded))
        guard !Task.isCancelled else { return }
        tmdb = found
        guard let found else { similar = []; collection = nil; return }
        var parts: LibraryShelf<Movie>?
        if let part = found.collection, let full = await store.tmdb.collection(part.id) {
            let items = await store.libraryMovies(full.parts, besides: movie, tmdbID: found.id)
            if !items.isEmpty { parts = LibraryShelf(title: full.name.nonEmpty ?? part.title, items: items) }
        }
        let inCollection = Set(parts?.items.map(\.id) ?? [])
        let related = await store.libraryMovies(found.recommendations, besides: movie, tmdbID: found.id).filter { !inCollection.contains($0.id) }
        guard !Task.isCancelled else { return }
        collection = parts; similar = related
    }
}

/// A show: Play the next episode, then seasons and episodes. With a TMDB
/// token, also TMDB's backdrops, logo, rating, trailer, cast and related shows.
struct SeriesDetailView: View {
    @Environment(AppStore.self) private var store
    let show: Series
    @State private var detail: SeriesDetail?
    @State private var loading = true
    @State private var season = 0
    @State private var tmdb: TMDBTitle?
    /// TMDB's recommendations, from the library.
    @State private var similar: [Series] = []

    var body: some View {
        let progress = store.watchProgress
        let upNext = detail.flatMap { ContinueWatching.upNext(in: $0, progress: progress) }
        ScrollView {
            VODHero(artwork: show.poster, backdrop: detail?.backdrop, tmdb: tmdb, title: show.title,
                    facts: [show.year.map(String.init), detail.map { "\($0.seasons.count) \($0.seasons.count == 1 ? "Season" : "Seasons")" }, show.genre.nonEmpty,
                            tmdb?.certification, tmdb?.ratingText])
            VStack(alignment: .leading, spacing: 20) {
                if let upNext, let detail {
                    let item = store.progressItem(for: upNext, of: show)
                    PlayRow(progress: item, label: upNext.code) { store.play(upNext, of: show, in: detail) } fromStart: {
                        store.play(upNext, of: show, in: detail, fromStart: true)
                    }
                }
                if let trailer = tmdb?.trailerURL { TrailerButton(url: trailer) }
                if let plot = show.plot.nonEmpty ?? tmdb?.overview.nonEmpty { Text(plot).font(.body) }
                let versions = store.vod.versions(of: show)
                if !versions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Other Versions").font(.headline)
                        ForEach(versions) { version in
                            NavigationLink { SeriesDetailView(show: version) } label: { Label(version.rawTitle, systemImage: "rectangle.stack") }
                        }
                    }
                    .accessibilityIdentifier("show-versions")
                }
                if let detail, !detail.seasons.isEmpty {
                    let current = detail.seasons.first { $0.number == season } ?? detail.seasons[0]
                    Picker("Season", selection: Binding(get: { current.number }, set: { season = $0 })) {
                        ForEach(detail.seasons) { Text($0.name).tag($0.number) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityIdentifier("season-picker")
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(current.episodes) { episode in
                            EpisodeRow(episode: episode, show: show, detail: detail)
                            if episode.id != current.episodes.last?.id { Divider() }
                        }
                    }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Episodes aren’t available right now.").foregroundStyle(.secondary)
                }
            }
            .padding()
            if let tmdb {
                TMDBRows(cast: tmdb.cast) {
                    if !similar.isEmpty {
                        HomeRow(title: "More Like This", identifier: "vod-more-like-this") { ForEach(similar) { ShowLink(show: $0) } }
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .task(id: store.tmdbEnabled) {
            if tmdb == nil, let saved = await store.savedTMDBTitle(show.id, kind: .tv), !Task.isCancelled { tmdb = saved }
            let loaded = await store.vod.detail(for: show, provider: store.provider, demo: store.demo)
            guard !Task.isCancelled else { return }
            detail = loaded
            loading = false
            if let loaded, season == 0 {
                season = ContinueWatching.upNext(in: loaded, progress: store.watchProgress)?.season ?? loaded.seasons.first?.number ?? 0
            }
            let found = await store.tmdbTitle(for: .show(show, detail: loaded))
            guard !Task.isCancelled else { return }
            tmdb = found
            var related: [Series] = []
            if let found { related = await store.libraryShows(found.recommendations, besides: show, tmdbID: found.id) }
            guard !Task.isCancelled else { return }
            similar = related
        }
    }
}

private struct EpisodeRow: View {
    @Environment(AppStore.self) private var store
    let episode: Episode
    let show: Series
    let detail: SeriesDetail

    var body: some View {
        let progress = store.progressItem(for: episode, of: show)
        Button { store.play(episode, of: show, in: detail) } label: {
            HStack(alignment: .top, spacing: 12) {
                Poster(url: episode.still ?? show.poster, title: "", ratio: 16 / 9)
                    .frame(width: 128)
                    .overlay(alignment: .bottom) {
                        if progress.resumePosition != nil { ProgressView(value: progress.fraction).tint(.white).padding(6) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Episode \(episode.number)").font(.caption).foregroundStyle(.secondary)
                    Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if !episode.plot.isEmpty { Text(episode.plot).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if let duration = episode.duration { Text(duration.watchDuration).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    if progress.isFinished {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Watched")
                    }
                    DownloadBadge(itemID: episode.id)
                }
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if progress.resumePosition != nil {
                Button("Play from Beginning", systemImage: "arrow.counterclockwise") { store.play(episode, of: show, in: detail, fromStart: true) }
            }
            Button(progress.isFinished ? "Mark as Unwatched" : "Mark as Watched", systemImage: progress.isFinished ? "circle" : "checkmark.circle") {
                store.setWatched(progress, !progress.isFinished)
            }
            DownloadMenuItems(item: progress)
            ExternalPlayItems(item: progress)
        }
        .accessibilityIdentifier("episode-\(episode.id)")
    }
}

/// Artwork across the top, under the navigation bar and status bar, fading
/// into the page with the title over it, as in the TV app. With TMDB, its
/// backdrops cross-fade behind the title logo.
private struct VODHero: View {
    let artwork: URL?
    let backdrop: URL?
    let tmdb: TMDBTitle?
    let title: String
    let facts: [String?]
    /// The backdrops hold still once the hero is scrolled away.
    @State private var onScreen = true

    var body: some View {
        Color.clear
            .frame(height: 480)
            .overlay { BackdropCarousel(urls: tmdb?.backdropURLs ?? [], fallback: backdrop ?? artwork, rotating: onScreen) }
            .clipped()
            .backgroundExtensionEffect()
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.85), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    TitleLogo(url: tmdb?.logoURL, title: title, maxWidth: 300, maxHeight: 120) {
                        Text(title).font(.largeTitle.bold()).lineLimit(3).minimumScaleFactor(0.7)
                    }
                    .accessibilityAddTraits(.isHeader)
                    let line = facts.compactMap { $0 }.joined(separator: " · ")
                    if !line.isEmpty { Text(line).font(.subheadline.weight(.medium)).opacity(0.85) }
                }
                .foregroundStyle(.white)
                .padding()
            }
            .accessibilityElement(children: .combine)
            .onScrollVisibilityChange(threshold: 0.5) { onScreen = $0 }
    }
}

/// TMDB's rows under a page's details: the cast, then titles in the library.
private struct TMDBRows<Rows: View>: View {
    let cast: [TMDBCastMember]
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !cast.isEmpty { CastRow(cast: cast) }
            rows
        }
        .padding(.bottom)
    }
}

/// Library titles under a heading, such as a collection's other parts.
private struct LibraryShelf<Item> {
    let title: String
    let items: [Item]
}

/// Play (or Resume, with the time left), the watched mark and Download on
/// one line. Once watched, Play shrinks to its icon and the mark reads "Watched".
/// Long-press Play to start over or play in Infuse or VLC.
private struct PlayRow: View {
    @Environment(AppStore.self) private var store
    let progress: WatchProgress
    var label: String?
    let play: () -> Void
    let fromStart: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if progress.isFinished {
                Button("Play", systemImage: "play.fill", action: play)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                    .contextMenu { menu }
                    .accessibilityIdentifier("vod-play")
                Button { store.setWatched(progress, false) } label: {
                    Label("Watched", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityHint("Marks it as unwatched")
                .accessibilityIdentifier("vod-watched")
                DownloadButton(item: progress)
            } else {
                let resuming = progress.resumePosition != nil
                Button(action: play) {
                    VStack(spacing: 6) {
                        Label([resuming ? "Resume" : "Play", label].compactMap { $0 }.joined(separator: " "), systemImage: "play.fill")
                        if resuming {
                            HStack(spacing: 8) {
                                ProgressView(value: progress.fraction).frame(width: 80)
                                Text("\(progress.remaining.watchDuration) left").font(.caption)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .contextMenu { menu }
                .accessibilityIdentifier("vod-play")
                Button("Mark as Watched", systemImage: "checkmark") { store.setWatched(progress, true) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityIdentifier("vod-watched")
                DownloadButton(item: progress)
            }
        }
        .font(.headline)
        .controlSize(.large)
    }

    @ViewBuilder private var menu: some View {
        if progress.resumePosition != nil || progress.isFinished {
            Button("Play from Beginning", systemImage: "arrow.counterclockwise", action: fromStart)
        }
        ExternalPlayItems(item: progress)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
