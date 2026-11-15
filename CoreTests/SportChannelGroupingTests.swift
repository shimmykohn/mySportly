import Foundation
import Testing
@testable import SportlyCore

struct SportChannelGroupingTests {
    @Test func providerSubgroupsDiscoverNewLabelsWithoutALeagueList() throws {
        let source = UUID()
        var channels = [Channel]()
        for prefix in ["NFL", "NCAAF", "NCAAAF", "NEWLEAGUE"] {
            for number in 1...2 {
                channels.append(Channel(id: "\(prefix).\(number)", sourceID: source,
                    name: "US | \(prefix) \(number) HD", group: "US | American Football"))
            }
        }
        channels.append(Channel(id: "other", sourceID: source, name: "American Football 01", group: "US"))
        let directory = try ChannelDirectory(channels: channels)
        var request = ChannelBrowseRequest(); request.sport = .football
        let visible = try directory.browse(request)
        let grouped = try directory.groupedProviderLabels(in: visible)
        #expect(Set(grouped.groups.map(\.label)) == ["NFL", "NCAAF", "NCAAAF", "NEWLEAGUE"])
        #expect(grouped.groups.allSatisfy { $0.count == 2 })
        #expect(grouped.remaining.map(\.id) == ["other"])
        request.providerGroup = "NEWLEAGUE"
        #expect(try directory.browse(request).map(\.id) == ["NEWLEAGUE.1", "NEWLEAGUE.2"])
        #expect(try directory.groupedProviderLabels(in: directory.browse(request)).groups.isEmpty)
    }

    @Test func interestedCategoriesExpandFirstAndOtherCategoriesStayCompact() throws {
        let source = UUID()
        let channels = [Channel(id: "g1", sourceID: source, name: "Golf 01"),
                        Channel(id: "g2", sourceID: source, name: "Golf 02"),
                        Channel(id: "network", sourceID: source, name: "ESPN"),
                        Channel(id: "news", sourceID: source, name: "News 1"),
                        Channel(id: "movie", sourceID: source, name: "Movies 1")]
        let directory = try ChannelDirectory(channels: channels)
        let groups = try directory.homeCategories(in: directory.channels, interests: ["Sports", "News"])
        #expect(groups.map(\.category) == ["News", "Sports", "Movies"])
        #expect(groups[1].sports.map(\.sport) == [.golf])
        #expect(groups[1].preview.map(\.id) == ["network"])
        #expect(groups[2].preview.isEmpty && groups[2].sports.isEmpty)
        let removed = try directory.homeCategories(in: directory.channels, interests: ["News"])
        #expect(removed.last?.category == "Sports")
        #expect(removed.last?.preview.isEmpty == true && removed.last?.sports.isEmpty == true)
    }

    @Test func numberedFeedsAndLeagueTagsResolveWithoutAGuide() {
        var resolver = ChannelMetadataResolver()
        let source = UUID()
        for (name, sport) in [(":Golf 07", ChannelSport.golf), (":Tennis 04", .tennis), ("US | PGA 10 HD", .golf), ("ATP 2", .tennis), ("NFL 4K", .football), ("F1 01", .motorsport)] {
            let details = resolver.resolve(Channel(id: name, sourceID: source, name: name, group: "US Entertainment"))
            #expect(details.category == "Sports")
            #expect(details.sport == sport)
        }
        let grouped = resolver.resolve(Channel(id: "grouped", sourceID: source, name: "Court 04", group: "US | WTA Tennis"))
        #expect(grouped.sport == .tennis)
        let specific = resolver.resolve(Channel(id: "specific", sourceID: source, name: "Golf 01", group: "Golf & Tennis"))
        #expect(specific.sport == .golf)
    }

    @Test func ambiguousNetworksAndSubstringsStayUngrouped() {
        var resolver = ChannelMetadataResolver()
        for name in ["ESPN HD", "Football 01", "Golf & Tennis", "Golfing holidays", "NHLights", "NBA / NFL"] {
            #expect(resolver.resolve(Channel(id: name, sourceID: UUID(), name: name)).sport == nil)
        }
    }

    @Test func groupsPreserveStreamsAndRespectAudienceAndManualCorrections() throws {
        let source = UUID(), encoder = JSONEncoder()
        let channels = [
            Channel(id: "g1", sourceID: source, name: ":Golf 07", group: "US"),
            Channel(id: "g2", sourceID: source, name: ":Golf 08", group: "US"),
            Channel(id: "t1", sourceID: source, name: ":Tennis 04", group: "US"),
            Channel(id: "t2", sourceID: source, name: ":Tennis 05", group: "US"),
            Channel(id: "hidden", sourceID: source, name: ":Tennis 06", group: "US"),
            Channel(id: "gb", sourceID: source, name: "UK | Golf 09"),
            Channel(id: "corrected", sourceID: source, name: "US | Golf 09"),
            Channel(id: "single", sourceID: source, name: "US | NBA"),
            Channel(id: "news", sourceID: source, name: "US | News")
        ]
        let directory = try ChannelDirectory(channels: channels, overrides: [
            "channel.hidden.hidden": try encoder.encode(true), "channel.corrected.category": try encoder.encode("Music")
        ])
        var request = ChannelBrowseRequest()
        request.audience = ChannelAudience(scope: .preferred, languages: ["en"], regions: ["US"])
        let visible = try directory.browse(request)
        let grouped = try directory.groupedSports(in: visible)
        #expect(grouped.groups.map(\.sport) == [.golf, .tennis])
        #expect(grouped.groups.map(\.count) == [2, 2])
        #expect(Set(grouped.remaining.map(\.id)) == ["news", "single", "corrected"])
        #expect(grouped.groups.reduce(0) { $0 + $1.count } + grouped.remaining.count == visible.count)
        request.sport = .tennis
        #expect(try directory.browse(request).map(\.id) == ["t1", "t2"])
        request.query = "05"
        #expect(try directory.browse(request).map(\.id) == ["t2"])
        request.sport = nil; request.query = ""; request.sportsOnly = true
        #expect(try directory.browse(request).count == 5)
        #expect(channels[0].name == ":Golf 07")
    }
}
