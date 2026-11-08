import Foundation
import Testing
@testable import SportlyCore

struct ChannelMetadataTests {
    private let source = UUID()
    @Test func tagsNormalizeCountriesAndLanguagesWithoutGuessingAudio() {
        var resolver = ChannelMetadataResolver()
        let us = resolver.resolve(Channel(id: "us", sourceID: source, name: "US | CNN FHD", group: "USA NEWS"))
        #expect(us.region == "US" && us.language.isEmpty && us.category == "News")
        let uk = resolver.resolve(Channel(id: "uk", sourceID: source, name: "[UK] BBC News [EN]", group: "International"))
        #expect(uk.region == "GB" && uk.language == "en")
        let spanish = resolver.resolve(Channel(id: "es", sourceID: source, name: "US | Spanish News", group: "USA"))
        #expect(spanish.region == "US" && spanish.language == "es")
        let explicit = resolver.resolve(Channel(id: "fr", sourceID: source, name: "US | News", language: "fra", region: "ca"))
        #expect(explicit.region == "CA" && explicit.language == "fr")
    }
    @Test func ambiguousWordsAndConflictingTagsStayUnclassified() {
        var resolver = ChannelMetadataResolver()
        for name in ["This Is Us", "RUSSIAN Cinema", "CANAL One", "In The Loop", "No Signal", "US / UK News"] {
            #expect(resolver.resolve(Channel(id: name, sourceID: source, name: name)).region.isEmpty, "Ambiguous name: \(name)")
        }
        let result = resolver.resolve(Channel(id: "multi", sourceID: source, name: "US | English Spanish News"))
        #expect(result.region == "US" && result.language.isEmpty)
        #expect(resolver.resolve(Channel(id: "conflict", sourceID: source, name: "CA | Local News", group: "USA Locals")).region.isEmpty)
    }
    @Test func filteringIsSharedAndManualCorrectionsWin() throws {
        let channels = [
            Channel(id: "us", sourceID: source, name: "US | News [EN]", guideID: "shared"),
            Channel(id: "unknown-audio", sourceID: source, name: "US | Sports", guideID: "shared"),
            Channel(id: "uk", sourceID: source, name: "UK | Sports [EN]", guideID: "shared"),
            Channel(id: "spanish", sourceID: source, name: "US | Spanish News", guideID: "shared"),
            Channel(id: "unknown", sourceID: source, name: "Mystery", guideID: "")
        ]
        let preferred = ChannelAudience(scope: .preferred, languages: ["en-US"], regions: ["USA"])
        let directory = try ChannelDirectory(channels: channels)
        var request = ChannelBrowseRequest(); request.audience = preferred
        #expect(Set(try directory.browse(request).map(\.id)) == ["us", "unknown-audio"])
        request.audience.includeUnknownLanguage = false
        #expect(try directory.browse(request).map(\.id) == ["us"])
        request.audience.scope = .unclassified
        #expect(Set(try directory.browse(request).map(\.id)) == ["unknown", "unknown-audio"])
        let corrected = try ChannelDirectory(channels: channels, overrides: ["channel.uk.region": try JSONEncoder().encode("US")])
        request.audience = preferred
        #expect(try corrected.browse(request).contains { $0.id == "uk" })
        #expect(channels[2].name == "UK | Sports [EN]" && channels[2].region.isEmpty)
    }
    @Test func sportsChoosesAnEligibleFeedWhenAGuideIsShared() throws {
        let date = Date.now
        let channels = [Channel(id: "uk", sourceID: source, name: "UK | Sports [EN]", guideID: "sports"),
                        Channel(id: "us", sourceID: source, name: "US | Sports [EN]", guideID: "sports")]
        let program = GuideProgram(id: "game", sourceID: source, guideID: "sports", title: "Basketball", start: date - 60, end: date + 3600)
        let index = try CatalogQueryIndex(channels: channels, programs: [program])
        let audience = ChannelAudience(scope: .preferred, languages: ["en"], regions: ["US"])
        #expect(try index.search(.init(keywords: [], start: date, end: date + 1, audience: audience)).map(\.id) == ["us"])
        #expect(try index.sports(at: date, audience: audience).live.first?.channel.id == "us")
        let preferences = RecommendationPreferences(languages: ["en"], regions: ["US"], interests: [], following: [], watched: [])
        #expect(try index.recommendations(at: date, preferences: preferences, audience: audience).map(\.id) == ["us"])
    }
    @Test func guideCoverageDistinguishesMissingIDsFromExpiredSchedules() throws {
        let date = Date.now
        let channels = [Channel(id: "live", sourceID: source, name: "US | News [EN]", guideID: "live"),
                        Channel(id: "ended", sourceID: source, name: "US | News", guideID: "ended"),
                        Channel(id: "missing", sourceID: source, name: "US | Mystery"),
                        Channel(id: "unmatched", sourceID: source, name: "US | Other", guideID: "absent")]
        let programs = [GuideProgram(id: "live", sourceID: source, guideID: "live", title: "News", start: date - 60, end: date + 60),
                        GuideProgram(id: "ended", sourceID: source, guideID: "ended", title: "Earlier", start: date - 3600, end: date - 60)]
        let index = try CatalogQueryIndex(channels: channels, programs: programs)
        let coverage = try index.coverage(at: date)
        #expect(coverage.channels == 4 && coverage.matched == 2 && coverage.onNow == 1)
        #expect(coverage.missingID == 1 && coverage.unmatchedID == 1 && coverage.noUpcoming == 1)
        #expect(coverage.unknownLanguage == 3)
        #expect(try index.channelsWithListings(from: date, to: date + 3600) == ["live"])
        #expect(try index.channelsWithListings(from: date - 3500, to: date - 100) == ["ended"])
    }
}
