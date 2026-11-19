import Foundation

/// TMDB for movie and show pages and the Continue Watching hero. On with a
/// token; off in the demo, whose titles are made up.
extension AppStore {
    var tmdbEnabled: Bool { tmdb.configured && !demo }

    func tmdbTitle(for lookup: TMDBLookup) async -> TMDBTitle? {
        tmdbEnabled ? await tmdb.title(for: lookup) : nil
    }

    /// What this device saved, to show while the provider's details load.
    func savedTMDBTitle(_ key: String, kind: TMDBKind) async -> TMDBTitle? {
        tmdbEnabled ? await tmdb.saved(key, kind: kind) : nil
    }

    /// Continue Watching's movie or show. Until the library has loaded, only
    /// a match saved from its page is used.
    func tmdbTitle(continuing item: WatchProgress) async -> TMDBTitle? {
        guard tmdbEnabled else { return nil }
        switch item.kind {
        case .movie:
            if let movie = vod.movie(item.itemID) { return await tmdb.title(for: .movie(movie, detail: nil)) }
            return await tmdb.title(for: TMDBLookup(key: item.itemID, kind: .movie, title: item.title), searching: false)
        case .episode:
            guard let showID = item.seriesID else { return nil }
            if let show = vod.show(showID) { return await tmdb.title(for: .show(show, detail: nil)) }
            return await tmdb.title(for: TMDBLookup(key: showID, kind: .tv, title: item.title), searching: false)
        }
    }

    /// TMDB's movies (recommendations, a collection's parts) that are in the
    /// library, other than `movie` itself (TMDB's `tmdbID`).
    func libraryMovies(_ references: [TMDBReference], besides movie: Movie, tmdbID: Int) async -> [Movie] {
        guard tmdbEnabled else { return [] }
        return await vod.movies(matching: references.filter { $0.id != tmdbID }, known: tmdb.knownMatches(), excluding: [movie.id])
    }

    func libraryShows(_ references: [TMDBReference], besides show: Series, tmdbID: Int) async -> [Series] {
        guard tmdbEnabled else { return [] }
        return await vod.shows(matching: references.filter { $0.id != tmdbID }, known: tmdb.knownMatches(), excluding: [show.id])
    }
}
