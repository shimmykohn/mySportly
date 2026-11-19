import Foundation
import Observation

/// Movies and shows from every Xtream source, loaded the first time they're
/// needed: the sealed copy on this device first, then the provider when that
/// copy is missing or a day old.
@MainActor @Observable final class VODLibrary {
    enum State: Equatable { case idle, loading, ready, failed(String) }

    private(set) var state: State = .idle
    private(set) var refreshing = false
    /// Set when a refresh fails but a saved copy is still shown.
    private(set) var refreshProblem: String?
    private(set) var movies: [Movie] = []
    private(set) var series: [Series] = []
    private(set) var movieRows: [VODShelfRow<Movie>] = []
    private(set) var seriesRows: [VODShelfRow<Series>] = []
    private(set) var recentMovies: [Movie] = []
    /// Bumped whenever the lists change, for views that derive from them.
    private(set) var revision = 0
    @ObservationIgnored private var catalogs: [UUID: VODCatalog] = [:]
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var movieDetails: [String: MovieDetail] = [:]
    @ObservationIgnored private var seriesDetails: [String: SeriesDetail] = [:]
    /// The AI's titles, genres and copies, by raw provider title.
    @ObservationIgnored private var decisions = VODDecisions()
    /// Item ID → genre, for the Watch filter.
    private(set) var genres: [String: String] = [:]
    /// The other copies (qualities, languages) folded into a movie or show, by its ID.
    private(set) var versions: [String: [String]] = [:]
    @ObservationIgnored private var hiddenCopies: [String: Movie] = [:]
    @ObservationIgnored private var hiddenShows: [String: Series] = [:]
    /// Which languages the shelves show, and each title's language by ID.
    @ObservationIgnored private var languages = VODLanguages()
    @ObservationIgnored private var itemLanguages: [String: String] = [:]
    /// Languages with titles in the catalog, most titles first.
    private(set) var availableLanguages: [String] = []
    /// Titles the language choice keeps off the shelves.
    private(set) var hiddenByLanguage = (movies: 0, shows: 0)
    @ObservationIgnored private var publishGeneration = 0
    /// Positions in `movies` and `series` by ID, for posters that look one up.
    @ObservationIgnored private var movieIndex: [String: Int] = [:]
    @ObservationIgnored private var showIndex: [String: Int] = [:]
    /// Built the first time TMDB's titles are looked for, once per revision.
    @ObservationIgnored private var tmdbIndex: (revision: Int, movies: TMDBLibraryIndex<Movie>, shows: TMDBLibraryIndex<Series>)?

    var hasContent: Bool { !movies.isEmpty || !series.isEmpty }

    func movie(_ id: String) -> Movie? { movieIndex[id].map { movies[$0] } ?? hiddenCopies[id] }
    func show(_ id: String) -> Series? { showIndex[id].map { series[$0] } ?? hiddenShows[id] }
    /// The other copies of a movie, for "Other Versions".
    func versions(of movie: Movie) -> [Movie] { (versions[movie.id] ?? []).compactMap { hiddenCopies[$0] } }
    func versions(of show: Series) -> [Series] { (versions[show.id] ?? []).compactMap { hiddenShows[$0] } }
    /// Raw titles of folded copies, so the AI keeps answering for them.
    var versionTitles: (movies: [String], shows: [String]) { (hiddenCopies.values.map(\.rawTitle), hiddenShows.values.map(\.rawTitle)) }
    /// Genres present, for the filter menu.
    var genreList: [String] { Array(Set(genres.values)).sorted() }

