import Foundation

// How the Watch tab sorts the provider's movies and shows: the language each
// title is in, one shelf per streaming service, and the Watch Later list.

// MARK: - Languages

/// The language of a movie or show, from the tags providers put on their
/// categories and titles: "EN - Action", "|FR| Films", "NETFLIX [DE]",
/// "ARABIC MOVIES". Empty when nothing says.
public enum VODLanguage {
    /// Codes providers put in front of or around a name → ISO 639-1. Country
    /// codes count, as a provider's "DE" folder is German.
    static let codes: [String: String] = [
        "EN": "en", "ENG": "en", "UK": "en", "US": "en", "USA": "en", "GB": "en", "AU": "en", "NZ": "en", "IE": "en",
        "FR": "fr", "FRA": "fr", "FRE": "fr", "VF": "fr", "VFF": "fr", "VFQ": "fr", "VOSTFR": "fr",
        "DE": "de", "GER": "de", "DEU": "de", "AT": "de",
        "ES": "es", "ESP": "es", "SPA": "es", "LAT": "es", "LATAM": "es", "LATINO": "es", "MX": "es", "CO": "es", "CL": "es", "PE": "es",
        "IT": "it", "ITA": "it", "PT": "pt", "POR": "pt", "BR": "pt", "NL": "nl", "NLD": "nl", "DUT": "nl",
        "TR": "tr", "TUR": "tr", "PL": "pl", "POL": "pl", "RU": "ru", "RUS": "ru", "UA": "uk", "UKR": "uk",
        "AR": "ar", "ARA": "ar", "ARAB": "ar", "HE": "he", "HEB": "he", "IL": "he", "FA": "fa", "IR": "fa", "PER": "fa",
        "UR": "ur", "PK": "ur", "IN": "hi", "HIN": "hi", "HI": "hi",
        "KO": "ko", "KR": "ko", "KOR": "ko", "JA": "ja", "JP": "ja", "JPN": "ja", "ZH": "zh", "CN": "zh", "CHI": "zh", "HK": "zh", "TW": "zh",
        "SE": "sv", "SV": "sv", "SWE": "sv", "NO": "no", "NOR": "no", "DK": "da", "DA": "da", "DAN": "da", "FI": "fi", "FIN": "fi",
        "GR": "el", "EL": "el", "GRE": "el", "RO": "ro", "ROM": "ro", "HU": "hu", "HUN": "hu", "CZ": "cs", "CS": "cs", "CZE": "cs",
        "SK": "sk", "SVK": "sk", "BG": "bg", "BUL": "bg", "AL": "sq", "ALB": "sq", "SQ": "sq", "HR": "hr", "CRO": "hr",
        "RS": "sr", "SR": "sr", "SRB": "sr", "VN": "vi", "VI": "vi", "VIE": "vi", "TH": "th", "THA": "th", "PH": "tl", "FIL": "tl",
        "ID": "id", "IND": "id", "KU": "ku", "KUR": "ku", "SOM": "so",
    ]
    /// Codes that are also everyday words ("IN CINEMAS", "IT: Chapter Two"):
    /// they count only between brackets or bars, or before a spaced dash.
    static let ambiguous: Set<String> = ["IN", "NO", "IT", "AL", "HE", "ID", "AT", "HI", "DA", "EL", "CO", "PE", "SK", "ROM", "IND", "PER"]
    /// Language names in category names.
    static let words: [String: String] = [
        "ENGLISH": "en", "FRENCH": "fr", "FRANCAIS": "fr", "FRANÇAIS": "fr", "GERMAN": "de", "DEUTSCH": "de",
        "SPANISH": "es", "ESPANOL": "es", "ESPAÑOL": "es", "CASTELLANO": "es", "LATINO": "es", "ITALIAN": "it", "ITALIANO": "it",
        "PORTUGUESE": "pt", "PORTUGUES": "pt", "PORTUGUÊS": "pt", "BRASIL": "pt", "BRAZIL": "pt", "DUTCH": "nl", "NEDERLANDS": "nl",
        "TURKISH": "tr", "TURK": "tr", "TÜRK": "tr", "TURKCE": "tr", "TÜRKÇE": "tr", "POLISH": "pl", "POLSKI": "pl", "RUSSIAN": "ru",
        "UKRAINIAN": "uk", "ARABIC": "ar", "ARABE": "ar", "HEBREW": "he", "PERSIAN": "fa", "FARSI": "fa", "URDU": "ur",
        "HINDI": "hi", "BOLLYWOOD": "hi", "PUNJABI": "pa", "TAMIL": "ta", "TELUGU": "te", "MALAYALAM": "ml", "KANNADA": "kn",
        "BENGALI": "bn", "MARATHI": "mr", "GUJARATI": "gu", "KOREAN": "ko", "JAPANESE": "ja", "CHINESE": "zh", "MANDARIN": "zh",
        "CANTONESE": "zh", "SWEDISH": "sv", "NORWEGIAN": "no", "DANISH": "da", "FINNISH": "fi", "GREEK": "el", "ROMANIAN": "ro",
        "HUNGARIAN": "hu", "CZECH": "cs", "SLOVAK": "sk", "BULGARIAN": "bg", "ALBANIAN": "sq", "CROATIAN": "hr", "SERBIAN": "sr",
        "VIETNAMESE": "vi", "THAI": "th", "FILIPINO": "tl", "TAGALOG": "tl", "PINOY": "tl", "INDONESIAN": "id", "MALAY": "ms",
        "KURDISH": "ku", "SOMALI": "so", "AFRIKAANS": "af", "ARMENIAN": "hy", "GEORGIAN": "ka", "AZERBAIJANI": "az", "AZERI": "az",
    ]
    private static let prefix = try! NSRegularExpression(pattern: #"^\s*([\[(|]?)\s*([A-Za-z]{2,6})\s*(\]|\)|\||:|\s[-–]\s|[-–])"#)
    private static let bracketed = try! NSRegularExpression(pattern: #"[\[(|]\s*([A-Za-z]{2,6})\s*[\])|]"#)
    private static let suffix = try! NSRegularExpression(pattern: #"(?:\s[-–]\s|\|)\s*([A-Za-z]{2,6})\s*$"#)

    /// The title's own tag wins over its folder's, which wins over a language
    /// named in the folder. Words in a title never count ("The French Dispatch").
    public static func detect(category: String, title: String) -> String {
        tag(in: title, isTitle: true) ?? tag(in: category, isTitle: false) ?? word(in: category) ?? ""
    }

    static func tag(in raw: String, isTitle: Bool) -> String? {
        let text = raw.precomposedStringWithCompatibilityMapping
        let range = NSRange(text.startIndex..., in: text)
        func code(_ value: Substring, spaced: Bool) -> String? {
            // Titles are tagged in capitals; "It: Chapter Two" is a title.
            guard !isTitle || value == value.uppercased() else { return nil }
            let upper = value.uppercased()
            guard let language = codes[upper] else { return nil }
            return ambiguous.contains(upper) && !spaced ? nil : language
        }
        if let match = prefix.firstMatch(in: text, range: range),
           let opener = Range(match.range(at: 1), in: text), let value = Range(match.range(at: 2), in: text),
           let separator = Range(match.range(at: 3), in: text), match.range.upperBound < range.upperBound {
            let closer = text[separator].trimmingCharacters(in: .whitespaces)
            // "|EN|", "[EN]", "EN |" and "EN - " are clear; "EN:" and "EN-" only for unambiguous codes.
            let clear = !text[opener].isEmpty || closer == "|" || closer == "]" || closer == ")" || text[separator].count > 1
            if let found = code(text[value], spaced: clear) { return found }
        }
        for match in bracketed.matches(in: text, range: range) {
            if let value = Range(match.range(at: 1), in: text), let found = code(text[value], spaced: true) { return found }
        }
        if let match = suffix.firstMatch(in: text, range: range), let value = Range(match.range(at: 1), in: text),
           let found = code(text[value], spaced: true) { return found }
        // A folder's first word: "EN ACTION", "US MOVIES".
        if !isTitle, let first = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first,
           let found = code(first, spaced: false) { return found }
        return nil
    }

    static func word(in text: String) -> String? {
        for token in text.uppercased().split(whereSeparator: { !$0.isLetter }) {
            if let language = words[String(token)] { return language }
        }
        return nil
    }

    /// "English", in the device's language.
    public static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: .current) ?? code.uppercased()
    }
}

/// Which titles the Watch tab shows, by language.
public struct VODLanguages: Hashable, Sendable {
    public enum Choice: Hashable, Sendable {
        /// The user's languages, plus titles nothing tags.
        case mine
        case all
        case only(String)

