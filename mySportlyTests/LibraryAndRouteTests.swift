import Foundation
import Testing
@testable import mySportly

@MainActor @Suite(.serialized) struct LibraryAndRouteTests {
    @Test func savesAreIndependentAndFavoritesKeepTheItemSaved() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        let league = SportsLibraryItem(name: "NFL", kind: .league), team = SportsLibraryItem(name: "Cowboys", kind: .team)
        store.saveSportsItem(league)
        #expect(store.sportsLibrary == [league])
        #expect(!store.hasSportsItem(team))
        store.saveSportsItem(team); store.setSportsFavorite(team, true)
        store.removeSportsItem(league)
        #expect(store.hasSportsItem(team)); #expect(store.isSportsFavorite(team))
        let channel = try #require(store.channels.first)
        store.toggle(channel, "favorite"); await store.waitForCatalog()
        store.toggle(channel, "favorite"); await store.waitForCatalog()
        #expect(!store.flag(channel, "favorite"))
        #expect(store.hasLibraryItem(store.bookmark(channel)))
        let category = LibraryBookmark.category(["Sports", "Golf"])
        store.saveLibraryItem(category); store.setLibraryFavorite(category, true)
        store.personal.reload(); store.rebuild(force: true); await store.waitForCatalog()
        #expect(store.savedLibraryItems.contains(category))
        #expect(store.isLibraryFavorite(category))
        store.removeLibraryItem(category)
        #expect(!store.hasLibraryItem(category)); #expect(!store.isLibraryFavorite(category))
    }
    @Test func linksRouteToTabsAndDoNotStartAI() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        store.route(AppRouteInbox.url("search", name: "query", value: "News & Sports / today"))
        #expect(store.selectedTab == .search)
        #expect(store.searchRequest == "News & Sports / today")
        #expect(!store.organization.isRunning)
        store.route(URL(string: "mysportly://guide")!)
        #expect(store.selectedTab == .guide)
        store.route(AppRouteInbox.url("library", name: "id", value: "removed"))
        #expect(store.selectedTab == .guide, "Removed routes are ignored")
        #expect(store.notice == nil)
    }
}
