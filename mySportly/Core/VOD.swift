import Foundation

// Movies and TV shows from Xtream providers ("VOD"). The catalog stays on
// this device; only watch progress syncs (as personal data).

public struct VODCategory: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct Movie: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sourceID: UUID
    public var providerID: String
    public var rawTitle: String
    public var title: String
    public var year: Int?
    public var categoryID: String
    public var poster: URL?
    public var rating: Double?
    public var added: Date?
    public var container: String
    public init(id: String, sourceID: UUID, providerID: String, rawTitle: String, title: String, year: Int? = nil, categoryID: String = "",
                poster: URL? = nil, rating: Double? = nil, added: Date? = nil, container: String = "mp4") {
        self.id = id; self.sourceID = sourceID; self.providerID = providerID; self.rawTitle = rawTitle; self.title = title; self.year = year
        self.categoryID = categoryID; self.poster = poster; self.rating = rating; self.added = added; self.container = container
    }
}

public struct Series: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sourceID: UUID
    public var providerID: String
    public var rawTitle: String
    public var title: String
    public var year: Int?
    public var categoryID: String
    public var poster: URL?
    public var plot: String
    public var genre: String
    public var rating: Double?
    public init(id: String, sourceID: UUID, providerID: String, rawTitle: String, title: String, year: Int? = nil, categoryID: String = "",
                poster: URL? = nil, plot: String = "", genre: String = "", rating: Double? = nil) {
        self.id = id; self.sourceID = sourceID; self.providerID = providerID; self.rawTitle = rawTitle; self.title = title; self.year = year
        self.categoryID = categoryID; self.poster = poster; self.plot = plot; self.genre = genre; self.rating = rating
    }
}

public struct MovieDetail: Codable, Hashable, Sendable {
    public var plot = ""
    public var duration: Double?
    public var genre = ""
    public var director = ""
    public var cast = ""
    public var backdrop: URL?
    public var year: Int?
    public init() {}
}

public struct Episode: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var providerID: String
    public var season: Int
    public var number: Int
    public var title: String
    public var plot: String
    public var duration: Double?
    public var still: URL?
    public var container: String
    public init(id: String, providerID: String, season: Int, number: Int, title: String, plot: String = "", duration: Double? = nil, still: URL? = nil, container: String = "mp4") {
        self.id = id; self.providerID = providerID; self.season = season; self.number = number; self.title = title
        self.plot = plot; self.duration = duration; self.still = still; self.container = container
    }
    /// "S1 · E3"
    public var code: String { "S\(season) · E\(number)" }
}

public struct Season: Codable, Hashable, Sendable, Identifiable {
    public var number: Int
    public var name: String
    public var episodes: [Episode]
    public var id: Int { number }
    public init(number: Int, name: String, episodes: [Episode]) { self.number = number; self.name = name; self.episodes = episodes }
}

public struct SeriesDetail: Codable, Hashable, Sendable {
    public var seasons: [Season] = []
    public var backdrop: URL?
    public init(seasons: [Season] = [], backdrop: URL? = nil) { self.seasons = seasons; self.backdrop = backdrop }
    public var episodes: [Episode] { seasons.flatMap(\.episodes) }
}

/// One source's movies and shows.
public struct VODCatalog: Codable, Sendable {
    public var sourceID: UUID
    public var fetched: Date
    public var movieCategories: [VODCategory] = []
    public var seriesCategories: [VODCategory] = []
    public var movies: [Movie] = []
    public var series: [Series] = []
    public init(sourceID: UUID, fetched: Date) { self.sourceID = sourceID; self.fetched = fetched }
    public var isEmpty: Bool { movies.isEmpty && series.isEmpty }
    /// Refetched after a day, or sooner on pull to refresh.
    public func isStale(at date: Date) -> Bool { date.timeIntervalSince(fetched) > 86_400 }
}

// MARK: - Titles

