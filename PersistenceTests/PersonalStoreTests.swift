import Foundation
import Testing
import SportlyCore
@testable import SportlyPersistence

@MainActor @Suite struct PersonalStoreTests {
    @Test func unchangedReloadDoesNotInvalidateTheLineup() throws {
        let store = PersonalStore(inMemory: true)
        let emptyRevision = store.revision
        #expect(!store.reload())
        #expect(store.revision == emptyRevision)
        try store.set("favorite.one", true)
        let savedRevision = store.revision
        #expect(savedRevision > emptyRevision)
        #expect(!store.reload())
        #expect(store.revision == savedRevision)
        #expect(store.value("favorite.one", default: false))
    }

    @Test func committedFieldsAndTombstonesSurviveReload() throws {
        let store = PersonalStore(inMemory: true)
        try #require(store.storageError == nil)
        try store.set("favorite.one", true)
        try store.set("category.one", "News")
        store.reload()
        #expect(store.value("favorite.one", default: false))
        #expect(store.value("category.one", default: "") == "News")
        let savedVersion = store.version("favorite.one")
        try store.remove("favorite.one")
        store.reload()
        #expect(!store.has("favorite.one"))
        #expect(store.version("favorite.one") != savedVersion)
        #expect(store.ledger["favorite.one"]?.payload == nil)
    }

    @Test func manualConfirmationGetsANewVersionEvenWhenPayloadMatches() throws {
        let store = PersonalStore(inMemory: true)
        let payload = try JSONEncoder().encode("Sports")
        try store.write(["category.one": payload], mutationID: "ai-apply")
        try store.set("category.one", "Sports")
        store.reload()
        #expect(store.raw("category.one") == payload)
        #expect(store.version("category.one") != "ai-apply")
    }

    @Test func optionalSyncChoiceIsLocalAndTakesEffectOnNextOpen() {
        let suite = "mySportly.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = PersonalStore(inMemory: true, defaults: defaults)
        first.requestCloudSync(false)
        #expect(first.syncChangeNeedsRelaunch)
        let reopened = PersonalStore(inMemory: true, defaults: defaults)
        #expect(!reopened.cloudRequested)
        #expect(!reopened.syncChangeNeedsRelaunch)
        #expect(!reopened.cloudConfigured)
    }
}