    /// Loads once per launch; `force` refetches every source (pull to refresh).
    func load(sources: [TVSource], provider: ProviderClient, cache: CatalogCache, demo: Bool, force: Bool = false) async {
        if let loadTask { return await loadTask.value }
        guard force || state == .idle || isStale else { return }
        let task = Task { await run(sources: sources, provider: provider, cache: cache, demo: demo, force: force) }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private var isStale: Bool { catalogs.values.contains { $0.isStale(at: .now) } }

    private func run(sources: [TVSource], provider: ProviderClient, cache: CatalogCache, demo: Bool, force: Bool) async {
        if demo {
            catalogs = [SampleVOD.sourceID: SampleVOD.catalog]
            await publish(); state = .ready; return
        }
        let xtream = sources.filter { $0.kind == .xtream }
        catalogs = catalogs.filter { id, _ in xtream.contains { $0.id == id } }
        if catalogs.isEmpty, state != .ready { state = .loading }
        // Saved copies first, so the tab fills right away.
        for source in xtream where catalogs[source.id] == nil {
            if let saved = await cache.loadVOD(source.id) { catalogs[source.id] = saved }
        }
        if !catalogs.isEmpty { await publish(); state = .ready }
        let due = xtream.filter { force || catalogs[$0.id]?.isStale(at: .now) ?? true }
        guard !due.isEmpty else { state = .ready; return }
        refreshing = true
        var failure: String?
        for source in due {
            do {
                let secrets = try KeychainStore.credentials(source.id) ?? SourceSecrets()
                let fresh = try await provider.vodCatalog(source, secrets: secrets)
                // A provider hiccup (a busy account, an error page) can come
                // back as an empty list; keep the saved one instead of
                // blanking the shelf, and try again next time.
                let kept = VODCatalog.keepingSaved(fresh: fresh, saved: catalogs[source.id])
                catalogs[source.id] = kept.catalog
                if kept.complete { try? await cache.saveVOD(kept.catalog) }
                else { failure = "Your provider sent an empty list. Showing the saved one." }
            } catch is CancellationError { break }
            catch { failure = (error as? LocalizedError)?.errorDescription ?? "Couldn’t refresh movies and shows." }
        }
        refreshing = false
        await publish()
        if catalogs.isEmpty, let failure { state = .failed(failure) } else { state = .ready }
        refreshProblem = failure != nil && !catalogs.isEmpty ? "Couldn’t refresh movies and shows. Showing the saved list." : nil
    }

    /// Shows only titles in these languages (plus untagged ones, by default).
    func setLanguages(_ languages: VODLanguages) async {
        guard languages != self.languages else { return }
        self.languages = languages
        if !catalogs.isEmpty { await publish() }
    }

    /// A title's language code, or "" when nothing tags it.
    func language(of itemID: String) -> String { itemLanguages[itemID] ?? "" }

    /// Rows and lists are built off the main actor; catalogs can hold 50,000+ titles.
    func apply(_ decisions: VODDecisions) async {
        guard decisions != self.decisions else { return }
        self.decisions = decisions
        if !catalogs.isEmpty { await publish() }
    }

    private struct Built: Sendable {
        var movies: [Movie], series: [Series], movieRows: [VODShelfRow<Movie>], seriesRows: [VODShelfRow<Series>], recent: [Movie]
        var genres: [String: String], versions: [String: [String]], hiddenMovies: [String: Movie], hiddenSeries: [String: Series]
        var languages: [String: String], available: [String], hidden: (movies: Int, shows: Int)
        var movieIndex: [String: Int], showIndex: [String: Int]
    }

    private func publish() async {
        let catalogs = Array(catalogs.values), decisions = decisions, scope = languages
        publishGeneration += 1
        let generation = publishGeneration
        let built = await Task.detached(priority: .userInitiated) { () -> Built in
            var movies = catalogs.flatMap(\.movies), series = catalogs.flatMap(\.series)
            for index in movies.indices { if let title = decisions.titles[movies[index].rawTitle] { movies[index].title = title } }
            for index in series.indices { if let title = decisions.titles[series[index].rawTitle] { series[index].title = title } }
            let movieCategories = Dictionary(catalogs.map { ($0.sourceID, $0.movieCategories) }, uniquingKeysWith: { a, _ in a })
            let seriesCategories = Dictionary(catalogs.map { ($0.sourceID, $0.seriesCategories) }, uniquingKeysWith: { a, _ in a })
            // Each title's language, from its own tags or its folder's.
            var language: [String: String] = [:]
            let movieFolders = VODShelf.categoryNames(movies, categories: movieCategories)
            let showFolders = VODShelf.categoryNames(series, categories: seriesCategories)
            for movie in movies { language[movie.id] = VODLanguage.detect(category: movieFolders[movie.id] ?? "", title: movie.rawTitle) }
            for show in series { language[show.id] = VODLanguage.detect(category: showFolders[show.id] ?? "", title: show.rawTitle) }
            // A copy in the user's language stands for the others.
            let (shownMovies, movieCopies, hiddenMovies) = VODCopies.fold(movies, copies: decisions.copies) { scope.rank(language[$0.id] ?? "") }
            let (shownSeries, seriesCopies, hiddenSeries) = VODCopies.fold(series, copies: decisions.copies) { scope.rank(language[$0.id] ?? "") }
            let movieShelf = shownMovies.filter { scope.includes(language[$0.id] ?? "") }
            let seriesShelf = shownSeries.filter { scope.includes(language[$0.id] ?? "") }
            var genres: [String: String] = [:]
            for movie in movies { if let genre = decisions.genres[movie.rawTitle] { genres[movie.id] = genre } }
            for show in series { if let genre = decisions.genres[show.rawTitle] { genres[show.id] = genre } }
            var counts: [String: Int] = [:]
            for code in language.values where !code.isEmpty { counts[code, default: 0] += 1 }
            let available = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
            return Built(movies: shownMovies, series: shownSeries,
                         movieRows: VODShelf.rows(movieShelf, categories: movieCategories), seriesRows: VODShelf.rows(seriesShelf, categories: seriesCategories),
                         recent: VODShelf.recentMovies(movieShelf), genres: genres, versions: movieCopies.merging(seriesCopies) { a, _ in a },
                         hiddenMovies: hiddenMovies, hiddenSeries: hiddenSeries, languages: language, available: available,
                         hidden: (shownMovies.count - movieShelf.count, shownSeries.count - seriesShelf.count),
                         movieIndex: Dictionary(shownMovies.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }),
                         showIndex: Dictionary(shownSeries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }))
        }.value
        // A newer build (another language or answers) already started.
        guard generation == publishGeneration else { return }
        (movies, series, movieRows, seriesRows, recentMovies) = (built.movies, built.series, built.movieRows, built.seriesRows, built.recent)
        (genres, versions, hiddenCopies, hiddenShows) = (built.genres, built.versions, built.hiddenMovies, built.hiddenSeries)
        (itemLanguages, availableLanguages, hiddenByLanguage) = (built.languages, built.available, built.hidden)
        (movieIndex, showIndex) = (built.movieIndex, built.showIndex)
        tmdbIndex = nil
        revision += 1
    }

    func forget(_ sourceID: UUID, cache: CatalogCache) async {
        catalogs.removeValue(forKey: sourceID)
        await cache.removeVOD(sourceID)
        await publish()
    }

    // MARK: Details, fetched when a page opens

    func detail(for movie: Movie, provider: ProviderClient, demo: Bool) async -> MovieDetail? {
        if let saved = movieDetails[movie.id] { return saved }
        if demo { return SampleVOD.movieDetail(movie) }
        guard let secrets = try? KeychainStore.credentials(movie.sourceID),
              let detail = try? await provider.movieDetail(movie, secrets: secrets) else { return nil }
        movieDetails[movie.id] = detail
        return detail
    }

    func detail(for show: Series, provider: ProviderClient, demo: Bool) async -> SeriesDetail? {
        if let saved = seriesDetails[show.id] { return saved }
        if demo { return SampleVOD.seriesDetail(show) }
        guard let secrets = try? KeychainStore.credentials(show.sourceID),
              let detail = try? await provider.seriesDetail(show, secrets: secrets) else { return nil }
        seriesDetails[show.id] = detail
        return detail
    }

    // MARK: TMDB's titles in the library

    /// TMDB's recommendations or a collection's parts that are in the library,
    /// in TMDB's order. `known` holds TMDB ids matched before, by item ID.
    func movies(matching references: [TMDBReference], known: [String: Int], excluding: Set<String>) async -> [Movie] {
        guard !references.isEmpty else { return [] }
        return await index().movies.matches(references, known: known, excluding: excluding)
    }

    func shows(matching references: [TMDBReference], known: [String: Int], excluding: Set<String>) async -> [Series] {
        guard !references.isEmpty else { return [] }
        return await index().shows.matches(references, known: known, excluding: excluding)
    }

    private func index() async -> (movies: TMDBLibraryIndex<Movie>, shows: TMDBLibraryIndex<Series>) {
        if let tmdbIndex, tmdbIndex.revision == revision { return (tmdbIndex.movies, tmdbIndex.shows) }
        let movies = movies, series = series, revision = revision
        let built = await Task.detached(priority: .userInitiated) { (movies: TMDBLibraryIndex(movies), shows: TMDBLibraryIndex(series)) }.value
        tmdbIndex = (revision, built.movies, built.shows)
        return built
    }
}
