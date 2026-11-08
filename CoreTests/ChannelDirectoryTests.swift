import Foundation
import Testing
@testable import SportlyCore

struct ChannelDirectoryTests {
    @Test func browsingKeepsEveryFeedButCollapsesOnlyExplicitVariants() throws {
        let source = UUID()
        let channels = [
            Channel(id: "a", sourceID: source, name: "Café News HD", group: "News", language: "en", region: "US"),
            Channel(id: "b", sourceID: source, name: "Café News SD", group: "News", language: "en", region: "US"),
            Channel(id: "c", sourceID: source, name: "Other", group: "Sports", language: "es", region: "ES")
        ]
        let encoder = JSONEncoder()
        let directory = try ChannelDirectory(channels: channels, overrides: [
            "channel.a.variants": try encoder.encode(["a", "b"]), "channel.b.variants": try encoder.encode(["a", "b"]),
            "channel.c.hidden": try encoder.encode(true)
        ])
        var request = ChannelBrowseRequest(); request.query = "cafe"
        #expect(try directory.browse(request).map(\.id) == ["a", "b"])
        request.collapseVariants = true
        #expect(try directory.browse(request).map(\.id) == ["a"])
        request.collapseVariants = false; request.query = ""; request.includeHidden = true
        #expect(try directory.browse(request).count == 3)
        #expect(directory.visibleCategories == ["News"])
        #expect(directory.categories == ["News", "Sports"])
        #expect(directory.sourceCounts[source] == 3)
    }

    @Test func guideRankingUsesOverridesAndKeepsUnknownLanguages() throws {
        let source = UUID(), encoder = JSONEncoder()
        let channels = [Channel(id: "a", sourceID: source, name: "Alpha", language: "es"),
                        Channel(id: "b", sourceID: source, name: "Beta"),
                        Channel(id: "c", sourceID: source, name: "Gamma", language: "en", region: "US")]
        let directory = try ChannelDirectory(channels: channels, overrides: ["channel.a.favorite": try encoder.encode(true)])
        var request = ChannelBrowseRequest(); request.ranked = true; request.collapseVariants = true
        let preferences = RecommendationPreferences(languages: ["en"], regions: ["US"], interests: [], following: [], watched: [])
        #expect(try directory.browse(request, preferences: preferences).map(\.id) == ["a", "c", "b"])
        request.preferredLanguagesOnly = true
        #expect(try directory.browse(request, preferences: preferences).count == 3)
    }

    @Test func sourceRemovalDoesNotLeaveGuideRowsOrSearchResults() throws {
        let removed = UUID(), kept = UUID(), date = Date.now
        let snapshot = try PreparedCatalog(channels: [Channel(id: "gone", sourceID: removed, name: "Gone"), Channel(id: "kept", sourceID: kept, name: "Kept")],
            programs: [GuideProgram(id: "gone-guide", sourceID: removed, guideID: "x", title: "Gone", start: date, end: date + 600)], activeSources: [kept], overrides: [:])
        #expect(snapshot.directory.channels.map(\.id) == ["kept"])
        #expect(snapshot.guide.isEmpty)
        #expect(snapshot.guideIDs[removed] == nil)
        #expect(snapshot.query.channelCount == 1)
    }
}
