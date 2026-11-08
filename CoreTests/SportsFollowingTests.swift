import Foundation
import Testing
@testable import SportlyCore

@Suite struct SportsFollowingTests {
    @Test func aliasesAndWordBoundariesAreConservative() {
        #expect(SportsFollowMatcher(["New York Knicks"]).matches(text: "Knicks vs. Celtics") == ["New York Knicks"])
        #expect(SportsFollowMatcher(["Dallas Cowboys"]).matches(text: "SNF: Cowboys at Packers") == ["Dallas Cowboys"])
        #expect(SportsFollowMatcher(["NBA"]).matches(text: "WNBA Finals").isEmpty)
        #expect(SportsFollowMatcher(["Mets"]).matches(text: "Comets basketball").isEmpty)
        #expect(SportsFollowMatcher(["New York Giants"]).matches(text: "Giants vs. Dodgers", context: "MLB Baseball").isEmpty)
        #expect(SportsFollowMatcher(["New York Giants"]).matches(text: "Giants at Cowboys", context: "NFL Football") == ["New York Giants"])
        #expect(SportsFollowMatcher(["NFL"]).matches(text: "Cowboys at Packers") == ["NFL"])
        #expect(SportsFollowMatcher(["Knicks", "New York Knicks"]).matches(text: "Knicks") == ["New York Knicks"])
        #expect(SportsFollowCatalog.choice(named: "Rangers") == nil)
        #expect(SportsFollowCatalog.choice(named: "NY Rangers")?.name == "New York Rangers")
        #expect(SportsFollowMatcher(["Team A"]).matches(text: "Team A vs Team B") == ["Team A"])
    }

    @Test func followingUsesDescriptionsAndKeepsUnscheduledChannelsSeparate() throws {
        let source = UUID(), now = Date.now
        let channels = [Channel(id: "scheduled", sourceID: source, name: "NBC", group: "Sports", guideID: "nbc", language: "en", region: "US"),
            Channel(id: "event", sourceID: source, name: "NFL | Cowboys at Packers", group: "NFL", language: "en", region: "US"),
            Channel(id: "idle", sourceID: source, name: "NFL Cowboys NO EVENT STREAMING", group: "NFL", language: "en", region: "US"),
            Channel(id: "foreign", sourceID: source, name: "NFL Cowboys", group: "NFL", language: "de", region: "DE")]
        let programs = [GuideProgram(id: "game", sourceID: source, guideID: "nbc", title: "Sunday Night Football", summary: "Dallas visits Green Bay. Cowboys at Packers.", start: now - 60, end: now + 3600)]
        let index = try CatalogQueryIndex(channels: channels, programs: programs)
        let audience = ChannelAudience(scope: .preferred, languages: ["en"], regions: ["US"], includeUnknownLanguage: true)
        let result = try index.sports(at: now, following: ["Dallas Cowboys"], followedOnly: true, audience: audience)
        #expect(result.live.map(\.channel.id) == ["scheduled"])
        #expect(result.live.first?.followedNames == ["Dallas Cowboys"])
        #expect(result.channelsWithoutListings.map(\.channel.id) == ["event"])
        let recommendations = try index.recommendations(at: now, preferences: .init(languages: [], regions: [], interests: [], following: ["Dallas Cowboys"], watched: []), audience: audience)
        #expect(recommendations.first?.reasons == ["Following: Dallas Cowboys"])
    }

    @Test func alternateEventFeedsPreserveExactEventSourceTimeAndLanguage() {
        let source = UUID()
        let channels = [Channel(id: "4k", sourceID: source, name: "NFL | 4k - SNF 8:20pm Cowboys at Packers"),
            Channel(id: "hd", sourceID: source, name: "NFL | 13 - SNF 8:20pm Cowboys at Packers"),
            Channel(id: "time", sourceID: source, name: "NFL | 14 - SNF 9:20pm Cowboys at Packers"),
            Channel(id: "language", sourceID: source, name: "NFL | 15 - SNF 8:20pm Cowboys at Packers", language: "es"),
            Channel(id: "other", sourceID: UUID(), name: "NFL | 13 - SNF 8:20pm Cowboys at Packers"),
            Channel(id: "generic", sourceID: source, name: "NFL | 15 - NO EVENT STREAMING")]
        let groups = PlaybackAlternatives.groups(channels)
        #expect(groups["4k"] == ["hd", "4k"])
        #expect(groups["hd"] == ["hd", "4k"])
        #expect(groups.count == 2)
    }
}
