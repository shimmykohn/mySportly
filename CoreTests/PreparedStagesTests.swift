import Foundation
import Testing
@testable import SportlyCore

struct PreparedStagesTests {
    let source = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var channels: [Channel] {
        [Channel(id: "espn", sourceID: source, name: "US: ESPN HD", group: "US | Sports", guideID: "", region: "US"),
         Channel(id: "cnn", sourceID: source, name: "US: CNN", group: "US | News", guideID: "cnn.us", region: "US"),
         Channel(id: "bbc", sourceID: source, name: "UK: BBC One", group: "UK | Entertainment", guideID: "BBCOne.uk", region: "GB"),
         Channel(id: "film", sourceID: source, name: "Movie Channel", group: "Movies", guideID: "")]
    }
    var programs: [GuideProgram] {
        ["espn.us", "cnn.us", "bbcone.uk"].map { GuideProgram(id: $0, sourceID: source, guideID: $0, title: "Show", start: now, end: now + 1800) }
    }

    func prepared(_ channels: [Channel]? = nil, overrides: [String: Data] = [:], stages: PreparedStages? = nil) throws -> PreparedCatalog {
        try PreparedCatalog(channels: channels ?? self.channels, programs: programs, activeSources: [source], overrides: overrides, stages: stages)
    }

    @Test func freshBuildProducesStagesThatReproduceIt() throws {
        let fresh = try prepared()
        let stages = try #require(fresh.freshStages)
        let reused = try prepared(stages: stages)
        #expect(reused.freshStages == nil)
        #expect(reused.directory.lineup.map(\.id) == fresh.directory.lineup.map(\.id))
        #expect(reused.directory.metadata == fresh.directory.metadata)
        #expect(reused.guideMappings.matches == fresh.guideMappings.matches)
        #expect(reused.guideMappings.ambiguous == fresh.guideMappings.ambiguous)
        #expect(!fresh.guideMappings.matches.isEmpty)
    }

    @Test func renamedChannelRecomputesMetadata() throws {
        let stages = try #require(try prepared().freshStages)
        var renamed = channels
        renamed[3].name = "US: Sports Extra"; renamed[3].group = "US | Sports"
        let rebuilt = try prepared(renamed, stages: stages)
        let fresh = try prepared(renamed)
        #expect(rebuilt.freshStages != nil)
        #expect(rebuilt.directory.metadata == fresh.directory.metadata)
        #expect(rebuilt.directory.metadata["film"]?.category != (try prepared()).directory.metadata["film"]?.category)
    }

    @Test func regionOverrideRecomputesOnlyGuideMatches() throws {
        let stages = try #require(try prepared().freshStages)
        let overrides = ["channel.espn.region": try JSONEncoder().encode("GB")]
        let rebuilt = try prepared(overrides: overrides, stages: stages)
        let fresh = try prepared(overrides: overrides)
        let saved = try #require(rebuilt.freshStages)
        #expect(saved.metadataFingerprint == stages.metadataFingerprint)
        #expect(saved.guideFingerprint != stages.guideFingerprint)
        #expect(rebuilt.guideMappings.matches == fresh.guideMappings.matches)
        #expect(rebuilt.directory.metadata == fresh.directory.metadata)
    }

    @Test func endedGuideIDsRecomputeGuideMatches() throws {
        let stages = try #require(try prepared().freshStages)
        let fewer = try PreparedCatalog(channels: channels, programs: Array(programs.dropFirst()), activeSources: [source], overrides: [:], stages: stages)
        let fresh = try PreparedCatalog(channels: channels, programs: Array(programs.dropFirst()), activeSources: [source], overrides: [:])
        #expect(fewer.freshStages?.guideFingerprint != stages.guideFingerprint)
        #expect(fewer.guideMappings.matches == fresh.guideMappings.matches)
    }

    @Test func roundTripsThroughCatalogCodec() throws {
        let stages = try #require(try prepared().freshStages)
        let decoded = try CatalogCodec.decode(PreparedStages.self, from: CatalogCodec.encode(stages))
        #expect(decoded == stages)
    }
}
