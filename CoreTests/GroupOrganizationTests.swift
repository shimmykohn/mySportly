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
    @Test func batchPromptContainsNoStreamAddressesAndHasExplicitNone() throws {
        let group = try #require(grouped([channel("a", "Golf 01 https://private.invalid/user/password", group: "Sports")]).groups.first)
        let input = GroupDecisionInput(group: group, parent: [], choices: GroupTaxonomy(paths: [["Sports"], ["News"]]).children(of: []))
        let questions = try OpenAIGroupModel.questions([input])
        let json = String(decoding: try JSONEncoder().encode(DecisionsRequest(input: "test", questions: questions)), as: UTF8.self)
        #expect(!json.contains("private.invalid"))
        #expect(!json.contains("password"))
        #expect(json.contains(#""type":"input_json""#))
        #expect(json.contains(#""model":"gpt-6-luna""#))
        let question = try #require(questions.first)
        #expect(question.name == group.id)
        #expect(question.choices.contains { $0.value == "none" })
        #expect(question.choices.first { $0.value == "category: Sports" }?.description?.contains("Sporting events") == true)
    }
    @Test func hierarchicalChoicesAndNoneRoutingAreValidated() async throws {
        let group = try #require(grouped([channel("a", "Golf 01"), channel("b", "Golf 02")]).groups.first)
        let taxonomy = GroupTaxonomy(paths: [["Sports", "Golf"], ["News"]])
        let model = ScriptedModel(choices: [TaxonomyNode.id(for: ["Sports"]), "none"])
        let namer = TestNamer()
        let result = try await GroupOrganizationPipeline.classify([group], taxonomy: taxonomy, model: model, namer: namer)
        #expect(result.first?.status == .needsName)
        #expect(result.first?.path == ["Sports"])
        #expect(result.first?.proposedName == "Golf")
        #expect(await namer.calls == 1)
        #expect(result.first?.applies(to: group) == false)
        let unavailable = try await GroupOrganizationPipeline.classify([group], taxonomy: taxonomy, model: ScriptedModel(choices: ["none"]))
        #expect(unavailable.first?.status == .needsName)
        #expect(unavailable.first?.proposedName == nil)
    }
    @Test func lowConfidenceAndOutOfTreeChoicesNeverBecomeAppliedClassifications() async throws {
        let group = try #require(grouped([channel("a", "ABC")]).groups.first)
        let taxonomy = GroupTaxonomy(paths: [["News"], ["Sports"]])
        let result = try await GroupOrganizationPipeline.classify([group], taxonomy: taxonomy,
            model: ScriptedModel(choices: [TaxonomyNode.id(for: ["News"])], confidence: 0.2))
        #expect(result.first?.status == .needsReview)
        #expect(result.first?.applies(to: group) == false)
        await #expect(throws: GroupDecisionFailure.self) {
            try await GroupOrganizationPipeline.classify([group], taxonomy: taxonomy, model: ScriptedModel(choices: ["invented"]))
        }
    }
    @Test func categorySpellingReusesExistingNodesAndBroadGroupsCanStopAtParent() async throws {
        var taxonomy = GroupTaxonomy(paths: [["Sports", "Golf"]])
        taxonomy.add(["sports", "golf", "Tournaments"])
        #expect(taxonomy.canonical(["SPORTS", "GOLF"]) == ["Sports", "Golf"])
        #expect(taxonomy.children(of: ["Sports", "Golf"]).first?.path == ["Sports", "Golf", "Tournaments"])
        let group = try #require(grouped([channel("a", "Sports Network")]).groups.first)
        let result = try await GroupOrganizationPipeline.classify([group], taxonomy: taxonomy,
            model: ScriptedModel(choices: [TaxonomyNode.id(for: ["Sports"]), "here"]))
        #expect(result.first?.path == ["Sports"])
        #expect(result.first?.status == .classified)
    }
    @Test func decisionsCanTraverseAnExtendedFourthLevel() async throws {
        let group = try #require(grouped([channel("a", "Documentary Cosmos")]).groups.first)
        let path = ["Documentary", "Science", "Space", "Cosmos"]
        let taxonomy = GroupTaxonomy(paths: [path])
        let result = try await GroupOrganizationPipeline.classify([group], taxonomy: taxonomy,
            model: ScriptedModel(choices: (1...4).map { TaxonomyNode.id(for: Array(path.prefix($0))) }))
        #expect(result.first?.status == .classified)
        #expect(result.first?.path == path)
    }
    @Test func responseRejectsMissingAnswersAndUnknownChoices() throws {
        let group = try #require(grouped([channel("a", "ABC")]).groups.first)
        let input = GroupDecisionInput(group: group, parent: [], choices: GroupTaxonomy(paths: [["News"]]).children(of: []))
        let request = DecisionsRequest(input: "test", questions: try OpenAIGroupModel.questions([input]))
        #expect(throws: DecisionsFailure.self) { try DecisionsClient.decode(Data(#"{"model":"gpt-6-luna","answers":[]}"#.utf8), for: request) }
        let payload: [String: Any] = ["model": "gpt-6-luna", "answers": [["type": "choice", "name": group.id, "choice": "invented", "confidence": 1,
                                                                       "probabilities": [["value": "invented", "probability": 1]]]]]
        #expect(throws: DecisionsFailure.self) { try DecisionsClient.decode(JSONSerialization.data(withJSONObject: payload), for: request) }
    }
    @Test func refusedGroupIsLeftForReviewWhileOthersApply() async throws {
        let index = try grouped([channel("1", "US CNN", group: "News"), channel("2", "Mystery feed", group: "")])
        let news = try #require(index.groups.first { $0.name.contains("CNN") }), other = try #require(index.groups.first { !$0.name.contains("CNN") })
        let taxonomy = GroupTaxonomy(paths: [["News"], ["Sports"]])
        let inputs = [news, other].map { GroupDecisionInput(group: $0, parent: [], choices: taxonomy.children(of: [])) }
        let request = DecisionsRequest(input: "test", questions: try OpenAIGroupModel.questions(inputs))
        let payload: [String: Any] = ["model": "gpt-6-luna", "answers": [
            ["type": "choice", "name": news.id, "choice": "category: News", "confidence": 0.9,
             "probabilities": [["value": "category: News", "probability": 0.92], ["value": "category: Sports", "probability": 0.05], ["value": "none", "probability": 0.03]]],
            ["type": "refusal", "name": other.id]]]
        let answers = try DecisionsClient.decode(JSONSerialization.data(withJSONObject: payload), for: request)
        let choices = OpenAIGroupModel.choices(answers, inputs: inputs)
        #expect(choices[news.id]?.choice == TaxonomyNode.id(for: ["News"]))
        #expect(choices[other.id] == nil)
        let result = try await GroupOrganizationPipeline.classify([news, other], taxonomy: taxonomy, model: MapModel(answers: choices))
        #expect(result.first { $0.id == news.id }?.status == .classified)
        #expect(result.first { $0.id == other.id }?.status == .needsReview)
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
    @Test func leafCategoriesFinishWithoutInventingANewChild() async throws {
        let group = try #require(grouped([channel("1", "US CNN", group: "News")]).groups.first)
        let model = ScriptedModel(choices: [TaxonomyNode.id(for: ["News"])])
        let result = try await GroupOrganizationPipeline.classify([group], taxonomy: .init(paths: [["News"]]), model: model)
        #expect(result.first?.status == .classified)
        #expect(result.first?.path == ["News"])
    }
    @Test func coverageAndCountryTagsDoNotInventSportsSubcategories() throws {
        let index = try grouped([
            channel("1", "US TENNIS 01"), channel("2", "US TENNIS 02"),
            channel("3", "TENNIS PPV 01"), channel("4", "TENNIS PPV 02"),
            channel("5", "NBA REPLAY 01"), channel("6", "NBA REPLAY 02")])
        #expect(index.taxonomy.children(of: ["Sports", "Tennis"]).isEmpty)
        #expect(index.taxonomy.children(of: ["Sports", "Basketball"]).map(\.label) == ["NBA"])
    }
    @Test func closeProbabilitySplitStaysReviewableWithoutRejectingTheBatch() async throws {
        let group = try #require(grouped([channel("1", "Unfamiliar television title", group: "")]).groups.first)
        let taxonomy = GroupTaxonomy(paths: [["Entertainment"], ["Documentary"]])
        let input = GroupDecisionInput(group: group, parent: [], choices: taxonomy.children(of: []))
        let request = DecisionsRequest(input: "test", questions: try OpenAIGroupModel.questions([input]))
        let response: [String: Any] = ["model": "gpt-6-luna", "answers": [["type": "choice", "name": group.id, "choice": "category: Entertainment", "confidence": 0.2,
            "probabilities": [["value": "category: Entertainment", "probability": 0.36], ["value": "category: Documentary", "probability": 0.37], ["value": "none", "probability": 0.27]]]]]
        let answers = OpenAIGroupModel.choices(try DecisionsClient.decode(JSONSerialization.data(withJSONObject: response), for: request), inputs: [input])
        let choice = try #require(answers[group.id])
        let result = try await GroupOrganizationPipeline.classify([group], taxonomy: taxonomy, model: FixedModel(choice: choice))
        #expect(result.first?.status == .needsReview)
        #expect(result.first?.applies(to: group) == false)
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
private struct FixedModel: GroupDecisionModel {
    let choice: GroupChoice
    func choose(_ inputs: [GroupDecisionInput]) async throws -> [String: GroupChoice] {
        Dictionary(uniqueKeysWithValues: inputs.map { ($0.group.id, choice) })
    }
}
private actor ScriptedModel: GroupDecisionModel {
    var choices: [String]
    let confidence: Double
    init(choices: [String], confidence: Double = 0.95) { self.choices = choices; self.confidence = confidence }
    func choose(_ inputs: [GroupDecisionInput]) async throws -> [String: GroupChoice] {
        let choice = choices.removeFirst()
        return Dictionary(uniqueKeysWithValues: inputs.map { ($0.group.id, GroupChoice(choice: choice, confidence: confidence, probability: 0.99)) })
    }
}
private actor TestNamer: GroupNameProposer {
    var calls = 0
    func propose(for group: CatalogNameGroup, under parent: [String]) async throws -> String? { calls += 1; return "Golf" }
}

private struct MapModel: GroupDecisionModel {
    let answers: [String: GroupChoice]
    func choose(_ inputs: [GroupDecisionInput]) async throws -> [String: GroupChoice] { answers.filter { key, _ in inputs.contains { $0.group.id == key } } }
}
