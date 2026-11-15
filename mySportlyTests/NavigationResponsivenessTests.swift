import Foundation
import Testing
@testable import mySportly

/// Runs against the catalog already saved on this physical device. No import,
/// credentials, playback, or personal-setting mutations are needed.
@MainActor @Suite(.serialized) struct NavigationResponsivenessTests {
    @Test func savedCatalogMainThreadWork() async throws {
        let store = AppStore()
        await store.load()
        guard store.channels.count >= 50_000 else { return }
        let clock = ContinuousClock()
        var longestMainThreadGap = Duration.zero
        let heartbeat = Task { @MainActor in
            var previous = clock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                let now = clock.now
                longestMainThreadGap = max(longestMainThreadGap, previous.duration(to: now))
                previous = now
            }
        }
        await Task.yield()
        let rebuildStart = clock.now
        store.rebuild(force: true)
        let rebuild = rebuildStart.duration(to: clock.now)
        await store.waitForCatalog()
        let guideStart = clock.now
        let directory = try #require(store.directory)
        var request = ChannelBrowseRequest(); request.ranked = true; request.collapseVariants = true
        let rankedRequest = request, preferences = store.recommendationPreferences
        let guide = try await catalogWork { try directory.browse(rankedRequest, preferences: preferences) }
        let guideTime = guideStart.duration(to: clock.now)
        let organizerStart = clock.now
        store.prepareOrganization()
        let organizerTime = organizerStart.duration(to: clock.now)
        await store.waitForOrganization()
        let index = try #require(store.queryIndex), audience = store.audience, now = store.clock
        let followingStart = clock.now
        let followed = try await catalogWork { try index.sports(at: now, following: ["Dallas Cowboys", "New York Knicks"], followedOnly: true, audience: audience) }
        let followingTime = followingStart.duration(to: clock.now)
        print("FOLLOWING_VERIFIED live=\(followed.live.count) upcoming=\(followed.upcoming.count) channels_without_listings=\(followed.channelsWithoutListings.count) query_time=\(followingTime)")
        #expect(followingTime < .seconds(5))
        heartbeat.cancel()
        print("NAVIGATION_VERIFIED channels=\(store.channels.count) rebuild_enqueue=\(rebuild) guide_background=\(guideTime) organizer_enqueue=\(organizerTime) main_thread_gap=\(longestMainThreadGap)")
        #expect(guide.count == store.lineup.count)
        #expect(rebuild < .milliseconds(100))
        #expect(organizerTime < .milliseconds(100))
        #expect(longestMainThreadGap < .milliseconds(250), "Large-catalog preparation must leave the main actor responsive")
    }
}
