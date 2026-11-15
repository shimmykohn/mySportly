import Foundation
import Testing
@testable import SportlyCore

@Suite struct GuideMappingTests {
    let source = UUID()
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func resolve(_ channels: [Channel], ids: [String], definitions: [GuideChannel] = []) throws -> GuideMappingResolver {
        let directory = try ChannelDirectory(channels: channels)
        return try GuideMappingResolver(channels: channels, guideIDs: [source: ids], guideChannels: definitions, metadata: directory.metadata)
    }
    func channel(_ id: String, _ name: String, guideID: String = "", region: String = "US") -> Channel {
        Channel(id: id, sourceID: source, name: name, guideID: guideID, region: region)
    }
    @Test func exactNamesQualityAndCountryMatchWithoutLosingEditions() throws {
        let channels = [channel("hd", "US: ESPN HD"), channel("raw", "ATT: ESPN ᴿᴬᵂ ⁶⁰ᶠᵖˢ"),
            channel("second", "US: ESPN2 HD"), channel("west", "US: ESPN West HD"),
            channel("delay", "US: ESPN +1 HD"), channel("gb", "UK: ESPN HD", region: "GB"),
            channel("regionless", "ESPN HD", region: ""), channel("amp", "US: A&E HD")]
        let result = try resolve(channels, ids: ["ESPN.us", "AandE.us"])
        #expect(Set(result.matches.keys) == ["hd", "raw", "amp"])
        #expect(result.matches["amp"]?.guideID == "AandE.us")
    }
    @Test func siblingMappingsAreSourceScopedAndAmbiguityIsRejected() throws {
        var other = channel("other", "Unique HD", guideID: "foreign"); other.sourceID = UUID()
        let channels = [channel("mapped", "US: News East HD", guideID: "opaque-1"), channel("sd", "US: News East SD"),
            channel("a", "US: Sports HD", guideID: "one"), channel("b", "US: Sports SD", guideID: "two"), channel("c", "US: Sports FHD"),
            other, channel("local", "Unique SD")]
        let result = try resolve(channels, ids: ["opaque-1", "one", "two"])
        #expect(result.matches["sd"]?.guideID == "opaque-1")
        #expect(result.matches["c"] == nil)
        #expect(result.ambiguous == ["c"])
        #expect(result.matches["local"] == nil)
        #expect(result.matches["mapped"] == nil)
    }
    @Test func localCallsignNeverAssignsNewsOnlyOrShiftedOrSubchannelFeeds() throws {
        let channels = [channel("local", "US: ABC NEW YORK (WABC) HD"), channel("fast", "PRIME: ABC NEW YORK NEWS (WABC) RAW"),
            channel("news", "US: ABC NEWS (WABC) HD"), channel("sub", "US: ABC (WABC.2) HD"),
            channel("west", "US: ABC (WABC) WEST HD"), channel("plus", "US: ABC (WABC) +1 HD")]
        let result = try resolve(channels, ids: ["WABC.us"])
        #expect(Set(result.matches.keys) == ["local"])
        let branded = try resolve([channel("brand", "US: ABC HD")], ids: ["WABC.us"], definitions: [GuideChannel(sourceID: source, guideID: "WABC.us", names: ["ABC"])])
        #expect(branded.matches.isEmpty)
    }
    @Test func languageKnownToConflictDoesNotUseTheGenericIDAlias() throws {
        var anchor = channel("anchor", "US: ESPN HD", guideID: "ESPN.us"); anchor.language = "en"
        var spanish = channel("spanish", "US: ESPN SD"); spanish.language = "es"
        #expect(try resolve([anchor, spanish], ids: ["ESPN.us"]).matches.isEmpty)
    }
    @Test func manualBlankAndWrongProviderIDsRemainExplicitChoices() throws {
        let channels = [channel("auto", "US: ESPN HD"), channel("blank", "US: ESPN SD"), channel("manual", "US: ESPN FHD"), channel("provider", "US: Different Network UHD", guideID: "other")]
        let programs = ["ESPN.us", "other"].map { GuideProgram(id: $0, sourceID: source, guideID: $0, title: "Live Sport", start: date, end: date + 3600) }
        let overrides = ["channel.blank.guideID": try JSONEncoder().encode(""), "channel.manual.guideID": try JSONEncoder().encode("other")]
        let prepared = try PreparedCatalog(channels: channels, programs: programs, activeSources: [source], overrides: overrides)
        let found = try prepared.query.search(.init(keywords: [], start: date, end: date + 1))
        #expect(found.first { $0.id == "auto" }?.program?.guideID == "ESPN.us")
        #expect(found.first { $0.id == "blank" }?.program == nil)
        #expect(found.first { $0.id == "manual" }?.program?.guideID == "other")
        #expect(found.first { $0.id == "provider" }?.program?.guideID == "other")
        #expect(try prepared.query.coverage(at: date).automatic == 1)
    }
    @Test func xmlChannelNamesAreRetainedAndOldCachesStillDecode() throws {
        let xml = "<tv><channel id=\"opaque.us\"><display-name lang=\"en\">A &amp; B</display-name><display-name>AB Television</display-name></channel><programme channel=\"opaque.us\" start=\"20261018120000 +0000\" stop=\"20261018130000 +0000\"><title>Show</title></programme></tv>"
        let guide = try XMLTVParser.document(Data(xml.utf8), sourceID: source)
        #expect(guide.channels.first?.names == ["A & B", "AB Television"])
        #expect(guide.programs.count == 1)
        let result = try resolve([channel("alias", "US: AB Television HD")], ids: ["opaque.us"], definitions: guide.channels)
        #expect(result.matches["alias"]?.guideID == "opaque.us")
        var cache = try JSONDecoder().decode(CatalogSnapshot.self, from: Data("{}".utf8))
        cache.replace(sourceID: source, channels: [], programs: guide.programs, guideChannels: guide.channels)
        cache.replace(sourceID: source, channels: [], programs: nil)
        #expect(cache.guideChannels == guide.channels)
        #expect(try JSONDecoder().decode(CatalogSnapshot.self, from: JSONEncoder().encode(cache)).guideChannels == guide.channels)
        cache.replace(sourceID: source, channels: [], programs: [])
        #expect(cache.guideChannels.isEmpty)
    }
    @Test func idleEventSlotsStaySearchableWithoutBecomingSuggestionsOrMappings() throws {
        var idle = channel("idle", "- NO EVENT STREAMING - | US: ESPN PPV 7", guideID: "slot")
        idle.group = "Sports"
        let regular = channel("regular", "US: ESPN HD", guideID: "ESPN.us")
        let placeholder = channel("placeholder", "Sports 2", guideID: "empty")
        let channels = [idle, regular, placeholder]
        let programs = [GuideProgram(id: "slot", sourceID: source, guideID: "slot", title: "Football", start: date, end: date + 3600),
            GuideProgram(id: "real", sourceID: source, guideID: "ESPN.us", title: "Tennis", start: date, end: date + 3600),
            GuideProgram(id: "empty", sourceID: source, guideID: "empty", title: "No Event", start: date, end: date + 3600)]
        let prepared = try PreparedCatalog(channels: channels, programs: programs, activeSources: [source], overrides: [:])
        var request = ChannelBrowseRequest(); request.excludeInactive = true
        #expect(try prepared.directory.browse(request).map(\.id).contains("idle") == false)
        #expect(try prepared.directory.browse(.init()).count == 3)
        #expect(try prepared.query.search(.init(keywords: ["no event"], start: date, end: date + 1)).count == 2)
        #expect(try prepared.query.recommendations(at: date, preferences: .init(languages: [], regions: ["US"], interests: [], following: [], watched: [])).map(\.id) == ["regular"])
        #expect(try prepared.query.sports(at: date).live.map(\.channel.id) == ["regular"])
        idle.guideID = ""
        #expect(try resolve([idle], ids: ["ESPN.us"]).matches.isEmpty)
        #expect(!ListingAvailability.isPlaceholderProgram("The Main Event"))
    }
}
