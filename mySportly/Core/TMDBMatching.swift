import Foundation

/// What the app tells TMDB about a library title: a title, a year and ids.
public struct TMDBLookup: Hashable, Sendable {
    /// The movie's or show's item ID; its match is saved under it.
    public var key: String
    public var kind: TMDBKind
    public var title: String
    public var year: Int?
    /// The provider's, when it sent them.
    public var tmdbID: Int?
    public var imdbID: String?

    public init(key: String, kind: TMDBKind, title: String, year: Int? = nil, tmdbID: Int? = nil, imdbID: String? = nil) {
        self.key = key; self.kind = kind; self.title = title; self.year = year; self.tmdbID = tmdbID; self.imdbID = imdbID
    }

    /// The shown title: `VODTitle.clean`'s, or the AI's tidier one.
    public static func movie(_ movie: Movie, detail: MovieDetail?) -> TMDBLookup {
        TMDBLookup(key: movie.id, kind: .movie, title: movie.title, year: movie.year ?? detail?.year,
                   tmdbID: detail?.tmdbID ?? movie.tmdbID, imdbID: detail?.imdbID)
    }

    public static func show(_ show: Series, detail: SeriesDetail?) -> TMDBLookup {
        TMDBLookup(key: show.id, kind: .tv, title: show.title, year: show.year, tmdbID: detail?.tmdbID ?? show.tmdbID, imdbID: detail?.imdbID)
    }
}

public enum TMDBMatch {
    /// For comparing titles: lowercase, without accents, apostrophes,
    /// punctuation or a leading article, with "&" read as "and".
    public static func normalized(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        var words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if words.count > 1, ["the", "a", "an"].contains(words[0]) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    /// A year apart still agrees (a festival premiere, then the release); an
    /// unknown year agrees with any.
    public static func yearsAgree(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return true }
        return abs(a - b) <= 1
    }

    /// The search result that is this title: the same name (or original name)
    /// from within a year, the exact year first, otherwise in TMDB's order.
    /// Without a year only the same name counts; with one, a name that
    /// contains the other as whole words does too.
    public static func best(_ results: [TMDBReference], title: String, year: Int?) -> TMDBReference? {
        let wanted = normalized(title)
        guard !wanted.isEmpty else { return nil }
        var best: (score: (Int, Int, Int), result: TMDBReference)?
        for (index, result) in results.enumerated() {
            let names = [result.title, result.originalTitle].map(normalized).filter { !$0.isEmpty }
            let exact = names.contains(wanted)
            guard exact || (year != nil && names.contains { contains($0, wanted) || contains(wanted, $0) }) else { continue }
            var distance = 0
            if let year {
                guard let found = result.year, abs(found - year) <= 1 else { continue }
                distance = abs(found - year)
            }
            let score = (exact ? 0 : 1, distance, index)
            if best.map({ score < $0.score }) ?? true { best = (score, result) }
        }
        return best?.result
    }

    /// `part` (four letters or more) as whole words inside a longer `whole`.
    private static func contains(_ whole: String, _ part: String) -> Bool {
        part.count >= 4 && whole.count > part.count && " \(whole) ".contains(" \(part) ")
    }
}

/// How long TMDB answers are kept on the device.
public enum TMDBCachePolicy {
    /// Details are refetched after a week, a match after a month and a miss
    /// after three days, when a page or the hero next needs them.
    public static let details: TimeInterval = 7 * 86_400
    public static let match: TimeInterval = 30 * 86_400
    public static let miss: TimeInterval = 3 * 86_400
    /// Nothing is kept longer: well inside TMDB's six-month limit, with stale
    /// copies standing in while offline.
    public static let retention: TimeInterval = 60 * 86_400

    /// A date in the future (the clock moved) counts as stale.
    public static func isFresh(_ saved: Date, maxAge: TimeInterval, at date: Date) -> Bool {
        let age = date.timeIntervalSince(saved)
        return age >= 0 && age < maxAge
    }
}

/// A library title's TMDB id, or that nothing matched, and when that was found.
public struct TMDBMatchRecord: Codable, Hashable, Sendable {
    public var tmdbID: Int?
    public var saved: Date
    public init(tmdbID: Int?, saved: Date) { self.tmdbID = tmdbID; self.saved = saved }
    public func isFresh(at date: Date) -> Bool {
        TMDBCachePolicy.isFresh(saved, maxAge: tmdbID == nil ? TMDBCachePolicy.miss : TMDBCachePolicy.match, at: date)
    }
}

extension TMDBTitle {
    public func isFresh(at date: Date) -> Bool { TMDBCachePolicy.isFresh(fetched, maxAge: TMDBCachePolicy.details, at: date) }
}

extension TMDBCollection {
    public func isFresh(at date: Date) -> Bool { TMDBCachePolicy.isFresh(fetched, maxAge: TMDBCachePolicy.details, at: date) }
}

/// The library by TMDB id and by title, to show TMDB's recommendations and a
/// collection's parts that are actually in it.
public struct TMDBLibraryIndex<Item: VODItem>: Sendable {
    private var byTMDB: [Int: Item] = [:]
    private var byTitle: [String: [Item]] = [:]
    private var byID: [String: Item] = [:]

    public init(_ items: [Item]) {
        for item in items {
            byID[item.id] = item
            if let id = item.tmdbID, byTMDB[id] == nil { byTMDB[id] = item }
            let name = TMDBMatch.normalized(item.title)
            if !name.isEmpty { byTitle[name, default: []].append(item) }
        }
    }

    /// The library's copy of each reference, in TMDB's order and once each:
    /// by TMDB id (the provider's, or `known`: ids matched before, by item
    /// ID), else by title within a year. Titles known to be something else
    /// aren't matched by name.
    public func matches(_ references: [TMDBReference], known: [String: Int] = [:], excluding: Set<String> = []) -> [Item] {
        var knownItems: [Int: Item] = [:]
        for (itemID, tmdbID) in known.sorted(by: { $0.key < $1.key }) where knownItems[tmdbID] == nil {
            if let item = byID[itemID] { knownItems[tmdbID] = item }
        }
        var seen = excluding, found: [Item] = []
        for reference in references {
            guard let item = byTMDB[reference.id] ?? knownItems[reference.id] ?? named(reference, known: known),
                  seen.insert(item.id).inserted else { continue }
            found.append(item)
        }
        return found
    }

    private func named(_ reference: TMDBReference, known: [String: Int]) -> Item? {
        var tried = Set<String>()
        for name in [reference.title, reference.originalTitle].map(TMDBMatch.normalized) where !name.isEmpty && tried.insert(name).inserted {
            if let item = byTitle[name]?.first(where: { ($0.tmdbID ?? known[$0.id]) == nil && TMDBMatch.yearsAgree($0.year, reference.year) }) {
                return item
            }
        }
        return nil
    }
}
