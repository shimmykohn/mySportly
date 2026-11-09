import Foundation
import Testing
@testable import mySportly

@MainActor @Suite(.serialized) struct LibraryAndRouteTests {
    @Test func followsAndFavoritesAreIndependent() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        let league = SportsLibraryItem(name: "NFL", kind: .league), team = SportsLibraryItem(name: "Dallas Cowboys", kind: .team)
        store.follow(league)
        #expect(store.addedLeagues == [league])
        #expect(!store.isFollowing(team), "Adding a league does not follow its teams")
        store.follow(team); store.unfollow(league)
        #expect(store.isFollowing(team))
        #expect(store.addedLeagues.isEmpty)
        let channel = try #require(store.channels.first)
        store.toggle(channel, "favorite"); await store.waitForCatalog()
        #expect(store.favorites.contains { $0.id == channel.id })
        store.toggle(channel, "favorite"); await store.waitForCatalog()
        #expect(!store.favorites.contains { $0.id == channel.id })
    }
    @Test func linksRouteToTabsAndDoNotStartAI() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        store.route(AppRouteInbox.url("search", name: "query", value: "News & Sports / today"))
        #expect(store.selectedTab == .search)
        #expect(store.searchRequest == "News & Sports / today")
        #expect(!store.isOrganizing)
        store.route(URL(string: "mysportly://guide")!)
        #expect(store.selectedTab == .guide)
        store.route(AppRouteInbox.url("library", name: "id", value: "removed"))
        #expect(store.selectedTab == .guide, "Removed routes are ignored")
        #expect(store.notice == nil)
    }
}
