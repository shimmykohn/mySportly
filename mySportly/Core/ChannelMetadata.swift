import Foundation

public enum LineupScope: String, Codable, CaseIterable, Sendable {
    case preferred = "My Lineup", all = "All Channels", unclassified = "Unclassified"
}

/// A shared policy for every discovery surface. Region is never inferred from
/// language, and country tags do not establish a stream's spoken language.
public struct ChannelAudience: Hashable, Sendable {
    public var scope: LineupScope
    public var languages: [String]
    public var regions: [String]
    public var includeUnknownLanguage: Bool
    public init(scope: LineupScope = .all, languages: [String] = [], regions: [String] = [], includeUnknownLanguage: Bool = true) {
        self.scope = scope
        self.languages = languages.map(LocalePreferences.languageCode).filter { !$0.isEmpty }
        self.regions = regions.map(LocalePreferences.regionCode).filter { !$0.isEmpty }
        self.includeUnknownLanguage = includeUnknownLanguage
    }
    public func includes(language: String, region: String) -> Bool {
        switch scope {
        case .all: return true
        case .unclassified: return (!languages.isEmpty && language.isEmpty) || (!regions.isEmpty && region.isEmpty)
        case .preferred:
            guard regions.isEmpty || regions.contains(region) else { return false }
            return languages.isEmpty || languages.contains(language) || (language.isEmpty && includeUnknownLanguage)
        }
    }
}

public struct ChannelMetadata: Codable, Hashable, Sendable {
    public var category: String
    public var language: String
    public var region: String
    public var reason: String
    public var sport: ChannelSport? = nil
}

