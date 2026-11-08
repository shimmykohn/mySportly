import Foundation
import Testing
@testable import SportlyCore

@Suite struct CatalogQueryTests {
    private let source = UUID()
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func searchHonorsManualNamesLanguagesFavoritesMappingAndTimeOffset() throws {
        let channel = Channel(id: "channel", sourceID: source, name: "Original", guideID: "wrong")
        let program = GuideProgram(id: "game", sourceID: source, guideID: "correct", title: "Basketball Finals", start: date - 7200, end: date - 1800)
        let encoder = JSONEncoder()
        let overrides = ["channel.channel.name": try encoder.encode("Téle Local"), "channel.channel.language": try encoder.encode("en"),
            "channel.channel.favorite": try encoder.encode(true), "channel.channel.guideID": try encoder.encode("correct"), "channel.channel.guideOffset": try encoder.encode(60)]
        let index = try CatalogQueryIndex(channels: [channel], programs: [program], overrides: overrides)
        let matches = try index.search(.init(keywords: ["tele", "finals"], start: date, end: date + 1, sportsOnly: true, favoritesOnly: true, language: "en"))
        #expect(matches.count == 1)
        #expect(matches.first?.name == "Téle Local")
        #expect(matches.first?.program?.start == program.start + 3600)
        #expect(try index.search(.init(keywords: [], start: date, end: date + 1, language: "es")).isEmpty)
        #expect(try index.search(.init(keywords: ["finals"], start: date + 7200, end: date + 7201)).isEmpty)
    }

    @Test func sportsDeduplicatesSharedGuidesAndKeepsSportsCategoryListings() throws {
        let channels = [
            Channel(id: "first", sourceID: source, name: "First", guideID: "shared"),
            Channel(id: "sports", sourceID: source, name: "Sports Feed", group: "Sports", guideID: "shared"),
            Channel(id: "variant", sourceID: source, name: "Variant HD", guideID: "shared")
        ]
        let programs = [
            GuideProgram(id: "game", sourceID: source, guideID: "shared", title: "Knicks Basketball", start: date - 30, end: date + 60),
            GuideProgram(id: "studio", sourceID: source, guideID: "shared", title: "Studio Discussion", start: date + 60, end: date + 120)
        ]
        let index = try CatalogQueryIndex(channels: channels, programs: programs)
        let sports = try index.sports(at: date)
        #expect(sports.live.count == 1)
        #expect(sports.live.first?.channel.id == "first")
        #expect(sports.upcoming.count == 1)
        #expect(sports.upcoming.first?.channel.id == "sports")
        let followed = try index.sports(at: date, following: ["KNICKS"], followedOnly: true)
        #expect(followed.live.count == 1)
        #expect(followed.upcoming.isEmpty)
        #expect(try index.sports(at: date, followedOnly: true).isEmpty)
        let later = try index.sports(at: date + 60)
        #expect(later.live.first?.program.id == "studio")
        #expect(later.upcoming.isEmpty)
    }

    @Test func guideKeysAreSourceScopedAndOffsetFeedsChooseTheEarliestEligibleEvent() throws {
        let second = UUID()
        let channels = [Channel(id: "delayed", sourceID: source, name: "Delayed", guideID: "same"),
            Channel(id: "normal", sourceID: source, name: "Normal", guideID: "same"),
            Channel(id: "other", sourceID: second, name: "Other", guideID: "same")]
        let programs = [GuideProgram(id: "same-id", sourceID: source, guideID: "same", title: "Football", start: date, end: date + 1800),
            GuideProgram(id: "same-id", sourceID: second, guideID: "same", title: "Tennis", start: date, end: date + 1800)]
        let index = try CatalogQueryIndex(channels: channels, programs: programs, overrides: ["channel.delayed.guideOffset": try JSONEncoder().encode(60)])
        let schedule = try index.sports(at: date)
        #expect(schedule.live.count == 2)
        #expect(schedule.upcoming.isEmpty)
        #expect(schedule.live.first { $0.program.title == "Football" }?.channel.id == "normal")
        #expect(try index.search(.init(keywords: ["tennis"], start: date, end: date + 1)).map(\.id) == ["other"])
    }

    @Test func recommendationHistoryIsAQueryInputAndFavoriteRankIsPreserved() throws {
        let channels = (0..<20).map { Channel(id: "\($0)", sourceID: source, name: String(format: "%02d", $0), guideID: "shared", language: "en") }
        let program = GuideProgram(id: "game", sourceID: source, guideID: "shared", title: "Tennis", start: date, end: date + 60)
        let index = try CatalogQueryIndex(channels: channels, programs: [program], overrides: ["channel.19.favorite": try JSONEncoder().encode(true)])
        var preferences = RecommendationPreferences(languages: ["en"], regions: [], interests: [], following: [], watched: [])
        let initial = try index.recommendations(at: date, preferences: preferences)
        #expect(initial.count == 1, "Feeds sharing one schedule should not fill Home with duplicate recommendations")
        #expect(initial.first?.id == "19")
        preferences.watched = ["18"]
        #expect(try index.recommendations(at: date, preferences: preferences).first?.id == "18")
    }

    @Test func fullSizedCatalogQueriesStayBoundedAndSearchEveryChannel() async throws {
        let source = source, date = date
        try await catalogWork {
            let channels = (0..<57_033).map { Channel(id: "\($0)", sourceID: source, name: "Channel \($0)", guideID: "guide\($0 % 3500)") }
            let programs = (0..<220_500).map { position in
                let slot = position / 3500
                return GuideProgram(id: "p\(position)", sourceID: source, guideID: "guide\(position % 3500)", title: slot.isMultiple(of: 3) ? "Basketball Finals" : "Evening News", start: date + Double(slot) * 1800, end: date + Double(slot + 1) * 1800)
            }
            let buildStart = Date()
            let index = try CatalogQueryIndex(channels: channels, programs: programs)
            let queryStart = Date()
            let all = try index.search(.init(keywords: [], start: date, end: date + 1))
            #expect(all.count == 57_033)
            #expect(all.last?.id == "57032")
            let schedule = try index.sports(at: date)
            #expect(schedule.live.count == 3500)
            #expect(schedule.upcoming.count == 70_000)
            let elapsed = Date().timeIntervalSince(queryStart)
            print("[CatalogPerformance] synthetic_build_seconds=\(queryStart.timeIntervalSince(buildStart)) queries_seconds=\(elapsed)")
            #expect(elapsed < 5, "Queries must not do variant-multiplied guide processing")
        }
    }

    @Test func cancellingTheOwnerCancelsDetachedCatalogWork() async throws {
        let task = Task {
            try await catalogWork {
                for _ in 0..<10_000_000 { try Task.checkCancellation() }
                return true
            }
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled query unexpectedly completed") }
        catch is CancellationError { }
    }
}
