import Foundation
import Testing
@testable import SportlyCore

@Suite struct StateTransitionTests {
    @Test func aFailedGuideRefreshDoesNotAdvanceGuideFreshness() {
        let source = UUID(); let old = Date(timeIntervalSince1970: 1000); let now = old.addingTimeInterval(172800)
        var snapshot = CatalogSnapshot()
        snapshot.replace(sourceID: source, channels: [], programs: [], at: old)
        snapshot.replace(sourceID: source, channels: [], programs: nil, at: now)
        #expect(snapshot.guideRefreshed[source] == old)
        #expect(snapshot.refreshed[source] == now)
    }
    @Test func manualConfirmationOfSameValueSurvivesUndo() {
        let key = "channel.one.category", old = Data("News".utf8), proposed = Data("Sports".utf8)
        let undo = UndoChange(key: key, before: old, applied: proposed, appliedMutationID: "ai-apply")
        let current = [key: LedgerValue(payload: proposed, mutationID: "manual-confirmation", modifiedAt: .now)]
        #expect(PersonalLedger.undo([undo], current: current).isEmpty)
    }
    @Test func untouchedAIChangeCanBeUndoneIncludingAbsentFields() {
        let key = "channel.one.language", proposed = Data("en".utf8)
        let undo = UndoChange(key: key, before: nil, applied: proposed, appliedMutationID: "ai-apply")
        let current = [key: LedgerValue(payload: proposed, mutationID: "ai-apply", modifiedAt: .now)]
        let changes = PersonalLedger.undo([undo], current: current)
        #expect(changes.keys.contains(key))
        if let restored = changes[key] { #expect(restored == nil) }
    }
    @Test func tombstonesAndTieBreaksConvergeRegardlessOfArrivalOrder() {
        let date = Date(timeIntervalSince1970: 1000)
        let rows = [LedgerRecord(key: "favorite", value: LedgerValue(payload: Data([1]), mutationID: "a", modifiedAt: date)), LedgerRecord(key: "favorite", value: LedgerValue(payload: nil, mutationID: "b", modifiedAt: date))]
        let forward = PersonalLedger.resolve(rows), reverse = PersonalLedger.resolve(rows.reversed())
        #expect(forward == reverse)
        #expect(forward["favorite"]?.payload == nil)
        #expect(forward["favorite"]?.mutationID == "b")
    }
    @Test func sourceRefreshCannotOverwriteNewerRemoval() {
        #expect(ImportPolicy.canCommit(expectedVersion: "source-original", currentVersion: "source-removed") == false)
        #expect(ImportPolicy.canCommit(expectedVersion: "source-original", currentVersion: "source-original"))
    }
    @Test func cloudBatchStopsAfterConsentRevocation() async throws {
        let state = BatchTestState()
        try await OrganizationBatchRunner.run([1, 2, 3], allowed: { await state.allowed }, evaluate: { value in await state.send(value) })
        #expect(await state.sent == [1])
    }
}
private actor BatchTestState {
    var allowed = true
    var sent: [Int] = []
    func send(_ value: Int) { sent.append(value); allowed = false }
}
