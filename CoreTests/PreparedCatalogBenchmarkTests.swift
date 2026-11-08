import Foundation
import Testing
@testable import SportlyCore

/// Decision input for persisting prepared stages (instant-launch plan, Task 8).
/// Run with SPORTLY_BENCHMARK=1 in a release build.
struct PreparedCatalogBenchmarkTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPORTLY_BENCHMARK"] == "1"), .timeLimit(.minutes(5)))
    func benchmarkPreparedStages() throws {
        let source = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)
        let regions = ["US", "UK", "CA", "ES", "FR", "DE"], groups = ["Sports", "News", "Movies", "Kids", "Entertainment"]
        let channels = (0..<57_033).map { index in
            Channel(id: "\(index)", sourceID: source, name: "\(regions[index % 6])| Channel \(index / 3) \(["HD", "FHD", "4K"][index % 3])",
                    group: "\(regions[index % 6]) | \(groups[index % 5])", guideID: index % 4 == 0 ? "" : "channel\(index / 3).\(regions[index % 6].lowercased())")
        }
        let programs = (0..<220_500).map { position in
            let slot = position / 3500
            return GuideProgram(id: "p\(position)", sourceID: source, guideID: "channel\(position % 3500).\(regions[position % 6].lowercased())",
                                title: slot.isMultiple(of: 3) ? "NBA Basketball: Knicks at Celtics" : "Evening News", start: now + Double(slot) * 1800, end: now + Double(slot + 1) * 1800)
        }
        func time<T>(_ label: String, _ work: () throws -> T) rethrows -> T {
            let start = ContinuousClock.now
            let value = try work()
            print("[PreparedStages] \(label)=\(ContinuousClock.now - start)")
            return value
        }
        _ = time("directory.localizedSort") { channels.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        let resolved: [String: ChannelMetadata] = time("directory.resolveMetadata") {
            var resolver = ChannelMetadataResolver(); var out: [String: ChannelMetadata] = [:]
            for channel in channels { out[channel.id] = resolver.resolve(channel) }
            return out
        }
        _ = time("directory.fold") { channels.map { ($0.name + " Sports " + $0.group).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) } }
        _ = time("group.base") { channels.map { GroupNames.base($0.name) } }
        _ = time("group.clean") { channels.map { GroupNames.clean($0.name) } }
        _ = time("group.slotFamily") { channels.map { GroupNames.slotFamily($0.name, sports: true) } }
        _ = time("group.hash") { channels.map { StableID.hash($0.name) } }
        _ = time("group.regions") { channels.map { GroupNames.regions.contains($0.id) } }
        _ = try time("directory.groupIndex") { try CatalogGroupIndex(channels: channels, metadata: resolved, placements: [:]) }
        let directory = try time("directory") { try ChannelDirectory(channels: channels, overrides: [:]) }
        var guide: [String: [GuideProgram]] = [:], ids: [UUID: Set<String>] = [:]
        time("guideGrouping") {
            for program in programs { guide[program.sourceID.uuidString + "|" + program.guideID, default: []].append(program); ids[program.sourceID, default: []].insert(program.guideID) }
            for key in guide.keys { guide[key]?.sort { $0.start < $1.start } }
        }
        let mappings = try time("guideMappings") { try GuideMappingResolver(channels: directory.channels, guideIDs: ids.mapValues { $0.sorted() }, metadata: directory.metadata) }
        _ = time("playbackAlternatives") { PlaybackAlternatives.groups(directory.lineup) }
        _ = try time("queryIndex") { try CatalogQueryIndex(channels: directory.lineup, programs: programs, metadata: directory.metadata, guideMatches: mappings.matches) }
        let full = try time("fullPrepared") { try PreparedCatalog(channels: channels, programs: programs, activeSources: [source], overrides: [:]) }
        let stagesData = try time("encodeStages") { try CatalogCodec.encode(full.freshStages) }
        let stages = try time("decodeStages(\(stagesData.count) bytes)") { try CatalogCodec.decode(PreparedStages?.self, from: stagesData) }
        let reused = try time("fullPreparedWithStages") { try PreparedCatalog(channels: channels, programs: programs, activeSources: [source], overrides: [:], stages: stages) }
        #expect(reused.freshStages == nil)
        let matchesData = try time("encodeGuideMatches") { try CatalogCodec.encode(mappings.matches) }
        _ = try time("decodeGuideMatches(\(mappings.matches.count))") { try CatalogCodec.decode([String: GuideMatch].self, from: matchesData) }
        let metadataData = try time("encodeMetadata") { try CatalogCodec.encode(directory.metadata) }
        _ = try time("decodeMetadata(\(directory.metadata.count), \(metadataData.count) bytes)") { try CatalogCodec.decode([String: ChannelMetadata].self, from: metadataData) }
    }
}