        /// Saved as "" (mine), "all" or a language code.
        public init(saved: String) {
            switch saved { case "": self = .mine; case "all": self = .all; default: self = .only(saved) }
        }
        public var saved: String {
            switch self { case .mine: ""; case .all: "all"; case .only(let code): code }
        }
    }
    public var choice: Choice
    /// The user's languages, best first.
    public var preferred: [String]
    public init(choice: Choice = .mine, preferred: [String] = []) { self.choice = choice; self.preferred = preferred }

    public func includes(_ language: String) -> Bool {
        switch choice {
        case .all: return true
        // Before the user's languages are known, nothing is hidden.
        case .mine: return preferred.isEmpty || language.isEmpty || preferred.contains(language)
        case .only(let code): return language == code
        }
    }

    /// Which copy of a title stands for the others: lower is better.
    public func rank(_ language: String) -> Int {
        if case .only(let code) = choice { return language == code ? 0 : (language.isEmpty ? 1 : 2) }
        if let index = preferred.firstIndex(of: language) { return index }
        return language.isEmpty ? preferred.count : preferred.count + 1
    }
}

// MARK: - Services

/// Streaming services providers name folders after. Every "NETFLIX MOVIES",
/// "EN - NETFLIX 4K" and "|FR| NETFLIX" folder becomes one Netflix shelf.
public enum VODService {
    static let services: [(name: String, patterns: [String])] = [
        ("Netflix", ["NETFLIX", "NFLX"]),
        ("Prime Video", ["AMAZON PRIME", "PRIME VIDEO", "AMAZON", "PRIME"]),
        ("Disney+", ["DISNEY PLUS", "DISNEY"]),
        ("Apple TV+", ["APPLE TV PLUS", "APPLE TV", "APPLE PLUS", "APPLETV"]),
        ("HBO Max", ["HBO MAX", "HBO", "MAX ORIGINALS"]),
        ("Hulu", ["HULU"]),
        ("Paramount+", ["PARAMOUNT PLUS", "PARAMOUNT"]),
        ("Peacock", ["PEACOCK"]),
        ("Showtime", ["SHOWTIME"]),
        ("Starz", ["STARZ"]),
        ("AMC+", ["AMC PLUS", "AMC"]),
        ("Crunchyroll", ["CRUNCHYROLL"]),
        ("Discovery+", ["DISCOVERY PLUS"]),
        ("BritBox", ["BRITBOX"]),
        ("MGM+", ["MGM PLUS", "EPIX"]),
        ("Shahid", ["SHAHID"]),
        ("OSN+", ["OSN PLUS", "OSN"]),
        ("Canal+", ["CANAL PLUS"]),
        ("Viaplay", ["VIAPLAY"]),
        ("ZEE5", ["ZEE5", "ZEE 5"]),
        ("JioHotstar", ["JIOHOTSTAR", "JIO HOTSTAR", "HOTSTAR", "JIOCINEMA"]),
        ("SonyLIV", ["SONYLIV", "SONY LIV"]),
        ("Crave", ["CRAVE"]),
        ("MUBI", ["MUBI"]),
        ("Tubi", ["TUBI"]),
        ("Pluto TV", ["PLUTO TV", "PLUTO"]),
        ("Rakuten TV", ["RAKUTEN"]),
        ("Videoland", ["VIDEOLAND"]),
        ("Movistar+", ["MOVISTAR"]),
    ].map { ($0.0, $0.1.map { " \($0) " }) }

