import XCTest
@testable import mySportly

@MainActor final class MetadataCoverageTests: XCTestCase {
    func testSavedGuideRecoveryAndHomeCleanup() async throws {
        let store = AppStore(); await store.load()
        try XCTSkipUnless(store.channels.count > 50_000, "Requires the saved device catalog")
        let directory = try XCTUnwrap(store.directory), index = try XCTUnwrap(store.queryIndex)
        let programs = store.catalog.programs, overrides = store.personal.snapshotValues()
        let audience = ChannelAudience(scope: .preferred, languages: ["en"], regions: ["US"])
        let date = Date.now
        let result = try await catalogWork {
            let baseline = try CatalogQueryIndex(channels: directory.lineup, programs: programs, overrides: overrides, metadata: directory.metadata)
            var request = ChannelBrowseRequest(); request.audience = audience; request.excludeInactive = true
            let home = try directory.browse(request)
            let recommendations = try index.recommendations(at: date, preferences: .init(languages: ["en"], regions: ["US"], interests: [], following: [], watched: []), audience: audience)
            return (try baseline.coverage(at: date, audience: audience), try index.coverage(at: date, audience: audience), home, recommendations)
        }
        print("[GuideRecovery] before=\(result.0.matched) after=\(result.1.matched) automatic=\(result.1.automatic) on_now=\(result.1.onNow) missing_id=\(result.1.missingID) unmatched_id=\(result.1.unmatchedID) home_channels=\(result.2.count) total_preferred=\(result.1.channels)")
        XCTAssertGreaterThan(result.1.matched, result.0.matched)
        XCTAssertGreaterThan(result.1.automatic, 0)
        XCTAssertTrue(result.2.allSatisfy { !ListingAvailability.isInactiveChannel($0.name) })
        XCTAssertTrue(result.3.allSatisfy { !ListingAvailability.isInactiveChannel($0.channel.name) })
        for channel in store.channels.filter({ store.guideMatches[$0.id] != nil && !store.personal.has(store.key($0, "guideID")) }).prefix(50) {
            XCTAssertFalse(store.programs(for: channel).isEmpty)
        }
    }
    func testSavedCatalogUsesLocalMetadataAndReportsGuideCoverage() async throws {
        let store = AppStore()
        let started = ContinuousClock.now
        await store.load()
        try XCTSkipUnless(store.channels.count > 50_000, "Requires the saved device catalog")
        let directory = try XCTUnwrap(store.directory), index = try XCTUnwrap(store.queryIndex)
        let audience = ChannelAudience(scope: .preferred, languages: ["en"], regions: ["US"])
        var request = ChannelBrowseRequest(); request.audience = audience; request.collapseVariants = true
        let input = request
        let result = try await catalogWork {
            let channels = try directory.browse(input)
            let withListings = try index.channelsWithListings(from: .now, to: .now + 6 * 3600)
            return (channels, try index.coverage(at: .now, audience: audience), directory.metadata.values.filter { !$0.region.isEmpty }.count, channels.filter { withListings.contains($0.id) }.count)
        }
        let coverage = result.1
        print("[MetadataCoverage] total=\(store.channels.count) raw_regions=\(store.catalog.channels.filter { !$0.region.isEmpty }.count) detected_regions=\(result.2) preferred=\(result.0.count) guide_matched=\(coverage.matched) on_now=\(coverage.onNow) missing_id=\(coverage.missingID) unmatched_id=\(coverage.unmatchedID) ended=\(coverage.noUpcoming) unknown_language=\(coverage.unknownLanguage) guide_visible=\(result.3) check_seconds=\(started.duration(to: .now))")
        XCTAssertGreaterThan(result.0.count, 0)
        XCTAssertLessThan(result.0.count, store.channels.count)
        XCTAssertGreaterThan(coverage.matched, 0)
        XCTAssertTrue(result.0.allSatisfy { directory.metadata[$0.id]?.region == "US" })
        XCTAssertEqual(Set(store.channels.map(\.id)), Set(store.catalog.channels.map(\.id)))
    }
}
