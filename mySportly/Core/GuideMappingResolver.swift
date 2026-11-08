import Foundation

public struct GuideMatch: Codable, Hashable, Sendable {
    public var guideID: String
    public var reason: String
}

/// Derived matches never rewrite the provider catalog or personal corrections.
/// Only unique names within one source and country may supply a missing ID.
public struct GuideMappingResolver: Sendable {
    public let matches: [String: GuideMatch]
    public let ambiguous: Set<String>
    private struct Key: Hashable { let source: UUID; let region: String; let name: String }
    private struct Candidate: Hashable { let id: String; let language: String }

    public init(channels: [Channel], guideIDs: [UUID: [String]], guideChannels: [GuideChannel] = [], metadata: [String: ChannelMetadata]) throws {
        let available = guideIDs.mapValues(Set.init)
        var foldedIDs: [UUID: [String: Set<String>]] = [:]
        var names: [Key: Set<Candidate>] = [:]
        var knownLanguages: [UUID: [String: Set<String>]] = [:]
        func add(_ name: String, source: UUID, region: String, id: String, language: String = "") {
            guard !region.isEmpty else { return }
            let normalized = Self.name(name, region: region)
            guard !normalized.isEmpty else { return }
            names[Key(source: source, region: region, name: normalized), default: []].insert(Candidate(id: id, language: language))
        }
        for (source, ids) in guideIDs {
            for id in ids {
                try Task.checkCancellation()
                foldedIDs[source, default: [:]][Self.fold(id), default: []].insert(id)
                if let label = Self.guideLabel(id) { add(label.name, source: source, region: label.region, id: id) }
            }
        }
        for channel in guideChannels where available[channel.sourceID]?.contains(channel.guideID) == true {
            if let label = Self.guideLabel(channel.guideID) {
                for name in channel.names { add(name, source: channel.sourceID, region: label.region, id: channel.guideID) }
            }
        }
        // An existing provider mapping is evidence for otherwise opaque IDs.
        // Manual mappings are deliberately not propagated to other feeds.
        for (position, channel) in channels.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            guard available[channel.sourceID]?.contains(channel.guideID) == true, !Self.eventFeed(channel),
                  let details = metadata[channel.id] else { continue }
            if let country = Self.guideLabel(channel.guideID)?.region, country != details.region { continue }
            if !details.language.isEmpty { knownLanguages[channel.sourceID, default: [:]][channel.guideID, default: []].insert(details.language) }
            add(channel.name, source: channel.sourceID, region: details.region, id: channel.guideID, language: details.language)
        }
        var matches: [String: GuideMatch] = [:], ambiguous = Set<String>()
        for (position, channel) in channels.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            guard available[channel.sourceID]?.contains(channel.guideID) != true else { continue }
            if !channel.guideID.isEmpty, let candidates = foldedIDs[channel.sourceID]?[Self.fold(channel.guideID)], candidates.count == 1, let id = candidates.first {
                matches[channel.id] = GuideMatch(guideID: id, reason: "Guide ID spelling matched")
                continue
            }
            guard !Self.eventFeed(channel), let details = metadata[channel.id], !details.region.isEmpty else { continue }
            let key = Key(source: channel.sourceID, region: details.region, name: Self.name(channel.name, region: details.region))
            // A network alone does not identify its local affiliate's schedule.
            if details.region == "US", Self.localNetworks.contains(key.name) { continue }
            let candidates = Set((names[key] ?? []).filter {
                let languages = knownLanguages[channel.sourceID]?[$0.id] ?? []
                return (languages.isEmpty || details.language.isEmpty || languages.contains(details.language)) &&
                    ($0.language.isEmpty || details.language.isEmpty || $0.language == details.language)
            }.map(\.id))
            if candidates.count == 1, let id = candidates.first {
                matches[channel.id] = GuideMatch(guideID: id, reason: "Unique channel name and country matched")
            } else if candidates.count > 1 { ambiguous.insert(channel.id) }
            else if details.region == "US", let call = Self.localCallsign(channel.name) {
                let ids = Set((names[Key(source: channel.sourceID, region: "US", name: call)] ?? []).map(\.id))
                if ids.count == 1, let id = ids.first { matches[channel.id] = GuideMatch(guideID: id, reason: "Exact local station call sign matched") }
                else if ids.count > 1 { ambiguous.insert(channel.id) }
            }
        }
        self.matches = matches; self.ambiguous = ambiguous
    }

    private static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func eventFeed(_ channel: Channel) -> Bool {
        let text = (channel.name + " " + channel.group).uppercased()
        return ListingAvailability.isInactiveChannel(channel.name) || text.contains("PPV") || text.contains("24/7")
    }
    private static func guideLabel(_ id: String) -> (name: String, region: String)? {
        guard let dot = id.lastIndex(of: ".") else { return nil }
        let region = LocalePreferences.regionCode(String(id[id.index(after: dot)...]))
        guard !region.isEmpty else { return nil }
        return (String(id[..<dot]), region)
    }
    private static let quality: Set<String> = ["HD", "SD", "FHD", "UHD", "4K", "8K", "RAW", "HDRAW", "FHDRAW", "60FPS", "50FPS", "30FPS", "HEVC", "H264", "H265"]
    private static let localNetworks: Set<String> = ["abc", "cbs", "nbc", "fox", "pbs", "cw", "thecw", "mytv"]
    private static let prefix = try! NSRegularExpression(pattern: #"^\s*(US|USA|UK|GB|CA|AU|ATT)\s*[:|]\s*"#)
    private static let callsign = try! NSRegularExpression(pattern: #"\(([WK][A-Z]{3})\)"#)
    private static let shifted = try! NSRegularExpression(pattern: #"\+\s*\d|\b(EAST|WEST|PACIFIC|MOUNTAIN|CENTRAL)\b"#)

    /// Keep editions, cities, languages, numbers and time shifts. Never match on
    /// a brand alone or strip arbitrary provider prefixes (e.g. FAST news feeds).
    static func name(_ value: String, region: String) -> String {
        var text = value.precomposedStringWithCompatibilityMapping.uppercased()
        let range = NSRange(text.startIndex..., in: text)
        if let match = prefix.firstMatch(in: text, range: range), let tagRange = Range(match.range(at: 1), in: text) {
            let tag = String(text[tagRange])
            if LocalePreferences.regionCode(tag) == region || (tag == "ATT" && region == "US") {
                text = String(text[Range(match.range, in: text)!.upperBound...])
            }
        }
        text = text.replacingOccurrences(of: "&", with: " AND ")
        var tokens = text.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+")).inverted).filter { !$0.isEmpty }
        while let last = tokens.last, quality.contains(last) { tokens.removeLast() }
        return tokens.joined().lowercased()
    }
    private static func localCallsign(_ value: String) -> String? {
        let text = value.precomposedStringWithCompatibilityMapping.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("US:") || text.hasPrefix("USA:") else { return nil }
        guard !text.contains("NEWS"), shifted.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil else { return nil }
        let matches = callsign.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: text) else { return nil }
        return String(text[range]).lowercased()
    }
}
