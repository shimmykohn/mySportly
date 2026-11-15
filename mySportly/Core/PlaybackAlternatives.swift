import Foundation

public enum PlaybackAlternatives {
    /// Match exact same-source event labels, preserving time, teams and language.
    /// Different numbered event slots are alternatives only when their complete
    /// event suffix agrees. Generic numbered channels never match each other.
    public static func groups(_ channels: [Channel]) -> [String: [String]] {
        let event = try! NSRegularExpression(pattern: #"(?i)^\s*(NFL|NBA|MLB|NHL|WNBA|MLS)\s*\|\s*(?:4K|UHD|FHD|HD|SD|[0-9]{1,3})\s*-\s*(.+)$"#)
        var groups: [String: [Channel]] = [:]
        for channel in channels where !ListingAvailability.isInactiveChannel(channel.name) {
            guard let match = event.firstMatch(in: channel.name, range: NSRange(channel.name.startIndex..., in: channel.name)),
                  let league = Range(match.range(at: 1), in: channel.name), let title = Range(match.range(at: 2), in: channel.name) else { continue }
            let suffix = SportsFollowMatcher.normalize(String(channel.name[title]))
            guard suffix.contains(" at ") || suffix.contains(" vs ") else { continue }
            let key = [channel.sourceID.uuidString, String(channel.name[league]).uppercased(), suffix, channel.language, channel.region].joined(separator: "|")
            groups[key, default: []].append(channel)
        }
        var result: [String: [String]] = [:]
        for group in groups.values where group.count > 1 {
            let ids = group.sorted {
                let a = ["4K", "UHD"].contains(ChannelOrganizer.quality($0.name))
                let b = ["4K", "UHD"].contains(ChannelOrganizer.quality($1.name))
                return a == b ? $0.id < $1.id : !a
            }.map(\.id)
            for id in ids { result[id] = ids }
        }
        return result
    }
}