/// Deterministic, conservative hints. Raw provider names/groups/identities are
/// retained in Channel; this derived information is rebuilt from the saved cache.
public struct ChannelMetadataResolver {
    private struct Tags { var regions: Set<String>; var languages: Set<String>; var category: ChannelCategory; var sports: Set<ChannelSport> }
    private var groups: [String: Tags] = [:]
    private static let wordSeparators = CharacterSet.alphanumerics.inverted
    private static let tagSeparators = CharacterSet(charactersIn: "|:[](){}•/\\–—-")
    private static let ambiguousPrefixes: Set<String> = ["IN", "NO", "IT", "IS", "BE", "AT", "AS", "ME", "MY", "SO", "TO", "DO", "TV"]
    private static let regionNames = ["UNITED STATES": "US", "USA": "US", "UNITED KINGDOM": "GB", "CANADA": "CA", "AUSTRALIA": "AU", "NEW ZEALAND": "NZ", "IRELAND": "IE", "FRANCE": "FR", "GERMANY": "DE", "SPAIN": "ES", "ITALY": "IT", "PORTUGAL": "PT", "MEXICO": "MX", "BRAZIL": "BR", "ISRAEL": "IL", "INDIA": "IN", "PAKISTAN": "PK", "RUSSIA": "RU", "POLAND": "PL", "TURKEY": "TR", "NETHERLANDS": "NL", "BELGIUM": "BE", "SWEDEN": "SE", "NORWAY": "NO", "DENMARK": "DK", "FINLAND": "FI", "GREECE": "GR", "ROMANIA": "RO", "JAPAN": "JP", "CHINA": "CN", "SOUTH KOREA": "KR", "SOUTH AFRICA": "ZA"]
    private static let languageNames = ["ENGLISH": "en", "SPANISH": "es", "ESPAÑOL": "es", "FRENCH": "fr", "FRANÇAIS": "fr", "HEBREW": "he", "ARABIC": "ar", "PORTUGUESE": "pt", "GERMAN": "de", "ITALIAN": "it", "HINDI": "hi", "RUSSIAN": "ru", "CHINESE": "zh", "JAPANESE": "ja", "KOREAN": "ko", "POLISH": "pl", "TURKISH": "tr", "DUTCH": "nl"]
    private static let regionPhrases = regionNames.filter { $0.key.contains(" ") }.map { (" " + $0.key + " ", $0.value) }
    private static let rules: [(ChannelCategory, Set<String>)] = [
        (.sports, ["SPORT", "SPORTS", "ESPN", "NBA", "NFL", "NHL", "MLB", "SOCCER", "FOOTBALL", "BASKETBALL", "TENNIS", "CRICKET", "GOLF"]),
        (.news, ["NEWS", "CNN", "MSNBC", "NEWSMAX"]), (.kids, ["KIDS", "CHILDREN", "CARTOON", "NICKELODEON"]),
        (.movies, ["MOVIE", "MOVIES", "CINEMA"]), (.documentary, ["DOCUMENTARY", "DOCUMENTARIES", "NATURE", "SCIENCE"]),
        (.music, ["MUSIC"]), (.lifestyle, ["LIFESTYLE", "COOKING", "TRAVEL"]), (.entertainment, ["ENTERTAINMENT", "GENERAL"])
    ]
    public init() {}
    public mutating func resolve(_ channel: Channel) -> ChannelMetadata {
        let group: Tags
        if let cached = groups[channel.group] { group = cached }
        else { group = Self.tags(channel.group); groups[channel.group] = group }
        let name = Self.tags(channel.name)
        func single(_ values: Set<String>) -> String { values.count == 1 ? values.first! : "" }
        let rawRegion = LocalePreferences.regionCode(channel.region)
        let rawLanguage = LocalePreferences.languageCode(channel.language)
        let regions = name.regions.union(group.regions)
        let languages = name.languages.union(group.languages)
        let region = rawRegion.isEmpty ? single(regions) : rawRegion
        let language = rawLanguage.isEmpty ? single(languages) : rawLanguage
        let category = name.category == .sports && !name.sports.isEmpty ? .sports : (group.category == .unknown ? name.category : group.category)
        // A specific feed name wins over a broad provider folder. Conflicting
        // sports in a name remain ungrouped rather than picking one arbitrarily.
        let sports = name.sports.isEmpty ? group.sports : name.sports
        let sport = category == .sports && sports.count == 1 ? sports.first : nil
        var reasons: [String] = []
        if !rawRegion.isEmpty || !rawLanguage.isEmpty { reasons.append("Explicit provider metadata") }
        if (!regions.isEmpty && rawRegion.isEmpty) || (!languages.isEmpty && rawLanguage.isEmpty) { reasons.append("Country/language tags in the provider name or group") }
        if category != .unknown { reasons.append("Category keywords in the provider name or group") }
        if regions.count > 1 || languages.count > 1 { reasons.append("Conflicting tags left unclassified") }
        return ChannelMetadata(category: category.rawValue, language: language, region: region,
            reason: reasons.isEmpty ? "No reliable tags found. Manual correction is available." : reasons.joined(separator: ". ") + ".", sport: sport)
    }
    private static func tags(_ text: String) -> Tags {
        let upper = text.uppercased()
        let tokens = upper.components(separatedBy: wordSeparators).filter { !$0.isEmpty }
        let words = Set(tokens)
        let padded = " " + tokens.joined(separator: " ") + " "
        var regions = Set(tokens.compactMap { regionNames[$0] })
        var languages = Set(tokens.compactMap { languageNames[$0] })
        for (phrase, region) in regionPhrases where padded.contains(phrase) { regions.insert(region) }
        // Short country codes only count at the start or as delimiter-separated
        // tags. "This Is Us", "CANAL", "RUSSIAN", etc. must not become US/CA.
        let chunks = upper.components(separatedBy: tagSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for chunk in chunks where chunk.count == 2 || chunk == "USA" || chunk == "UK" {
            let code = LocalePreferences.regionCode(chunk)
            if !code.isEmpty { regions.insert(code) }
        }
        for chunk in chunks {
            if let first = chunk.components(separatedBy: wordSeparators).first,
               !ambiguousPrefixes.contains(first), first.count == 2 || first == "USA" || first == "UK" {
                let code = LocalePreferences.regionCode(first)
                if !code.isEmpty { regions.insert(code) }
            }
        }
        // EN is an unambiguous language tag. Other abbreviations need a LANG
        // label: [ES] can mean Spain and must not silently imply Spanish audio.
        if upper.contains("[EN]") || upper.contains("(EN)") { languages.insert("en") }
        for code in ["EN", "ES", "FR", "HE", "AR", "PT", "DE", "IT", "HI", "RU", "ZH", "JA", "KO", "PL", "TR", "NL"] {
            if upper.contains("[LANG=\(code)]") || upper.contains("(LANG=\(code))") { languages.insert(code.lowercased()) }
        }
        let flags: [String: String] = ["🇺🇸": "US", "🇬🇧": "GB", "🇨🇦": "CA", "🇦🇺": "AU", "🇫🇷": "FR", "🇪🇸": "ES", "🇩🇪": "DE", "🇮🇱": "IL"]
        for (flag, region) in flags where upper.contains(flag) { regions.insert(region) }
        let sports = ChannelSport.matches(in: words)
        var categories = Set(rules.filter { !$0.1.isDisjoint(with: words) }.map(\.0))
        if !sports.isEmpty { categories.insert(.sports) }
        return Tags(regions: regions, languages: languages, category: categories.count == 1 ? categories.first! : .unknown, sports: sports)
    }
}