public enum VODTitle {
    private static let year = try! NSRegularExpression(pattern: #"\s*(?:[\[(]\s*((?:19|20)\d{2})\s*[\])]|[-–]\s*((?:19|20)\d{2}))\s*$"#)

    /// "EN | The Batman (2022) 4K" → ("The Batman", 2022). Display only.
    public static func clean(_ raw: String) -> (title: String, year: Int?) {
        var text = NameCleaning.local(raw)
        var found: Int?
        let range = NSRange(text.startIndex..., in: text)
        if let match = year.firstMatch(in: text, range: range) {
            let group = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            if let value = Range(group, in: text).flatMap({ Int(text[$0]) }), let whole = Range(match.range, in: text), whole.lowerBound > text.startIndex {
                found = value
                text = String(text[..<whole.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return (text.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : text, found)
    }
}

// MARK: - Xtream decoding

/// Xtream panels send numbers as strings, strings as numbers, and empty
/// values as "" or null.
struct XtreamValue: Decodable {
    let string: String
    var int: Int? { Int(string) ?? Double(string).map { Int($0) } }
    var double: Double? { Double(string) }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { string = text }
        else if let number = try? container.decode(Int.self) { string = String(number) }
        else if let number = try? container.decode(Double.self) { string = String(number) }
        else { string = "" }
    }
}

public enum XtreamVOD {
    private struct Category: Decodable { var category_id: XtreamValue; var category_name: String? }
    private struct MovieRow: Decodable {
        var stream_id: XtreamValue; var name: String?; var stream_icon: String?; var category_id: XtreamValue?
        var rating: XtreamValue?; var added: XtreamValue?; var container_extension: String?; var year: XtreamValue?
    }
    private struct SeriesRow: Decodable {
        var series_id: XtreamValue; var name: String?; var cover: String?; var category_id: XtreamValue?
        var plot: String?; var genre: String?; var rating: XtreamValue?; var releaseDate: String?; var year: XtreamValue?
    }

    /// Lenient: a row that won't decode is skipped, not fatal.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    private static func rows<T: Decodable>(_ type: T.Type, _ data: Data) -> [T] {
        ((try? JSONDecoder().decode([Lossy<T>].self, from: data)) ?? []).compactMap(\.value)
    }

    public static func categories(_ data: Data) -> [VODCategory] {
        rows(Category.self, data).compactMap { row in
            guard !row.category_id.string.isEmpty else { return nil }
            return VODCategory(id: row.category_id.string, name: row.category_name ?? "Other")
        }
    }

    public static func movies(_ data: Data, sourceID: UUID) -> [Movie] {
        var seen = Set<String>()
        return rows(MovieRow.self, data).compactMap { row in
            let provider = row.stream_id.string
            guard !provider.isEmpty, let name = row.name, !name.isEmpty, seen.insert(provider).inserted else { return nil }
            let clean = VODTitle.clean(name)
            return Movie(id: StableID.vod(source: sourceID, kind: "movie", provider: provider), sourceID: sourceID, providerID: provider,
                         rawTitle: name, title: clean.title, year: clean.year ?? row.year?.int.flatMap(validYear),
                         categoryID: row.category_id?.string ?? "", poster: url(row.stream_icon), rating: row.rating?.double.flatMap(validRating),
                         added: row.added?.double.map(Date.init(timeIntervalSince1970:)), container: container(row.container_extension))
        }
    }

    public static func series(_ data: Data, sourceID: UUID) -> [Series] {
        var seen = Set<String>()
        return rows(SeriesRow.self, data).compactMap { row in
            let provider = row.series_id.string
            guard !provider.isEmpty, let name = row.name, !name.isEmpty, seen.insert(provider).inserted else { return nil }
            let clean = VODTitle.clean(name)
            return Series(id: StableID.vod(source: sourceID, kind: "series", provider: provider), sourceID: sourceID, providerID: provider,
                          rawTitle: name, title: clean.title, year: clean.year ?? row.year?.int.flatMap(validYear) ?? year(row.releaseDate),
                          categoryID: row.category_id?.string ?? "", poster: url(row.cover), plot: row.plot ?? "", genre: row.genre ?? "",
                          rating: row.rating?.double.flatMap(validRating))
        }
    }

    private struct MovieInfo: Decodable {
        var info: Info?
        struct Info: Decodable {
            var plot: String?; var description: String?; var duration_secs: XtreamValue?; var genre: String?; var director: String?
            var cast: String?; var actors: String?; var backdrop_path: Backdrop?; var releasedate: String?; var release_date: String?
        }
    }
    /// `backdrop_path` is a list on most panels, a string on some.
    private struct Backdrop: Decodable {
        let first: String?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let list = try? container.decode([String].self) { first = list.first } else { first = try? container.decode(String.self) }
        }
    }

    public static func movieDetail(_ data: Data) -> MovieDetail {
        var detail = MovieDetail()
        guard let info = (try? JSONDecoder().decode(MovieInfo.self, from: data))?.info else { return detail }
        detail.plot = (info.plot ?? info.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        detail.duration = info.duration_secs?.double.flatMap { $0 > 0 ? $0 : nil }
        detail.genre = info.genre ?? ""
        detail.director = info.director ?? ""
        detail.cast = info.cast ?? info.actors ?? ""
        detail.backdrop = url(info.backdrop_path?.first)
        detail.year = year(info.releasedate ?? info.release_date)
        return detail
    }

    private struct SeriesInfo: Decodable {
        var seasons: [Lossy<SeasonRow>]?
        var info: Info?
        var episodes: EpisodeMap?
        struct Info: Decodable { var backdrop_path: Backdrop? }
        struct SeasonRow: Decodable { var season_number: XtreamValue?; var name: String? }
    }
    private struct EpisodeRow: Decodable {
        var id: XtreamValue; var episode_num: XtreamValue?; var title: String?; var container_extension: String?
        var season: XtreamValue?; var info: Info?
        struct Info: Decodable { var duration_secs: XtreamValue?; var plot: String?; var movie_image: String? }
    }
    /// `episodes` is keyed by season on most panels, a list of lists on some.
    private struct EpisodeMap: Decodable {
        var bySeason: [Int: [EpisodeRow]] = [:]
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let map = try? container.decode([String: [Lossy<EpisodeRow>]].self) {
                for (key, list) in map { bySeason[Int(key) ?? 0, default: []] += list.compactMap(\.value) }
            } else if let lists = try? container.decode([[Lossy<EpisodeRow>]].self) {
                for list in lists {
                    let rows = list.compactMap(\.value)
                    guard let season = rows.first?.season?.int else { continue }
                    bySeason[season, default: []] += rows
                }
            }
        }
    }

    public static func seriesDetail(_ data: Data, series: Series) -> SeriesDetail {
        guard let decoded = try? JSONDecoder().decode(SeriesInfo.self, from: data) else { return SeriesDetail() }
        let names = Dictionary((decoded.seasons ?? []).compactMap(\.value).compactMap { row in row.season_number?.int.map { ($0, row.name ?? "") } },
                               uniquingKeysWith: { a, _ in a })
        let seasons = (decoded.episodes?.bySeason ?? [:]).sorted { $0.key < $1.key }.compactMap { number, rows -> Season? in
            var seen = Set<String>()
            let episodes = rows.compactMap { row -> Episode? in
                let provider = row.id.string
                guard !provider.isEmpty, seen.insert(provider).inserted else { return nil }
                let episodeNumber = row.episode_num?.int ?? 0
                let raw = row.title ?? ""
                return Episode(id: StableID.vod(source: series.sourceID, kind: "episode", provider: provider), providerID: provider,
                               season: number, number: episodeNumber, title: episodeTitle(raw, series: series, number: episodeNumber),
                               plot: row.info?.plot ?? "", duration: row.info?.duration_secs?.double.flatMap { $0 > 0 ? $0 : nil },
                               still: url(row.info?.movie_image), container: container(row.container_extension))
            }.sorted { $0.number < $1.number }
            guard !episodes.isEmpty else { return nil }
            let name = names[number].flatMap { $0.isEmpty ? nil : $0 } ?? "Season \(number)"
            return Season(number: number, name: name, episodes: episodes)
        }
        return SeriesDetail(seasons: seasons, backdrop: url(decoded.info?.backdrop_path?.first))
    }

    /// Providers often title episodes "Show Name - S01E03 - Pilot".
    static func episodeTitle(_ raw: String, series: Series, number: Int) -> String {
        var text = NameCleaning.local(raw)
        for prefix in [series.rawTitle, series.title] where !prefix.isEmpty && text.lowercased().hasPrefix(prefix.lowercased()) {
            text = String(text.dropFirst(prefix.count)); break
        }
        text = text.replacingOccurrences(of: #"(?i)^\W*S\d{1,2}\s*E\d{1,3}\W*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–|:·").union(.whitespaces))
        return text.isEmpty ? "Episode \(number)" : text
    }

    /// `{root}/movie|series/{user}/{pass}/{id}.{ext}`
    public static func playbackURL(root: URL, path: String, username: String, password: String, providerID: String, container: String) -> URL {
        root.appending(path: path).appending(component: username).appending(component: password).appending(component: "\(providerID).\(container)")
    }

    private static func url(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty, let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
    private static func container(_ text: String?) -> String {
        let value = (text ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        return !value.isEmpty && value.count <= 5 && value.allSatisfy({ $0.isLetter || $0.isNumber }) ? value : "mp4"
    }
    private static func validYear(_ value: Int) -> Int? { (1900...2100).contains(value) ? value : nil }
    private static func validRating(_ value: Double) -> Double? { value > 0 && value <= 10 ? value : nil }
    private static func year(_ text: String?) -> Int? {
        guard let text, text.count >= 4, let value = Int(text.prefix(4)) else { return nil }
        return validYear(value)
    }
}

extension StableID {
    public static func vod(source: UUID, kind: String, provider: String) -> String { "\(kind):" + source.uuidString + ":" + hash(provider) }
}

// MARK: - Watch progress

public enum VODKind: String, Codable, Sendable { case movie, episode }

/// Where the user stopped in a movie or episode. Synced as personal data, and
/// carries what the Home card and resume need without loading the catalog.
public struct WatchProgress: Codable, Hashable, Sendable, Identifiable {
    public var itemID: String
    public var kind: VODKind
    public var sourceID: UUID
    public var providerID: String
    public var container: String
    public var title: String
    public var subtitle: String
    public var artwork: URL?
    /// The show, for episodes.
    public var seriesID: String?
    public var position: Double
    public var duration: Double
    public var updated: Date
    /// Marked watched by hand, or played to the end.
    public var watched: Bool
    public var id: String { itemID }

    public init(itemID: String, kind: VODKind, sourceID: UUID, providerID: String, container: String, title: String, subtitle: String = "",
                artwork: URL? = nil, seriesID: String? = nil, position: Double = 0, duration: Double = 0, updated: Date = .now, watched: Bool = false) {
        self.itemID = itemID; self.kind = kind; self.sourceID = sourceID; self.providerID = providerID; self.container = container
        self.title = title; self.subtitle = subtitle; self.artwork = artwork; self.seriesID = seriesID
        self.position = position; self.duration = duration; self.updated = updated; self.watched = watched
    }

    public static let resumeMinimum: Double = 30
    public static let finishMargin: Double = 120

    public var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    public var isFinished: Bool { watched || (duration > 0 && (fraction >= 0.95 || duration - position <= Self.finishMargin)) }
    /// Where to start: nil means from the beginning.
    public var resumePosition: Double? { !isFinished && position >= Self.resumeMinimum ? position : nil }
    public var remaining: Double { max(0, duration - position) }

    public static func key(_ itemID: String) -> String { "vod.progress.\(itemID)" }
}

public enum ContinueWatching {
    /// Unfinished titles, newest first; one entry per show (its latest episode).
    public static func items(_ all: [WatchProgress]) -> [WatchProgress] {
        var seenShows = Set<String>()
        return all.filter { $0.resumePosition != nil }.sorted { $0.updated > $1.updated }.filter { item in
            guard let show = item.seriesID else { return true }
            return seenShows.insert(show).inserted
        }
    }

    public static func nextEpisode(after episodeID: String, in detail: SeriesDetail) -> Episode? {
        let all = detail.episodes
        guard let index = all.firstIndex(where: { $0.id == episodeID }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// The episode to offer on a show page: the one in progress, else the one
    /// after the last finished, else the first.
    public static func upNext(in detail: SeriesDetail, progress: [String: WatchProgress]) -> Episode? {
        let all = detail.episodes
        if let current = all.filter({ progress[$0.id]?.resumePosition != nil }).max(by: { progress[$0.id]!.updated < progress[$1.id]!.updated }) { return current }
        if let last = all.lastIndex(where: { progress[$0.id]?.isFinished == true }) { return last + 1 < all.count ? all[last + 1] : nil }
        return all.first
    }
}

// MARK: - Shelves

public protocol VODItem: Sendable, Identifiable where ID == String {
    var sourceID: UUID { get }
    var categoryID: String { get }
    var title: String { get }
}
extension Movie: VODItem {}
extension Series: VODItem {}

public struct VODShelfRow<Item: VODItem>: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let items: [Item]
}

public enum VODShelf {
    public static let recentlyAdded = "Recently Added"

    /// One row per category, merged across sources by cleaned name, in the
    /// providers' order; titles without a known category go last.
    public static func rows<Item: VODItem>(_ items: [Item], categories: [UUID: [VODCategory]]) -> [VODShelfRow<Item>] {
        var order: [String] = [], names: [String: String] = [:]
        for (source, list) in categories.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            for category in list {
                let name = NameCleaning.local(category.name)
                names["\(source.uuidString)|\(category.id)"] = name
                if !order.contains(name) { order.append(name) }
            }
        }
        var grouped: [String: [Item]] = [:]
        for item in items { grouped[names["\(item.sourceID.uuidString)|\(item.categoryID)"] ?? "Other", default: []].append(item) }
        if grouped["Other"] != nil, !order.contains("Other") { order.append("Other") }
        return order.compactMap { name in grouped[name].map { VODShelfRow(id: name, title: name, items: $0) } }
    }

    public static func recentMovies(_ movies: [Movie], limit: Int = 20) -> [Movie] {
        Array(movies.filter { $0.added != nil }.sorted { $0.added! > $1.added! }.prefix(limit))
    }

    /// Title matches, prefix matches first, capped.
    public static func search<Item: VODItem>(_ query: String, in items: [Item], limit: Int = 50) -> [Item] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return [] }
        var prefix: [Item] = [], contains: [Item] = []
        for item in items where item.title.localizedStandardContains(text) {
            if item.title.lowercased().hasPrefix(text.lowercased()) { prefix.append(item) } else { contains.append(item) }
            if prefix.count >= limit { break }
        }
        return Array((prefix + contains).prefix(limit))
    }
}