    /// The service a folder is named after, if any.
    public static func name(for category: String) -> String? {
        let words = category.uppercased().replacingOccurrences(of: "+", with: " PLUS ")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
        let padded = " " + words + " "
        return services.first { $0.patterns.contains { padded.contains($0) } }?.name
    }
}

extension VODShelf {
    /// A folder's shelf: the service it's named after, else its name without
    /// the provider's tags and a trailing "Movies" or "Series".
    public static func shelfName(_ category: String) -> String {
        if let service = VODService.name(for: category) { return service }
        let cleaned = NameCleaning.local(category)
        var words = cleaned.split(separator: " ").map(String.init)
        let lower = words.map { $0.lowercased() }
        let filler: Set<String> = ["movies", "movie", "films", "film", "series", "shows", "show"]
        // "New Movies" isn't "New"; "TV Shows" stays as it is.
        let qualifiers: Set<String> = ["new", "latest", "top", "best", "recent", "popular", "all", "other", "classic", "old", "more", "trending", "featured", "hot", "tv"]
        guard let last = lower.last, filler.contains(last) else { return cleaned }
        if words.count > 2, lower[lower.count - 2] == "tv" { words.removeLast(2) }
        else if words.count > 1, lower[lower.count - 2] != "tv" { words.removeLast() }
        if words.count == 1, qualifiers.contains(words[0].lowercased()) { return cleaned }
        return words.joined(separator: " ")
    }

    /// Shelves merge regardless of case and accents: "ACTION" and "Action".
    static func shelfKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

// MARK: - Watch Later

/// A movie or show saved for later. Synced as personal data, with what a
/// poster needs before the catalog loads.
public struct WatchLaterItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case movie, show }
    public var itemID: String
    public var kind: Kind
    public var sourceID: UUID
    public var title: String
    public var year: Int?
    public var artwork: URL?
    public var added: Date
    public var id: String { itemID }

    public init(itemID: String, kind: Kind, sourceID: UUID, title: String, year: Int? = nil, artwork: URL? = nil, added: Date = .now) {
        self.itemID = itemID; self.kind = kind; self.sourceID = sourceID; self.title = title; self.year = year; self.artwork = artwork; self.added = added
    }
    public init(_ movie: Movie, added: Date = .now) {
        self.init(itemID: movie.id, kind: .movie, sourceID: movie.sourceID, title: movie.title, year: movie.year, artwork: movie.poster, added: added)
    }
    public init(_ show: Series, added: Date = .now) {
        self.init(itemID: show.id, kind: .show, sourceID: show.sourceID, title: show.title, year: show.year, artwork: show.poster, added: added)
    }

    public static func key(_ itemID: String) -> String { "vod.later.\(itemID)" }

    /// Newest first, without movies already watched.
    public static func list(_ items: [WatchLaterItem], finished: Set<String>) -> [WatchLaterItem] {
        items.filter { $0.kind == .show || !finished.contains($0.itemID) }.sorted { ($0.added, $0.itemID) > ($1.added, $1.itemID) }
    }
}
