import Foundation

/// The small slice of a prepared catalog that the first screen needs:
/// favorites, then recently watched, then the head of the lineup, with their
/// listings for the next day. It is read before the full catalog on launch.
/// Channels carry stream URLs, so the file must be stored sealed.
public struct LaunchSnapshot: Codable, Sendable {
    public static let channelLimit = 300
    public static let window: TimeInterval = 24 * 3600

    public var createdAt: Date
    public var channels: [Channel]
    public var favoriteIDs: [String]
    public var lineupIDs: [String]
    public var guide: [String: [GuideProgram]]
    public var guideMatches: [String: GuideMatch]

    public init(prepared: PreparedCatalog, recentIDs: [String], manualGuideIDs: [String: String] = [:], now: Date) {
        var seen = Set<String>(), chosen: [Channel] = []
        func add(_ channel: Channel?) {
            guard let channel, chosen.count < Self.channelLimit, seen.insert(channel.id).inserted else { return }
            chosen.append(channel)
        }
        prepared.directory.favorites.forEach(add)
        recentIDs.forEach { add(prepared.channelsByID[$0]) }
        for channel in prepared.directory.lineup where chosen.count < Self.channelLimit { add(channel) }

        let matches = prepared.guideMappings.matches
        var guide: [String: [GuideProgram]] = [:], kept: [String: GuideMatch] = [:]
        let end = now + Self.window
        for channel in chosen {
            if let match = matches[channel.id] { kept[channel.id] = match }
            for guideID in Set([manualGuideIDs[channel.id], matches[channel.id]?.guideID, channel.guideID].compactMap { $0 }) where !guideID.isEmpty {
                let key = channel.sourceID.uuidString + "|" + guideID
                guard guide[key] == nil, let programs = prepared.guide[key] else { continue }
                let upcoming = programs.filter { $0.end > now && $0.start < end }
                if !upcoming.isEmpty { guide[key] = upcoming }
            }
        }
        createdAt = now
        channels = chosen
        favoriteIDs = prepared.directory.favorites.map(\.id).filter(seen.contains)
        lineupIDs = prepared.directory.lineup.map(\.id).filter(seen.contains)
        self.guide = guide
        guideMatches = kept
    }

    /// Drops channels from sources that no longer exist and listings that ended.
    public func active(sources: Set<UUID>, now: Date) -> LaunchSnapshot {
        var copy = self
        copy.channels = channels.filter { sources.contains($0.sourceID) }
        let ids = Set(copy.channels.map(\.id))
        copy.favoriteIDs = favoriteIDs.filter(ids.contains)
        copy.lineupIDs = lineupIDs.filter(ids.contains)
        copy.guideMatches = guideMatches.filter { ids.contains($0.key) }
        let prefixes = Set(sources.map(\.uuidString))
        copy.guide = guide.compactMapValues { programs in
            let live = programs.filter { $0.end > now }
            return live.isEmpty ? nil : live
        }.filter { key, _ in prefixes.contains(String(key.prefix { $0 != "|" })) }
        return copy
    }
}
