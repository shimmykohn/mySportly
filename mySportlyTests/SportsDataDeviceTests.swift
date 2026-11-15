import AVFoundation
import UIKit
import XCTest
@testable import mySportly

final class SportsDataDeviceTests: XCTestCase {
    @MainActor func testFollowAddAndOneTimeMigration() async throws {
        let store = AppStore(inMemory: true)
        let nba = SportsLibraryItem(name: "NBA", kind: .league)
        let knicks = SportsLibraryItem(name: "New York Knicks", kind: .team)
        let nets = SportsLibraryItem(name: "Brooklyn Nets", kind: .team)
        try store.personal.set("preferences.teams", [nets.name])
        store.runFollowMigration()
        XCTAssertTrue(store.isFollowing(nets), "Legacy saves become follows")
        store.follow(nba)
        XCTAssertEqual(store.addedLeagues, [nba])
        XCTAssertFalse(store.isFollowing(knicks), "Adding a league does not follow its teams")
        store.follow(knicks)
        try store.personal.set("sports.notify.\(knicks.id)", true)
        store.unfollow(knicks)
        XCTAssertFalse(store.isFollowing(knicks))
        XCTAssertFalse(store.notifiesGameStart(knicks), "Unfollowing turns off game alerts")
        store.unfollow(nba)
        XCTAssertTrue(store.isFollowing(nets), "Removing a league keeps followed teams")
        try store.personal.set("preferences.teams", [knicks.name])
        store.runFollowMigration()
        XCTAssertFalse(store.isFollowing(knicks), "The migration runs once")
        XCTAssertNil(store.personal.storageError)
    }
    func testBundledDirectoryAndLogoSurviveOfflineCacheReload() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sports-reference", withExtension: "json"))
        let reference = try await SportsRepository().load(referenceURL: url)
        XCTAssertGreaterThanOrEqual(reference.teams.count, 173)
        XCTAssertTrue(reference.games.isEmpty, "The reference must not ship historical games as current schedules")
        let knicks = try XCTUnwrap(reference.catalog.teams.first { $0.libraryItem.name == "New York Knicks" })
        let logo = try XCTUnwrap(knicks.logo)
        let directory = URL.temporaryDirectory.appending(path: "sports-logo-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = await SportsLogoCache(directory: directory).image(url: logo, pixels: 72)
        XCTAssertNotNil(first, "The real API-SPORTS logo must decode on the device")
        XCTAssertLessThanOrEqual(first?.width ?? 0, 72)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineSportsURLProtocol.self]
        let offline = URLSession(configuration: configuration)
        defer { offline.invalidateAndCancel() }
        let second = await SportsLogoCache(directory: directory, session: offline).image(url: logo, pixels: 56)
        XCTAssertNotNil(second, "A new cache instance must reuse the disk file with networking unavailable")
        XCTAssertLessThanOrEqual(second?.width ?? 0, 56)
        print("SPORTS_LOGOS_VERIFIED teams=\(reference.teams.count) online_decode=true offline_disk_reload=true")
    }

    @MainActor func testSavedGuideGroupingLeavesMainThreadResponsive() async throws {
        let store = AppStore()
        await store.load(); await store.sportsData.load()
        try XCTSkipIf(store.channels.isEmpty, "Requires the provider catalog already saved on the device")
        await store.waitForSportsMatching()
        let clock = ContinuousClock()
        var longestGap = Duration.zero
        let heartbeat = Task { @MainActor in
            var previous = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                let now = clock.now; longestGap = max(longestGap, previous.duration(to: now)); previous = now
            }
        }
        await Task.yield()
        let start = clock.now
        store.matchSportsGames()
        await store.waitForSportsMatching()
        let elapsed = start.duration(to: clock.now)
        heartbeat.cancel()
        XCTAssertLessThan(longestGap, .milliseconds(250))
        XCTAssertLessThan(elapsed, .seconds(10))
        let links = store.gameLinks.values.flatMap { $0 }
        for link in links {
            XCTAssertNotNil(store.channelIndex[link.channelID])
            XCTAssertNotNil(store.sportsData.index.games[link.gameID])
            XCTAssertGreaterThan(link.validUntil, link.validFrom)
        }
        print("SPORTS_GUIDE_VERIFIED channels=\(store.channels.count) games=\(store.sportsData.index.games.count) feeds=\(links.count) elapsed=\(elapsed) main_thread_gap=\(longestGap)")
        let directory = try XCTUnwrap(store.directory), audience = store.audience
        let groupStart = clock.now
        let grouped = try await catalogWork {
            var request = ChannelBrowseRequest(); request.audience = audience; request.collapseVariants = true; request.excludeInactive = true
            return try directory.groupedSports(in: directory.browse(request))
        }
        XCTAssertLessThan(groupStart.duration(to: clock.now), .seconds(1))
        print("SPORTS_GROUPS_VERIFIED groups=\(grouped.groups.count) grouped_feeds=\(grouped.groups.reduce(0) { $0 + $1.count }) golf=\(grouped.groups.first { $0.sport == .golf }?.count ?? 0) tennis=\(grouped.groups.first { $0.sport == .tennis }?.count ?? 0) elapsed=\(groupStart.duration(to: clock.now))")
    }

    @MainActor func testMatchedProviderGameRendersVideo() async throws {
        let marker = URL.temporaryDirectory.appending(path: "mySportly-sports-playback.enabled")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path), "Requires the one-use sports playback marker")
        try FileManager.default.removeItem(at: marker)
        do {
            let snapshot = try await CatalogCache().load()
            let reference = try await SportsRepository().load(referenceURL: Bundle.main.url(forResource: "sports-reference", withExtension: "json"))
            let now = Date.now
            let result = try await catalogWork {
                let prepared = try PreparedCatalog(channels: snapshot.channels, programs: snapshot.programs,
                    activeSources: Set(snapshot.channels.map(\.sourceID)), overrides: [:], guideChannels: snapshot.guideChannels)
                return (try prepared.query.guideGames(reference: reference, refreshed: snapshot.refreshed, at: now), prepared.channelsByID, prepared.directory.metadata)
            }
            let liveGames = result.0.index.orderedGames.filter { $0.canWatch(at: now) }
            let choices = liveGames.flatMap { game in
                (result.0.links[game.id] ?? []).filter { $0.isValid(at: now) }.compactMap { link -> (SportsGame, Channel)? in
                    guard let channel = result.1[link.channelID], let metadata = result.2[link.channelID],
                          metadata.region == "US", (metadata.language == "en" || metadata.language.isEmpty) else { return nil }
                    return (game, channel)
                }
            }
            print("SPORTS_PLAYBACK_CANDIDATES live_games=\(liveGames.count) preferred_feeds=\(choices.count)")
            let selected = try XCTUnwrap(choices.first, "No current US/English game has a matching provider feed")
            let channel = selected.1, secrets = try XCTUnwrap(KeychainStore.credentials(channel.sourceID))
            let provider = ProviderClient()
            let data = try await HTTPClient().data(try provider.endpoint(secrets, file: "player_api.php"), limit: 1_000_000)
            let auth = try XCTUnwrap((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["user_info"] as? [String: Any])
            func number(_ field: String) -> Int { Int(auth[field] as? String ?? "") ?? (auth[field] as? NSNumber)?.intValue ?? 0 }
            try XCTSkipIf(number("active_cons") >= max(1, number("max_connections")), "Provider connection is occupied; no stream opened")
            let player = PlaybackController(), layer = AVPlayerLayer()
            layer.player = player.player; layer.frame = CGRect(x: 0, y: 120, width: 320, height: 180)
            let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            try XCTUnwrap(window).layer.addSublayer(layer)
            defer { player.stop(); layer.player = nil; layer.removeFromSuperlayer() }
            let alternatives = try choices.filter { $0.0.id == selected.0.id && $0.1.sourceID == channel.sourceID && $0.1.id != channel.id }.prefix(2).map {
                PlaybackAlternative(channel: $0.1, url: try provider.playbackURL($0.1, secrets: secrets))
            }
            let started = ContinuousClock.now
            player.play(channel, url: try provider.playbackURL(channel, secrets: secrets), title: nil, preferredLanguage: "en", alternates: alternatives)
            let deadline = Date.now + 45
            while (!layer.isReadyForDisplay || !player.isPlaying || player.player.currentTime().seconds < 2) && Date.now < deadline && player.errorMessage == nil {
                try await Task.sleep(for: .milliseconds(200))
            }
            XCTAssertTrue(layer.isReadyForDisplay, "A matched provider feed must render video")
            XCTAssertTrue(player.isPlaying)
            print("SPORTS_PLAYBACK_VERIFIED video=\(layer.isReadyForDisplay) elapsed=\(started.duration(to: .now)) alternatives=\(alternatives.count)")
        } catch let skip as XCTSkip { throw skip }
        catch { let safe = error as NSError; XCTFail("Matched playback check failed: domain=\(safe.domain) code=\(safe.code)") }
    }
}

private final class OfflineSportsURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() { }
}
