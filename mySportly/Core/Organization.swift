import Foundation

public enum ChannelCategory: String, Codable, CaseIterable, Sendable {
    case news = "News", sports = "Sports", entertainment = "Entertainment", movies = "Movies"
    case kids = "Kids", documentary = "Documentary", music = "Music", lifestyle = "Lifestyle", unknown = "Unsorted"
}

public struct ChannelSuggestion: Codable, Identifiable, Sendable {
    public var id: String { channelID }
    public var channelID: String
    public var category: ChannelCategory
    public var language: String
    public var region: String
    public var confidence: Double
    public var reason: String
    public var origin: String
    public var fingerprint: String
    public init(channelID: String, category: ChannelCategory = .unknown, language: String = "", region: String = "", confidence: Double = 0, reason: String = "", origin: String = "Metadata", fingerprint: String = "") {
        self.channelID = channelID; self.category = category; self.language = language; self.region = region
        self.confidence = confidence; self.reason = reason; self.origin = origin; self.fingerprint = fingerprint
    }
}

public enum ChannelOrganizer {
    public static func quality(_ name: String) -> String {
        ["4K", "UHD", "FHD", "HD", "SD"].first { name.range(of: "\\b\($0)\\b", options: [.regularExpression, .caseInsensitive]) != nil } ?? "Auto"
    }
    public static func fingerprint(_ channel: Channel) -> String {
        StableID.hash([channel.name, channel.group, channel.guideID, channel.language, channel.region].joined(separator: "|"))
    }
    public static func metadataSuggestions(_ channels: [Channel]) -> [ChannelSuggestion] {
        var resolver = ChannelMetadataResolver()
        return channels.map { channel in
            let metadata = resolver.resolve(channel)
            let category = ChannelCategory(rawValue: metadata.category) ?? .unknown
            return ChannelSuggestion(channelID: channel.id, category: category, language: metadata.language, region: metadata.region,
                                     confidence: category == .unknown && metadata.language.isEmpty && metadata.region.isEmpty ? 0 : 0.85,
                                     reason: metadata.reason,
                                     fingerprint: fingerprint(channel))
        }
    }
    public static func variantGroups(_ channels: [Channel]) -> [[String]] {
        let candidates = channels.filter { !$0.guideID.isEmpty }
        let quality = try! NSRegularExpression(pattern: #"(?i)\b(4K|UHD|FHD|HD|SD)\b"#)
        let whitespace = try! NSRegularExpression(pattern: #"\s+"#)
        let groups = Dictionary(grouping: candidates) { channel in
            // Only remove an explicit quality token. Keep region, language, event, and time-shift text.
            let stripped = quality.stringByReplacingMatches(in: channel.name, range: NSRange(channel.name.startIndex..., in: channel.name), withTemplate: "")
            let base = whitespace.stringByReplacingMatches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped), withTemplate: " ")
                .trimmingCharacters(in: .whitespaces).lowercased()
            return [channel.sourceID.uuidString, channel.guideID, base, channel.language, channel.region].joined(separator: "|")
        }
        return groups.values.filter { $0.count > 1 }.map { $0.map(\.id).sorted() }.sorted { $0[0] < $1[0] }
    }
    public static func validate(_ suggestions: [ChannelSuggestion], channels: [Channel]) -> [ChannelSuggestion] {
        let valid = Set(channels.map(\.id))
        var seen = Set<String>()
        return suggestions.filter { valid.contains($0.channelID) && $0.confidence.isFinite && (0...1).contains($0.confidence) && seen.insert($0.channelID).inserted }
    }
}
