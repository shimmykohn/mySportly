import Foundation
import Testing
@testable import SportlyCore

@Suite struct GroupOrganizationTests {
    private let source = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private func channel(_ id: String, _ name: String, group: String = "Sports", region: String = "US") -> Channel {
        Channel(id: id, sourceID: source, name: name, group: group, language: "en", region: region)
    }
    private func grouped(_ channels: [Channel], placements: [String: GroupPlacement] = [:]) throws -> CatalogGroupIndex {
        var resolver = ChannelMetadataResolver()
        let metadata = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, resolver.resolve($0)) })
        return try CatalogGroupIndex(channels: channels, metadata: metadata, placements: placements)
    }
    @Test func decisionsSurviveChangedStreamIDsQualityAndFewerSlots() throws {
        let original = try grouped([channel("old1", ":Golf 07 HD"), channel("old2", ":Golf 08 4K")])
        let group = try #require(original.groups.first)
        let placement = GroupPlacement(group: group, path: ["Sports", "Golf"], confidence: 0.95, status: .classified, origin: "OpenAI")
        let next = try grouped([channel("new", ":Golf 10 FHD")], placements: [group.id: placement])
        #expect(next.groups.count == 1)
        #expect(next.groups[0].id == group.id)
        #expect(next.path(for: "new") == ["Sports", "Golf"])
        #expect(next.pending(in: .init()).isEmpty)
    }
    @Test func groupingDoesNotMergeEditionsOrEraseStreamsOrInferASport() throws {
        let channels = [channel("a", "NEWLEAGUE 01", group: "American Football"), channel("b", "NEWLEAGUE 02", group: "American Football"),
                        channel("ca", "NEWLEAGUE 01", group: "American Football", region: "CA"), channel("other", "NEWLEAGUE News", group: "News")]
        let index = try grouped(channels)
        #expect(index.channelGroup["a"] == index.channelGroup["b"])
        #expect(index.channelGroup["a"] != index.channelGroup["ca"])
        #expect(index.channelGroup["a"] != index.channelGroup["other"])
        #expect(Set(index.groups.flatMap(\.channelIDs)) == Set(channels.map(\.id)))
        #expect(index.taxonomy.children(of: ["Sports", "American Football"]).contains { $0.label == "NEWLEAGUE" })
        let generic = try grouped([channel("1", "Something Unfamiliar", group: "")])
        #expect(generic.path(for: "1").isEmpty)
    }
    @Test func changedProviderContextRechecksMachineButKeepsManualDecision() throws {
        let group = try #require(grouped([channel("a", "ABC HD", group: "News")]).groups.first)
        let placement = GroupPlacement(group: group, path: ["News"], confidence: 1, status: .classified, origin: "OpenAI")
        let next = try grouped([channel("b", "ABC 4K", group: "Movies")], placements: [group.id: placement])
        #expect(next.pending(in: .init()).count == 1)
        #expect(next.path(for: "b") == ["Movies"])
        var manual = placement; manual.manual = true
        let corrected = try grouped([channel("c", "ABC SD", group: "Movies")], placements: [group.id: manual])
        #expect(corrected.path(for: "c") == ["News"])
    }
    @Test func customPathsDriveBrowseAndRespectManualChannelCorrection() throws {
        let channels = [channel("a", "Example 01", group: ""), channel("b", "Example 02", group: "")]
        let group = try #require(grouped(channels).groups.first)
        let placement = GroupPlacement(group: group, path: ["Learning", "Astronomy"], confidence: 1, status: .classified, origin: "Correction", manual: true)
        let overrides = ["taxonomy.placement.\(group.id)": try JSONEncoder().encode(placement),
                         "channel.b.category": try JSONEncoder().encode("News"), "channel.b.manual.category": try JSONEncoder().encode(true)]
        let directory = try ChannelDirectory(channels: channels, overrides: overrides)
        var request = ChannelBrowseRequest(); request.taxonomyPath = ["Learning", "Astronomy"]
        #expect(try directory.browse(request).map(\.id) == ["a"])
        #expect(directory.metadata["b"]?.category == "News")
        #expect(directory.nameGroups.taxonomy.children(of: ["Learning"]).first?.label == "Astronomy")
        let roundTrip = try JSONDecoder().decode(GroupPlacement.self, from: JSONEncoder().encode(placement))
        #expect(roundTrip.path == placement.path)
    }
    @Test func explicitSlotsKeepIdentityWhenEventNamesAndDatesChange() throws {
        let original = try grouped([channel("old", "US (NEWLEAGUE 02) | Red vs Blue (2026-10-18 18:00:00)", group: "Sports")])
        let group = try #require(original.groups.first)
        let saved = GroupPlacement(group: group, path: ["Sports", "American Football", "NEWLEAGUE"], confidence: 0.9, status: .classified, origin: "OpenAI")
        let updated = try grouped([channel("new", "US (NEWLEAGUE 45) | Green vs Gold (2026-10-20 19:00:00)", group: "Sports")], placements: [group.id: saved])
        #expect(updated.groups.first?.id == group.id)
        #expect(updated.pending(in: .init()).isEmpty)
        let suffix = try grouped([channel("1", "Red vs Blue @ Oct 18 10:00 PM :Tennis 03"), channel("2", ":Tennis 04")])
        #expect(suffix.groups.count == 1)
        #expect(suffix.groups.first?.name == "Tennis")
    }
    @Test func savingAnUnnumberedChannelDoesNotInventANumberedFamily() throws {
        let channels = [channel("one", "US MTV", group: "Entertainment"), channel("two", "US MTV 2", group: "Entertainment")]
        let original = try grouped(channels)
        let group = try #require(original.groups.first { $0.channelIDs == ["one"] })
        let saved = GroupPlacement(group: group, path: ["Music"], confidence: 1, status: .classified, origin: "OpenAI")
        let next = try grouped(channels, placements: [group.id: saved])
        #expect(next.groups.count == original.groups.count)
        #expect(next.channelGroup == original.channelGroup)
    }
    @Test func coverageAndCountryTagsDoNotInventSportsSubcategories() throws {
        let index = try grouped([
            channel("1", "US TENNIS 01"), channel("2", "US TENNIS 02"),
            channel("3", "TENNIS PPV 01"), channel("4", "TENNIS PPV 02"),
            channel("5", "NBA REPLAY 01"), channel("6", "NBA REPLAY 02")])
        #expect(index.taxonomy.children(of: ["Sports", "Tennis"]).isEmpty)
        #expect(index.taxonomy.children(of: ["Sports", "Basketball"]).map(\.label) == ["NBA"])
    }
    @Test func reviewResultsAreReusableButOlderPolicyVersionsNeedRechecking() throws {
        let channels = [channel("1", "Unfamiliar title", group: "")]
        let group = try #require(grouped(channels).groups.first)
        var saved = GroupPlacement(group: group, path: ["News"], confidence: 0.3, status: .needsReview, origin: "OpenAI")
        #expect(saved.isReusable(for: group))
        #expect(try grouped(channels, placements: [group.id: saved]).pending(in: .init()).isEmpty)
        saved.decisionVersion = nil
        #expect(!saved.isReusable(for: group))
        saved.manual = true
        #expect(saved.isReusable(for: group))
    }
    @Test func durableQueueResumesOnlyUnfinishedGroups() throws {
        var run = GroupOrganizationRun(groupIDs: ["a", "b", "b", "c"])
        run.checkpoint(["a", "a", "unrelated"])
        let restored = try JSONDecoder().decode(GroupOrganizationRun.self, from: JSONEncoder().encode(run))
        #expect(restored.total == 3)
        #expect(restored.completed == 1)
        #expect(restored.remainingIDs == ["b", "c"])
        run.checkpoint(["b", "c"])
        #expect(run.isComplete)
    }
}
