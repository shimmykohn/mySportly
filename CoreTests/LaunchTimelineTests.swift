import Foundation
import Testing
@testable import SportlyCore

struct LaunchTimelineTests {
    @Test func marksAreRelativeToProcessStart() {
        let start = ContinuousClock.now
        var timeline = LaunchTimeline()
        timeline.mark(.processStart, at: start)
        timeline.mark(.firstInteractive, at: start + .milliseconds(850))
        #expect(timeline.milliseconds(to: .firstInteractive) == 850)
    }

    @Test func unmarkedPhaseIsNil() {
        var timeline = LaunchTimeline()
        timeline.mark(.processStart)
        #expect(timeline.milliseconds(to: .catalogPrepared) == nil)
    }

    @Test func summaryListsMarkedPhasesInOrder() {
        let start = ContinuousClock.now
        var timeline = LaunchTimeline()
        timeline.mark(.firstInteractive, at: start + .milliseconds(850))
        timeline.mark(.processStart, at: start)
        #expect(timeline.summary == "processStart=0 firstInteractive=850")
    }

    @Test func processStartDateIsThisProcessInThePast() throws {
        let started = try #require(LaunchTimeline.processStartDate())
        #expect(started <= Date())
        #expect(Date().timeIntervalSince(started) < 24 * 3600)
    }

    @Test func wallClockDateConvertsToInstantBeforeNow() {
        let now = ContinuousClock.now, wallNow = Date()
        let instant = LaunchTimeline.instant(for: wallNow - 2.5, now: now, wallNow: wallNow)
        #expect(now - instant == .milliseconds(2500))
    }

    @Test func firstMarkWins() {
        let start = ContinuousClock.now
        var timeline = LaunchTimeline()
        timeline.mark(.processStart, at: start)
        timeline.mark(.firstInteractive, at: start + .milliseconds(100))
        timeline.mark(.firstInteractive, at: start + .milliseconds(900))
        #expect(timeline.milliseconds(to: .firstInteractive) == 100)
    }
}
