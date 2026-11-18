import Foundation

// The Movie Database (TMDB): backdrops, title logos, ratings, cast, trailers
// and recommendations for movie and show pages. Requests carry only titles,
// years and ids, never provider names, addresses or credentials; the user's
// token travels in a header (see `TMDBService`). Everything here is pure.

public enum TMDBKind: String, Codable, Hashable, Sendable { case movie, tv }

/// A movie or show as TMDB lists it: a search result, a recommendation or a
/// collection's part.
public struct TMDBReference: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var originalTitle: String
    public var year: Int?
    public init(id: Int, title: String, originalTitle: String = "", year: Int? = nil) {
        self.id = id; self.title = title; self.originalTitle = originalTitle; self.year = year
    }
}

public struct TMDBCastMember: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var character: String
    /// For `TMDBImage.url(_:size: .profile)`.
    public var photo: String?
    public init(id: String, name: String, character: String = "", photo: String? = nil) {
        self.id = id; self.name = name; self.character = character; self.photo = photo
    }
}

/// A movie's or show's TMDB details, reduced to what its page shows.
public struct TMDBTitle: Codable, Hashable, Sendable {
    public var kind: TMDBKind
    public var id: Int
    public var title: String
    public var year: Int?
    public var overview = ""
    /// Image paths, best first (see `TMDBChoice.backdrops`).
    public var backdrops: [String] = []
    /// The transparent title logo.
    public var logo: String?
    /// The US rating, such as "PG-13" or "TV-MA".
    public var certification: String?
    /// The average vote out of 10, once enough people have voted.
    public var rating: Double?
    /// A YouTube video ID.
    public var trailer: String?
    public var cast: [TMDBCastMember] = []
    public var recommendations: [TMDBReference] = []
    /// The collection a movie belongs to; its title is the collection's name.
    public var collection: TMDBReference?
    public var fetched: Date

    public init(kind: TMDBKind, id: Int, title: String, year: Int? = nil, fetched: Date) {
        self.kind = kind; self.id = id; self.title = title; self.year = year; self.fetched = fetched
    }

    public var trailerURL: URL? {
        guard let trailer, TMDBChoice.isYouTubeKey(trailer) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(trailer)")
    }
}

/// A movie series, such as "The Dark Knight Collection".
public struct TMDBCollection: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    /// Its movies, oldest first.
    public var parts: [TMDBReference]
    public var fetched: Date
    public init(id: Int, name: String, parts: [TMDBReference], fetched: Date) {
        self.id = id; self.name = name; self.parts = parts; self.fetched = fetched
    }
}

// MARK: - Requests

/// TMDB's v3 API, in English. Each request carries a title, a year or an id.
public enum TMDBEndpoint {
    static let root = URL(string: "https://api.themoviedb.org/3")!

    /// Details plus everything a page shows, in one request. Images are in
    /// English or have no language ("null").
    public static func details(_ kind: TMDBKind, id: Int) -> URL {
        let appended = "images,videos,credits,recommendations," + (kind == .movie ? "release_dates" : "content_ratings")
        return url("\(kind.rawValue)/\(id)", [("append_to_response", appended), ("include_image_language", "en,null"), ("language", "en-US")])
    }

    /// `year` narrows to titles released (or, for shows, airing) that year.
    public static func search(_ kind: TMDBKind, title: String, year: Int? = nil) -> URL {
        var query = [("query", title), ("include_adult", "false"), ("language", "en-US")]
        if let year { query.append(("year", String(year))) }
        return url("search/\(kind.rawValue)", query)
    }

    /// Looks up an IMDb id ("tt0137523").
    public static func find(imdbID: String) -> URL {
        url("find/\(imdbID)", [("external_source", "imdb_id"), ("language", "en-US")])
    }

    public static func collection(_ id: Int) -> URL {
        url("collection/\(id)", [("language", "en-US")])
    }

