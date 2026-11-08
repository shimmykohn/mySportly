import Foundation

public enum SourceKind: String, Codable, Sendable, CaseIterable { case xtream, m3u }

public struct TVSource: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: SourceKind
    public var host: String
    public var connectionLimit: Int
    public var refreshedAt: Date?
    public init(id: UUID = UUID(), name: String, kind: SourceKind, host: String = "", connectionLimit: Int = 1, refreshedAt: Date? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.host = host
        self.connectionLimit = connectionLimit; self.refreshedAt = refreshedAt
    }
}

public struct Channel: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var sourceID: UUID
    public var providerID: String
    public var name: String
    public var group: String
    public var guideID: String
    public var logo: URL?
    public var streamURL: URL?
    public var language: String
    public var region: String
    public var archiveDays: Int
    public var quality: String
    public init(id: String, sourceID: UUID, providerID: String = "", name: String, group: String = "", guideID: String = "", logo: URL? = nil, streamURL: URL? = nil, language: String = "", region: String = "", archiveDays: Int = 0, quality: String = "") {
        self.id = id; self.sourceID = sourceID; self.providerID = providerID; self.name = name
        self.group = group; self.guideID = guideID; self.logo = logo; self.streamURL = streamURL
        self.language = language; self.region = region; self.archiveDays = archiveDays; self.quality = quality
    }
}

public struct GuideProgram: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var sourceID: UUID
    public var guideID: String
    public var title: String
    public var summary: String
    public var start: Date
    public var end: Date
    public var categories: [String]
    public var language: String
    public var image: URL?
    public init(id: String, sourceID: UUID, guideID: String, title: String, summary: String = "", start: Date, end: Date, categories: [String] = [], language: String = "", image: URL? = nil) {
        self.id = id; self.sourceID = sourceID; self.guideID = guideID; self.title = title; self.summary = summary
        self.start = start; self.end = end; self.categories = categories; self.language = language; self.image = image
    }
    public func isLive(at date: Date) -> Bool { start <= date && date < end }
    public var isSports: Bool {
        let terms = (categories + [title]).joined(separator: " ").lowercased()
        return ["sport", "basketball", "football", "baseball", "hockey", "soccer", "tennis", "golf", "nba", "nfl", "nhl", "mlb", "premier league", "cricket", "rugby", "formula 1", "ufc"].contains { terms.contains($0) }
    }
}

public struct CatalogSnapshot: Codable, Sendable {
    public var channels: [Channel] = []
    public var programs: [GuideProgram] = []
    public var refreshed: [UUID: Date] = [:]
    public var decisions: [String: ChannelSuggestion] = [:]
    public var guideRefreshed: [UUID: Date] = [:]
    public var guideChannels: [GuideChannel] = []
    public var guideURLs: [UUID: URL] = [:]
    public init() {}
    private enum CodingKeys: String, CodingKey { case channels, programs, refreshed, decisions, guideRefreshed, guideChannels, guideURLs }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        channels = try values.decodeIfPresent([Channel].self, forKey: .channels) ?? []
        programs = try values.decodeIfPresent([GuideProgram].self, forKey: .programs) ?? []
        refreshed = try values.decodeIfPresent([UUID: Date].self, forKey: .refreshed) ?? [:]
        decisions = try values.decodeIfPresent([String: ChannelSuggestion].self, forKey: .decisions) ?? [:]
        guideRefreshed = try values.decodeIfPresent([UUID: Date].self, forKey: .guideRefreshed) ?? [:]
        guideChannels = try values.decodeIfPresent([GuideChannel].self, forKey: .guideChannels) ?? []
        guideURLs = try values.decodeIfPresent([UUID: URL].self, forKey: .guideURLs) ?? [:]
    }
    /// Keeps listings that have not ended and start within `horizon`. Ended
    /// listings dominate a saved guide and are never shown.
    public mutating func pruneGuide(now: Date, horizon: TimeInterval = 3 * 86_400) {
        let limit = now + horizon
        programs.removeAll { $0.end <= now || $0.start >= limit }
    }
    public mutating func replace(sourceID: UUID, channels: [Channel], programs: [GuideProgram]?, guideChannels: [GuideChannel] = [], at date: Date = .now) {
        self.channels.removeAll { $0.sourceID == sourceID }
        var seen = Set<String>()
        self.channels += channels.filter { $0.sourceID == sourceID && seen.insert($0.id).inserted }
        if let programs {
            self.guideChannels.removeAll { $0.sourceID == sourceID }
            self.guideChannels += guideChannels.filter { $0.sourceID == sourceID }
            self.programs.removeAll { $0.sourceID == sourceID }
            var programIDs = Set<String>()
            self.programs += programs.filter { $0.sourceID == sourceID && programIDs.insert($0.id).inserted }
            guideRefreshed[sourceID] = date
        }
        refreshed[sourceID] = date
    }
    public mutating func replaceGuide(sourceID: UUID, guide: TVGuide, at date: Date = .now) {
        guideChannels.removeAll { $0.sourceID == sourceID }
        guideChannels += guide.channels.filter { $0.sourceID == sourceID }
        programs.removeAll { $0.sourceID == sourceID }
        var seen = Set<String>()
        programs += guide.programs.filter { $0.sourceID == sourceID && seen.insert($0.id).inserted }
        guideRefreshed[sourceID] = date
    }
}

public struct GuideChannel: Codable, Hashable, Sendable {
    public var sourceID: UUID
    public var guideID: String
    public var names: [String]
    public init(sourceID: UUID, guideID: String, names: [String]) {
        self.sourceID = sourceID; self.guideID = guideID; self.names = names
    }
}

public struct TVGuide: Sendable {
    public var channels: [GuideChannel]
    public var programs: [GuideProgram]
}

public enum CatalogError: Error, LocalizedError, Equatable {
    case invalidURL, invalidPlaylist, invalidGuide, tooLarge, noChannels, rejected, unsupportedRecording(String)
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a valid HTTP or HTTPS address."
        case .invalidPlaylist: "This file is not an extended M3U playlist."
        case .invalidGuide: "The TV guide could not be read. Check that the source supplies XMLTV."
        case .tooLarge: "This source exceeds the import size limit. Try a smaller playlist or guide."
        case .noChannels: "No playable channel addresses were found."
        case .rejected: "The provider rejected this request. Check the connection details and subscription."
        case .unsupportedRecording(let reason): reason
        }
    }
}
