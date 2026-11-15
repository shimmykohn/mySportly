import Foundation
import Testing
@testable import SportlyCore

struct RefreshScheduleTests {
    let now = Date(timeIntervalSince1970: 2_000_000)
    @Test func guideRefreshCanBeDueWithoutReloadingPlaylist() {
        let schedule = RefreshSchedule()
        #expect(schedule.due(playlistSuccess: now - 8 * 3600, guideSuccess: now - 8 * 3600, playlistAttempt: nil, guideAttempt: nil, supportsGuide: true, at: now) == .guide)
        #expect(schedule.due(playlistSuccess: now - 25 * 3600, guideSuccess: now - 25 * 3600, playlistAttempt: nil, guideAttempt: nil, supportsGuide: true, at: now) == .playlist)
    }
    @Test func disabledSchedulesAndMissingGuidesDoNotLoop() {
        #expect(RefreshSchedule(playlist: .off, guide: .off).due(playlistSuccess: nil, guideSuccess: nil, playlistAttempt: nil, guideAttempt: nil, supportsGuide: true, at: now) == nil)
        #expect(RefreshSchedule().due(playlistSuccess: now, guideSuccess: nil, playlistAttempt: nil, guideAttempt: nil, supportsGuide: false, at: now) == nil)
        #expect(RefreshSchedule().due(playlistSuccess: now, guideSuccess: now, playlistAttempt: nil, guideAttempt: nil, supportsGuide: true, at: now) == nil)
    }
    @Test func failedAttemptBacksOffWithoutChangingSuccess() {
        let schedule = RefreshSchedule()
        #expect(schedule.due(playlistSuccess: nil, guideSuccess: nil, playlistAttempt: now - 60, guideAttempt: now - 60, supportsGuide: true, at: now) == nil)
        #expect(schedule.next(kind: .playlist, success: nil, attempt: now) == now + 3600)
    }
    @Test func guideOnlyCommitPreservesChannelsOtherSourcesAndPlaylistAge() throws {
        let source = UUID(), other = UUID()
        let channel = Channel(id: "one", sourceID: source, name: "One")
        let old = GuideProgram(id: "old", sourceID: source, guideID: "one", title: "Old", start: now, end: now + 100)
        let kept = GuideProgram(id: "other", sourceID: other, guideID: "other", title: "Other", start: now, end: now + 100)
        let fresh = GuideProgram(id: "fresh", sourceID: source, guideID: "one", title: "Fresh", start: now, end: now + 100)
        var snapshot = CatalogSnapshot()
        snapshot.replace(sourceID: source, channels: [channel], programs: [old], at: now - 86400)
        snapshot.replace(sourceID: other, channels: [], programs: [kept], at: now - 86400)
        snapshot.replaceGuide(sourceID: source, guide: TVGuide(channels: [], programs: [fresh, fresh, kept]), at: now)
        #expect(snapshot.channels == [channel])
        #expect(Set(snapshot.programs.map(\.id)) == ["fresh", "other"])
        #expect(snapshot.refreshed[source] == now - 86400)
        #expect(snapshot.guideRefreshed[source] == now)
        #expect(snapshot.guideRefreshed[other] == now - 86400)
        let oldCache = try JSONDecoder().decode(CatalogSnapshot.self, from: Data("{}".utf8))
        #expect(oldCache.guideURLs.isEmpty)
    }
    @Test func categoryBookmarksHaveStableIdentityAcrossCaseAndNoPathCollisions() throws {
        #expect(LibraryBookmark.category(["Sports", "Golf"]).id == LibraryBookmark.category(["SPORTS", "golf"]).id)
        #expect(LibraryBookmark.category(["AB", "C"]).id != LibraryBookmark.category(["A", "BC"]).id)
        let item = LibraryBookmark.category(["Sports", "Golf"])
        #expect(try JSONDecoder().decode(LibraryBookmark.self, from: JSONEncoder().encode(item)) == item)
    }
}
