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

    @Test func firstMarkWins() {
        let start = ContinuousClock.now
        var timeline = LaunchTimeline()
        timeline.mark(.processStart, at: start)
        timeline.mark(.firstInteractive, at: start + .milliseconds(100))
        timeline.mark(.firstInteractive, at: start + .milliseconds(900))
        #expect(timeline.milliseconds(to: .firstInteractive) == 100)
    }
}
