import Foundation
import Testing
@testable import mySportly

@MainActor @Suite(.serialized) struct GroupOrganizationDeviceTests {
    @Test func groupCorrectionPersistsThroughRebuild() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        let group = try #require(store.directory?.nameGroups.groups.first)
        store.setGroupPath(group, path: ["Learning", "Space"])
        await store.waitForCatalog()
        #expect(store.directory?.nameGroups.paths[group.id] == ["Learning", "Space"])
        #expect(store.categories.contains("Learning"))
    }
}