    private static func url(_ path: String, _ query: [(String, String)]) -> URL {
        var components = URLComponents(url: root.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        // URLComponents leaves "+" alone, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

/// `https://image.tmdb.org/t/p/{size}{path}`.
public enum TMDBImage {
    /// Widths from TMDB's `/configuration`.
    public enum Size: String, Sendable { case backdrop = "w1280", logo = "w500", profile = "w185" }

    public static func url(_ path: String, size: Size) -> URL? {
        guard var file = validPath(path) else { return nil }
        // Logos may be SVG; TMDB serves every width as PNG, and SVG only at "original".
        if file.lowercased().hasSuffix(".svg") { file = String(file.dropLast(4)) + ".png" }
        return URL(string: "https://image.tmdb.org/t/p/" + size.rawValue + file)
    }

    /// "/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg": one file name, nothing else.
    static func validPath(_ path: String?) -> String? {
        guard let path, path.hasPrefix("/"), (5...128).contains(path.count),
              path.dropFirst().allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return nil }
        return path
    }
}

/// Only the API Read Access Token, which goes in a header. The shorter API
/// key only works in a URL, so it isn't accepted.
public enum TMDBToken {
    /// A JWT: three dot-separated base64url parts, the first starting "eyJ".
    public static func isReadAccessToken(_ token: String) -> Bool {
        token.hasPrefix("eyJ") && (80...2048).contains(token.count)
            && token.split(separator: ".", omittingEmptySubsequences: false).count == 3
            && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
    /// The v3 API key: 32 hexadecimal characters.
    public static func isAPIKey(_ token: String) -> Bool { token.count == 32 && token.allSatisfy(\.isHexDigit) }
}

public enum TMDBFailure: Error, Equatable, Sendable, LocalizedError {
    case credentials, notFound, busy, unavailable

    public init(status: Int) {
        switch status {
        case 401: self = .credentials
        case 404: self = .notFound
        case 429: self = .busy
        default: self = .unavailable
        }
    }

    public var errorDescription: String? {
        switch self {
        case .credentials: "TMDB didn’t accept this token. Copy the API Read Access Token from your TMDB account’s API settings and paste it again."
        case .notFound: "TMDB doesn’t have this title."
        case .busy: "TMDB is busy right now."
        case .unavailable: "TMDB isn’t responding right now."
        }
    }
}

// MARK: - Responses

/// Lenient: a field or list entry that won't decode is left out, not fatal.
public enum TMDBDecode {
    struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    struct Results<T: Decodable>: Decodable {
        var results: [Lossy<T>]?
        var values: [T] { results?.compactMap(\.value) ?? [] }
    }
    /// A movie (`title`, `release_date`) or a show (`name`, `first_air_date`).
    struct Listing: Decodable {
        var id: Int?
        var title: String?; var name: String?; var original_title: String?; var original_name: String?
        var release_date: String?; var first_air_date: String?; var media_type: String?
        var date: String { release_date ?? first_air_date ?? "" }
        var reference: TMDBReference? {
            guard let id, id > 0, let title = (title ?? name)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            return TMDBReference(id: id, title: title, originalTitle: (original_title ?? original_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 year: TMDBDecode.year(date))
        }
    }
    struct Image: Decodable { var file_path: String?; var iso_639_1: String?; var vote_average: Double?; var vote_count: Double? }
    struct Video: Decodable { var key: String?; var site: String?; var type: String?; var official: Bool?; var iso_639_1: String?; var published_at: String? }
    struct Release: Decodable { var certification: String?; var type: Int? }
    struct ReleaseCountry: Decodable { var iso_3166_1: String?; var release_dates: [Lossy<Release>]? }
    struct ContentRating: Decodable { var iso_3166_1: String?; var rating: String? }
    struct Credit: Decodable { var id: Int?; var name: String?; var character: String?; var profile_path: String?; var order: Int?; var credit_id: String? }
    private struct Details: Decodable {
        var id: Int
        var title: String?; var name: String?; var release_date: String?; var first_air_date: String?
        var overview: String?; var vote_average: Double?; var vote_count: Double?
        var belongs_to_collection: Lossy<Collection>?
        var images: Lossy<Images>?
        var videos: Lossy<Results<Video>>?
        var credits: Lossy<Credits>?
        var recommendations: Lossy<Results<Listing>>?
        var release_dates: Lossy<Results<ReleaseCountry>>?
        var content_ratings: Lossy<Results<ContentRating>>?
        struct Collection: Decodable { var id: Int; var name: String? }
        struct Images: Decodable { var backdrops: [Lossy<Image>]?; var logos: [Lossy<Image>]? }
        struct Credits: Decodable { var cast: [Lossy<Credit>]? }
    }

    /// `/movie/{id}` or `/tv/{id}` with `TMDBEndpoint.details`' appended parts.
    public static func title(_ data: Data, kind: TMDBKind, fetched: Date) -> TMDBTitle? {
        guard let details = try? JSONDecoder().decode(Details.self, from: data), details.id > 0,
              let name = (details.title ?? details.name)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        var title = TMDBTitle(kind: kind, id: details.id, title: name, year: year(details.release_date ?? details.first_air_date), fetched: fetched)
        title.overview = details.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let images = details.images?.value
        title.backdrops = TMDBChoice.backdrops(images?.backdrops?.compactMap(\.value) ?? [])
        title.logo = TMDBChoice.logo(images?.logos?.compactMap(\.value) ?? [])
        title.trailer = TMDBChoice.trailer(details.videos?.value?.values ?? [])
        title.certification = kind == .movie ? TMDBChoice.certification(details.release_dates?.value?.values ?? [])
                                             : TMDBChoice.certification(details.content_ratings?.value?.values ?? [])
        title.rating = TMDBChoice.rating(average: details.vote_average, votes: details.vote_count)
        title.cast = TMDBChoice.cast(details.credits?.value?.cast?.compactMap(\.value) ?? [])
        var seen = Set<Int>()
        title.recommendations = Array((details.recommendations?.value?.values ?? [])
            .filter { $0.media_type == nil || $0.media_type == kind.rawValue }
            .compactMap(\.reference).filter { $0.id != details.id && seen.insert($0.id).inserted }.prefix(20))
        if kind == .movie, let collection = details.belongs_to_collection?.value, collection.id > 0 {
            title.collection = TMDBReference(id: collection.id, title: collection.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
        return title
    }

    /// `/search/movie` or `/search/tv`, in TMDB's order.
    public static func search(_ data: Data) -> [TMDBReference] {
        ((try? JSONDecoder().decode(Results<Listing>.self, from: data))?.values ?? []).compactMap(\.reference)
    }

    private struct Found: Decodable { var movie_results: [Lossy<Listing>]?; var tv_results: [Lossy<Listing>]? }
    /// `/find/{imdb_id}`: the first movie or show it names.
    public static func find(_ data: Data, kind: TMDBKind) -> Int? {
        guard let found = try? JSONDecoder().decode(Found.self, from: data) else { return nil }
        return ((kind == .movie ? found.movie_results : found.tv_results) ?? []).lazy.compactMap { $0.value?.reference?.id }.first
    }

    private struct CollectionDetails: Decodable { var id: Int; var name: String?; var parts: [Lossy<Listing>]? }
    /// `/collection/{id}`, its parts by release date; undated ones last.
    public static func collection(_ data: Data, fetched: Date) -> TMDBCollection? {
        guard let decoded = try? JSONDecoder().decode(CollectionDetails.self, from: data), decoded.id > 0 else { return nil }
        let parts = (decoded.parts ?? []).compactMap(\.value).enumerated()
            .sorted { ($0.element.date.isEmpty ? "~" : $0.element.date, $0.offset) < ($1.element.date.isEmpty ? "~" : $1.element.date, $1.offset) }
            .compactMap(\.element.reference)
        return TMDBCollection(id: decoded.id, name: decoded.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", parts: parts, fetched: fetched)
    }

    /// "1999-10-15" → 1999.
    static func year(_ date: String?) -> Int? {
        guard let date, date.count >= 4, let value = Int(date.prefix(4)), (1870...2100).contains(value) else { return nil }
        return value
    }
}

/// Which of TMDB's images, videos and ratings a page shows.
public enum TMDBChoice {
    /// Backdrops without a language (no text on them) first, then English,
    /// each by TMDB's vote; at most `limit`.
    static func backdrops(_ images: [TMDBDecode.Image], limit: Int = 10) -> [String] {
        Array(ranked(images, languages: [nil, "en"]).prefix(limit))
    }

    /// The English title logo, else one without a language.
    static func logo(_ images: [TMDBDecode.Image]) -> String? {
        ranked(images, languages: ["en", nil]).first
    }

    /// Paths in `languages`, in that order, each group by vote average and then vote count.
    private static func ranked(_ images: [TMDBDecode.Image], languages: [String?]) -> [String] {
        var seen = Set<String>()
        return images.enumerated().compactMap { offset, image -> (path: String, group: Int, average: Double, votes: Double, offset: Int)? in
            guard let path = TMDBImage.validPath(image.file_path), let group = languages.firstIndex(of: language(image.iso_639_1)) else { return nil }
            return (path, group, image.vote_average ?? 0, image.vote_count ?? 0, offset)
        }
        .sorted { ($0.group, -$0.average, -$0.votes, $0.offset) < ($1.group, -$1.average, -$1.votes, $1.offset) }
        .map(\.path).filter { seen.insert($0).inserted }
    }

    /// TMDB leaves images without text untagged ("xx" also means none).
    private static func language(_ code: String?) -> String? {
        guard let code = code?.lowercased(), !code.isEmpty, code != "xx" else { return nil }
        return code
    }

    /// The official YouTube trailer: English first, then the newest.
    static func trailer(_ videos: [TMDBDecode.Video]) -> String? {
        videos.enumerated()
            .filter { $0.element.official == true && $0.element.site?.lowercased() == "youtube" && $0.element.type?.lowercased() == "trailer" && isYouTubeKey($0.element.key) }
            .sorted { a, b in
                let (english, otherEnglish) = (a.element.iso_639_1 == "en", b.element.iso_639_1 == "en")
                if english != otherEnglish { return english }
                let (date, otherDate) = (a.element.published_at ?? "", b.element.published_at ?? "")
                return date != otherDate ? date > otherDate : a.offset < b.offset
            }
            .first?.element.key
    }

    static func isYouTubeKey(_ key: String?) -> Bool {
        guard let key, (6...32).contains(key.count) else { return false }
        return key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// A movie's US rating: the theatrical release's, else another US release's.
    static func certification(_ countries: [TMDBDecode.ReleaseCountry]) -> String? {
        let preference = [3, 2, 4, 5, 6, 1]
        return countries.filter { $0.iso_3166_1?.uppercased() == "US" }
            .flatMap { $0.release_dates?.compactMap(\.value) ?? [] }
            .compactMap { release -> (rank: Int, value: String)? in
                guard let value = release.certification?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
                return (preference.firstIndex(of: release.type ?? 0) ?? preference.count, value)
            }
            .min { $0.rank < $1.rank }?.value
    }

    /// A show's US rating.
    static func certification(_ ratings: [TMDBDecode.ContentRating]) -> String? {
        ratings.lazy.filter { $0.iso_3166_1?.uppercased() == "US" }
            .compactMap { $0.rating?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// Few votes make for a noisy average, so it needs ten.
    static func rating(average: Double?, votes: Double?) -> Double? {
        guard let average, average > 0, average <= 10, (votes ?? 0) >= 10 else { return nil }
        return (average * 10).rounded() / 10
    }

    /// In billing order, at most `limit`.
    static func cast(_ credits: [TMDBDecode.Credit], limit: Int = 15) -> [TMDBCastMember] {
        var seen = Set<String>()
        let ordered = credits.enumerated().sorted { ($0.element.order ?? .max, $0.offset) < ($1.element.order ?? .max, $1.offset) }
        return Array(ordered.compactMap { offset, credit -> TMDBCastMember? in
            guard let name = credit.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let id = credit.credit_id ?? "\(credit.id ?? 0)-\(offset)"
            guard seen.insert(id).inserted else { return nil }
            return TMDBCastMember(id: id, name: name, character: credit.character?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                  photo: TMDBImage.validPath(credit.profile_path))
        }.prefix(limit))
    }
}
