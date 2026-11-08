import Foundation
import Testing
@testable import SportlyCore

struct SportsLibraryMembershipTests {
    @Test func arbitraryDirectoryLeagueIncludesTeamsWithoutFavoritingOrDuplicatingThem() throws {
        let index = try SportsDataIndex(SportsCatalog(leagues: [.init(id: "l", name: "Example League")], teams: [
            .init(id: "a", name: "North Club", leagueID: "l"), .init(id: "b", name: "South Club", leagueID: "l")]))
        let league = SportsLibraryItem(name: "Example League", kind: .league)
        let team = SportsLibraryItem(name: "North Club", kind: .team)
        let membership = SportsLibraryMembership(saved: [league, team, team], choices: index.choices)
        #expect(membership.items.count == 3)
        #expect(membership.directItems.count == 2)
        #expect(membership.leagueIncluding(team) == league)
        #expect(membership.following == [league])
        #expect(index.teams(in: league).map(\.name) == ["North Club", "South Club"])
        let removed = SportsLibraryMembership(saved: [team], choices: index.choices)
        #expect(removed.items == [team])
        #expect(removed.leagueIncluding(team) == nil)
    }

    @Test func referenceArrivalAddsMembersAndUnknownLeagueDoesNotGuess() {
        let league = SportsLibraryItem(name: "NBA", kind: .league)
        #expect(SportsLibraryMembership(saved: [league]).items == [league])
        let populated = SportsLibraryMembership(saved: [league], choices: SportsFollowCatalog.teams)
        #expect(populated.items.count == 31)
        #expect(populated.contains(SportsLibraryItem(name: "Knicks", kind: .team)))
        #expect(!populated.contains(SportsLibraryItem(name: "Dallas Cowboys", kind: .team)))
        let unknown = SportsLibraryItem(name: "Another competition", kind: .league)
        #expect(SportsLibraryMembership(saved: [unknown], choices: SportsFollowCatalog.teams).items == [unknown])
    }
}
