import Foundation
import Testing
@testable import SportlyCore

@Suite struct CatalogPassTests {
    private let source = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private func channel(_ id: String, _ name: String, group: String = "USA SPORTS", region: String = "US", language: String = "en") -> Channel {
        Channel(id: id, sourceID: source, name: name, group: group, language: language, region: region)
    }
    private func response(_ text: String, type: String = "output_text", status: String = "completed") -> Data {
        let body: [String: Any] = ["status": status, "output": [["type": "message", "content": [["type": type, type == "refusal" ? "refusal" : "text": text]]]]]
        return try! JSONSerialization.data(withJSONObject: body)
    }
    private func rows(_ text: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: ["rows": try! JSONSerialization.jsonObject(with: Data(text.utf8))]), as: UTF8.self)
    }

    @Test func requestSendsNumberedLinesWithoutKeysOrAddresses() throws {
        let row = PassRow(key: "local-key-7", name: "US| ESPN FHD http://provider.example/user/pass/7.ts", context: ["USA SPORTS", "US · en"], cluster: "c")
        let data = try CatalogPass.body(.channels, rows: [row], categories: [["News"], ["Sports", "American Football"]])
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "gpt-6-luna")
        #expect(body["store"] as? Bool == false)
        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["strict"] as? Bool == true)
        let input = try #require(body["input"] as? [[String: Any]])
        let content = try #require(input.last?["content"] as? String)
        #expect(content.contains("0\tNone of these"))
        #expect(content.contains("2\tSports / American Football"))
        #expect(content.contains("1\tUS| ESPN FHD"))
        #expect(content.contains("\tUSA SPORTS\tUS · en"))
        let raw = String(decoding: data, as: UTF8.self)
        #expect(!raw.contains("provider.example") && !raw.contains("local-key-7"))
    }

    @Test func titleRequestsAskForNamesGenresAndCopies() throws {
        let data = try CatalogPass.body(.titles, rows: [PassRow(key: "k", name: "EN - Dune (2021) 4K", context: ["Movie"])])
        let raw = String(decoding: data, as: UTF8.self)
        #expect(raw.contains("1\\tEN - Dune (2021) 4K\\tMovie"))
        #expect(raw.contains("\"subject\"") && raw.contains("\"Sci-Fi\"") && raw.contains("\"same\""))
        #expect(!raw.contains("\"section\"") && !raw.contains("\"set\""))
    }

    @Test func answersMapBackToRowsAndAreChecked() throws {
        let rows = [PassRow(key: "a", name: "US| ESPN FHD"), PassRow(key: "b", name: "US| ESPN BACKUP"), PassRow(key: "c", name: "FOX NEWS")]
        let text = self.rows(#"""
        [{"n":1,"name":"ESPN","section":2,"same":null},
         {"n":2,"name":"ESPN","section":2,"same":1},
         {"n":3,"name":"Fox News Channel Live","section":9,"same":7},
         {"n":1,"name":"Duplicate answer","section":1,"same":null},
         {"n":12,"name":"Unknown row","section":1,"same":null}]
        """#)
        let answers = try CatalogPass.decode(response(text), .channels, rows: rows, categoryCount: 3)
        #expect(answers.count == 3)
        #expect(answers["a"] == PassAnswer(name: "ESPN", category: 2, same: nil))
        #expect(answers["b"] == PassAnswer(name: "ESPN", category: 2, same: "a"))
        // Invented words, an unknown category and an unknown row are all dropped.
        #expect(answers["c"] == PassAnswer(name: nil, category: nil, same: nil))
    }

    @Test func refusalsAreEmptyAndCutOffAnswersAreRejected() throws {
        let rows = [PassRow(key: "a", name: "ESPN")]
        #expect(try CatalogPass.decode(response("no", type: "refusal"), .channels, rows: rows).isEmpty)
        #expect(throws: DecisionsFailure.invalidResponse) {
            try CatalogPass.decode(response(#"{"rows":[{"n":1,"name":"ESP"#, status: "incomplete"), .channels, rows: rows)
        }
        #expect(throws: DecisionsFailure.invalidResponse) { try CatalogPass.decode(response("not json"), .titles, rows: rows) }
    }

    @Test func chunksNeverSplitAClusterOfCopies() {
        let clusters = ["a", "a", "a", "b", "b", "c", "c", "c", "c", "d"]
        let rows = clusters.enumerated().map { PassRow(key: "\($0.offset)", name: "\($0.offset)", cluster: $0.element) }
        let chunks = CatalogPass.chunks(rows, size: 4)
        #expect(chunks.map(\.count) == [5, 4, 1])
        for cluster in Set(clusters) {
            #expect(chunks.filter { $0.contains { $0.cluster == cluster } }.count == 1)
        }
    }

    @Test func copiesLinkedThroughAnotherCopyMerge() {
        let a = channel("a", "ESPN HD"), b = channel("b", "ESPN FHD"), c = channel("c", "ESPN BACKUP"), d = channel("d", "ESPN 4K")
        let candidates = FeedMerging.candidates([a, b, c, d], strict: [])
        #expect(candidates.count == 3)
        let key = CatalogPass.rowKey
        let answers: [String: PassAnswer] = [
            key(a): PassAnswer(name: "ESPN"), key(b): PassAnswer(name: "ESPN", same: key(c)),
            key(c): PassAnswer(name: "ESPN", same: key(a)),
        ]
        let merges = CatalogPass.mergeAnswers(candidates, answers: answers)
        #expect(merges.count == 2)
        #expect(merges.values.allSatisfy { $0.same })
        // A pair with a row still unanswered waits for the next run.
        #expect(!merges.values.contains { $0.ids.contains("d") })
        let apart = CatalogPass.mergeAnswers(candidates, answers: [key(a): PassAnswer(), key(b): PassAnswer()])
        #expect(apart.values.map(\.same) == [false])
    }

    @Test func placementsFollowTheMajorityAndAskForANameWhenNoneFits() {
        func group(_ id: String, _ channels: [String]) -> CatalogNameGroup {
            CatalogNameGroup(id: id, name: id, fingerprint: "f-" + id, channelIDs: channels, titles: [], providerGroups: [],
                             language: "en", region: "US", localPath: [], family: false)
        }
        let categories = [["News"], ["Sports"], ["Sports", "Golf"]]
        let votes = ["x": 3, "y": 3, "z": 2, "p": 1, "q": 2, "r": 0, "t": 0, "u": 2]
        let result = CatalogPass.placements([group("golf", ["x", "y", "z"]), group("split", ["p", "q"]), group("none", ["r"]),
                                             group("unanswered", ["s"]), group("tie", ["t", "u"])], categories: categories, channelCategory: votes)
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        #expect(byID.count == 4 && byID["unanswered"] == nil)
        #expect(byID["golf"]?.path == ["Sports", "Golf"] && byID["golf"]?.status == .classified)
        #expect(byID["split"]?.path == ["News"] && byID["split"]?.status == .needsReview)
        #expect(byID["none"]?.path == [] && byID["none"]?.status == .needsName)
        #expect(byID["tie"]?.path == ["Sports"] && byID["tie"]?.status == .needsReview)
        #expect(byID["golf"]?.decisionVersion == GroupPlacement.currentDecisionVersion)
    }

    @Test func rowsCoverOnlyTheLineupAndBringCopiesAlong() throws {
        let channels = [channel("a", "US| ESPN HD"), channel("b", "US| ESPN FHD"), channel("n", "US| CNN"),
                        channel("f", "FR| TF1", group: "FRANCE", region: "FR", language: "fr")]
        var resolver = ChannelMetadataResolver()
        let metadata = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, resolver.resolve($0)) })
        let index = try CatalogGroupIndex(channels: channels, metadata: metadata)
        let audience = ChannelAudience(scope: .preferred, languages: ["en"], regions: ["US"])
        // ESPN HD and CNN were asked before; ESPN FHD is new, so its copy comes along.
        let rows = CatalogPass.channelRows(channels, groups: index, audience: audience, asked: ["US| ESPN HD", "US| CNN"], pendingGroups: [], limit: 100)
        #expect(Set(rows.map(\.name)) == ["US| ESPN HD", "US| ESPN FHD"])
        #expect(rows.allSatisfy { $0.context.first == "USA SPORTS" && $0.cluster == rows[0].cluster })
        let everything = CatalogPass.channelRows(channels, groups: index, audience: .init(), asked: [], pendingGroups: [], limit: 100)
        #expect(everything.count == 4)
    }

    @Test func titleRowsSkipAskedTitlesAndKeepCopiesTogether() {
        let rows = CatalogPass.titleRows(movies: ["EN - Dune (2021)", "Arrival", "4K - Dune (2021)", "Arrival"], shows: ["Dune Prophecy"],
                                         asked: ["Arrival"], limit: 10)
        #expect(rows.map(\.name) == ["4K - Dune (2021)", "EN - Dune (2021)", "Dune Prophecy"])
        #expect(rows.last?.context == ["Show"])
    }

    @Test func aNewPassAsksEveryNameAgainOnce() {
        var results = AIResults()
        results.names = ["US| ESPN": "ESPN"]; results.namesAsked = ["US| ESPN"]; results.vodNamesAsked = ["Dune"]
        results.startPass(CatalogPass.version)
        #expect(results.namesAsked.isEmpty && results.vodNamesAsked == [] && results.names["US| ESPN"] == "ESPN")
        results.namesAsked = ["US| ESPN"]
        results.startPass(CatalogPass.version)
        #expect(results.namesAsked == ["US| ESPN"])
    }
}

@Suite struct AIExamplesTests {
    @Test func examplesShowOnlyWhatTheModelChangedBeyondLocalRules() {
        var results = AIResults()
        // Local rules already turn "US| ESPN HD" into "ESPN", so that isn't the model's doing.
        results.names = ["US| ESPN HD": "ESPN", "|AR| ★ BEIN SPORTS 1 ★": "beIN Sports 1", "FOX": "FOX"]
        results.vodNames = ["EN - THE MATRIX (1999) 4K": "The Matrix"]
        let examples = results.examples()
        #expect(examples.map(\.before) == ["|AR| ★ BEIN SPORTS 1 ★", "EN - THE MATRIX (1999) 4K"])
        #expect(examples.first?.after == "beIN Sports 1")
    }
}

@Suite struct ChannelFamilyTests {
    private let source = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private func channel(_ id: String, _ name: String) -> Channel { Channel(id: id, sourceID: source, name: name) }

    @Test func familiesComeBackCheckedAgainstTheName() throws {
        let rows = [PassRow(key: "a", name: "NFL 07: Cowboys vs Packers"), PassRow(key: "b", name: "ESPN 2"), PassRow(key: "c", name: "PPV 3")]
        let text = #"{"rows":[{"n":1,"name":"NFL 07: Cowboys vs Packers","section":1,"same":null,"set":"NFL"},"#
            + #"{"n":2,"name":"ESPN 2","section":1,"same":null,"set":null},"#
            + #"{"n":3,"name":"PPV 3","section":1,"same":null,"set":"Pay Per View"}]}"#
        let body: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        let answers = try CatalogPass.decode(JSONSerialization.data(withJSONObject: body), .channels, rows: rows, categoryCount: 1)
        #expect(answers["a"]?.family == "NFL")
        #expect(answers["b"]?.family == nil)
        // Words that aren't in the name are rejected.
        #expect(answers["c"]?.family == nil)
    }

    @Test func numberedSetsFoldIntoOneEntryInNumberOrder() {
        let items = [channel("1", "NFL 10"), channel("2", "CNN"), channel("3", "NFL 02"), channel("4", "PPV 1"), channel("5", "NFL 01")]
        let families = ["NFL 10": "NFL", "NFL 02": "NFL", "NFL 01": "NFL", "PPV 1": "PPV"]
        let entries = ChannelFamilies.collapse(items, channel: { $0 }) { families[$0.name] }
        #expect(entries.count == 3)
        guard case .family(let name, let members) = entries[0] else { Issue.record("Expected the NFL set first"); return }
        #expect(name == "NFL" && members.map(\.name) == ["NFL 01", "NFL 02", "NFL 10"])
        guard case .single(let cnn) = entries[1], case .single(let ppv) = entries[2] else { Issue.record("Expected singles"); return }
        // A set of one stays a plain channel.
        #expect(cnn.name == "CNN" && ppv.name == "PPV 1")
    }
}


@Suite struct TitlePassTests {
    @Test func genresAreCheckedAgainstTheList() throws {
        let rows = [PassRow(key: "a", name: "EN - Dune (2021)", context: ["Movie"]), PassRow(key: "b", name: "Arrival", context: ["Movie"])]
        let text = #"{"rows":[{"n":1,"name":"Dune","same":null,"subject":"Sci-Fi"},{"n":2,"name":"Arrival","same":null,"subject":"Space Opera"}]}"#
        let body: [String: Any] = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]]
        let answers = try CatalogPass.decode(JSONSerialization.data(withJSONObject: body), .titles, rows: rows)
        #expect(answers["a"]?.genre == "Sci-Fi")
        #expect(answers["b"]?.genre == nil)
    }

    @Test func copiesNeedTheSameKindAndAgreeingYears() {
        let rows = [PassRow(key: "EN - Dune (2021)", name: "EN - Dune (2021)", context: ["Movie"]),
                    PassRow(key: "4K - Dune (2021)", name: "4K - Dune (2021)", context: ["Movie"]),
                    PassRow(key: "Dune (1984)", name: "Dune (1984)", context: ["Movie"]),
                    PassRow(key: "Dune", name: "Dune", context: ["Show"])]
        let answers: [String: PassAnswer] = [
            "EN - Dune (2021)": PassAnswer(name: "Dune"),
            "4K - Dune (2021)": PassAnswer(name: "Dune", same: "EN - Dune (2021)"),
            "Dune (1984)": PassAnswer(name: "Dune", same: "EN - Dune (2021)"),
            "Dune": PassAnswer(name: "Dune", same: "EN - Dune (2021)"),
        ]
        let copies = CatalogPass.titleCopies(rows, answers: answers)
        // The 4K copy joins; the 1984 film and the show stay apart.
        #expect(copies == ["EN - Dune (2021)": "4K - Dune (2021)"] || copies == ["4K - Dune (2021)": "EN - Dune (2021)"])
    }

    @Test func foldedCopiesShowOnceWithTheirVersions() {
        let source = UUID()
        let movies = [Movie(id: "1", sourceID: source, providerID: "1", rawTitle: "EN - Dune (2021)", title: "Dune"),
                      Movie(id: "2", sourceID: source, providerID: "2", rawTitle: "4K - Dune (2021)", title: "Dune"),
                      Movie(id: "3", sourceID: source, providerID: "3", rawTitle: "Arrival", title: "Arrival")]
        let (shown, versions, hidden) = VODCopies.fold(movies, copies: ["4K - Dune (2021)": "EN - Dune (2021)"])
        #expect(shown.map(\.id) == ["1", "3"])
        #expect(versions == ["1": ["2"]] && hidden["2"]?.rawTitle == "4K - Dune (2021)")
    }

    @Test func genreFilterUsesTheAIGenres() {
        let source = UUID()
        let movies = [Movie(id: "1", sourceID: source, providerID: "1", rawTitle: "Dune", title: "Dune"),
                      Movie(id: "2", sourceID: source, providerID: "2", rawTitle: "Up", title: "Up")]
        var filter = VODFilter(); filter.genre = "Animation"
        let rows = [VODShelfRow(id: "r", title: "All", items: movies)]
        #expect(filter.apply(rows, genres: ["1": "Sci-Fi", "2": "Animation"]).map(\.id) == ["2"])
    }

    @Test func usageAddsUpToAnEstimatedCost() throws {
        let body = #"{"usage":{"input_tokens":1000000,"input_tokens_details":{"cached_tokens":500000},"output_tokens":200000}}"#
        let usage = TokenUsage.parse(Data(body.utf8)) + TokenUsage(requests: 1)
        #expect(usage == TokenUsage(input: 1_000_000, cached: 500_000, output: 200_000, requests: 2))
        // 0.5M fresh × $0.10 + 0.5M cached × $0.01 + 0.2M out × $0.50 = $0.155
        #expect(abs(usage.dollars - 0.155) < 0.000_001)
        #expect(0.004.dollarText == "< $0.01")
    }
}
