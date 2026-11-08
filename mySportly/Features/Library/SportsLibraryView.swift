import SwiftUI

struct SportsLibraryLabel: View {
    @Environment(AppStore.self) private var store
    let item: SportsLibraryItem
    var body: some View {
        HStack(spacing: 12) {
            SportsLogo(url: store.sportsData.index.logo(for: item))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).foregroundStyle(.primary)
                let league = store.sportsData.index.leagueName(for: item)
                if item.kind == .team && !league.isEmpty { Text(league).font(.caption).foregroundStyle(.secondary) }
                if item.kind == .league {
                    let count = store.sportsData.index.teams(in: item).count
                    if count > 0 { Text("\(count) teams").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct SportsLibraryRow: View {
    @Environment(AppStore.self) private var store
    let item: SportsLibraryItem
    var body: some View {
        let favorite = store.isSportsFavorite(item)
        NavigationLink { SportsLibraryItemView(item: item) } label: {
            HStack {
                SportsLibraryLabel(item: item)
                Spacer()
                if favorite { Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("Favorite") }
            }
        }
        .accessibilityIdentifier("sports-item-\(item.name)")
        .swipeActions(edge: .leading) {
            Button(favorite ? "Unfavorite" : "Favorite", systemImage: favorite ? "star.slash" : "star") { store.setSportsFavorite(item, !favorite) }.tint(.orange)
        }
        .swipeActions {
            if store.sportsLeagueIncluding(item) == nil {
                Button("Remove", role: .destructive) { store.removeSportsItem(item) }.accessibilityLabel("Remove \(item.name) from Library")
            }
        }
        .contextMenu {
            Button(favorite ? "Remove Favorite" : "Favorite", systemImage: favorite ? "star.slash" : "star") { store.setSportsFavorite(item, !favorite) }
            if store.sportsLeagueIncluding(item) == nil {
                Button("Remove from Library", role: .destructive) { store.removeSportsItem(item) }
            }
        }
    }
}

struct SportsLibraryCollectionView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    private var items: [SportsLibraryItem] {
        store.sportsLibrary.filter { query.isEmpty || $0.name.localizedStandardContains(query) || store.sportsData.index.leagueName(for: $0).localizedStandardContains(query) }
    }
    var body: some View {
        let favorites = items.filter { store.isSportsFavorite($0) }
        let others = items.filter { !store.isSportsFavorite($0) && (!query.isEmpty || store.sportsLeagueIncluding($0) == nil) }
        List {
            if !favorites.isEmpty { Section("Favorites") { ForEach(favorites) { SportsLibraryRow(item: $0) } } }
            if !others.isEmpty { Section(query.isEmpty ? "In Your Library" : "Results") { ForEach(others) { SportsLibraryRow(item: $0) } } }
            if items.isEmpty {
                if !query.isEmpty { ContentUnavailableView.search(text: query) }
                else {
                    ContentUnavailableView {
                        Label("Your Sports Library", systemImage: "sportscourt")
                    } description: { Text("Save a league or a team. Teams inside a league are not saved separately.") } actions: {
                        NavigationLink("Add Teams and Leagues") { SportsFollowingView() }
                    }
                }
            }
            if query.isEmpty && !items.isEmpty {
                Section { Text("Open a league to see its teams. Star any team or league to show its broadcasts in Favorites Today on Live.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Teams & Leagues")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your teams and leagues")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { SportsFollowingView() } label: { Label("Add Teams and Leagues", systemImage: "plus") }.accessibilityIdentifier("add-sports-library")
            }
        }
    }
}

struct SportsLibraryItemView: View {
    @Environment(AppStore.self) private var store
    let item: SportsLibraryItem
    @State private var schedule = SportsSchedule()
    @State private var games: [SportsGame] = []
    @State private var busy = true
    @State private var liveLimit = 50
    @State private var upcomingLimit = 50
    private struct Request: Equatable { let revision: Int; let links: Int; let date: Date; let itemID: String; let audience: ChannelAudience }
    private var request: Request { Request(revision: store.queryRevision, links: store.sportsLinkRevision, date: store.clock, itemID: item.id, audience: store.audience) }
    var body: some View {
        List {
            Section {
                if store.hasSportsItem(item) {
                    if let league = store.sportsLeagueIncluding(item) { Label("Included with \(league.name)", systemImage: "checkmark") }
                    else { Label("In Your Library", systemImage: "checkmark") }
                    Toggle("Favorite", isOn: Binding(get: { store.isSportsFavorite(item) }, set: { store.setSportsFavorite(item, $0) }))
                        .accessibilityIdentifier("sports-favorite")
                } else { Button("Add to Library", systemImage: "plus") { store.saveSportsItem(item) }.accessibilityIdentifier("save-sports-item") }
            } footer: { Text(item.kind == .league ? "Saving a league adds one item to Library. Its teams are inside the league. Favorites appear on Live when the guide lists a broadcast now or later today. Removing the league keeps teams you saved or favorited individually." : "Favorites appear on Live when the guide lists a broadcast now or later today. A team you favorite stays saved even if you later remove its league.") }
            if item.kind == .league {
                let teams = store.sportsData.index.teams(in: item)
                if !teams.isEmpty {
                    Section {
                        NavigationLink { LeagueTeamsView(league: item) } label: { LabeledContent("Teams", value: teams.count.formatted()) }
                            .accessibilityIdentifier("league-teams")
                    }
                }
            }
            SportsGamesSection(games: games)
            if busy { ProgressView("Finding programs…") }
            if !schedule.live.isEmpty {
                Section("On Now") {
                    ForEach(schedule.live.prefix(liveLimit)) { SportsEventRow(event: $0) }
                    if schedule.live.count > liveLimit { Button("Show More Live Events") { liveLimit += 50 } }
                }
            }
            if !schedule.upcoming.isEmpty {
                Section("Coming Up") {
                    ForEach(schedule.upcoming.prefix(upcomingLimit)) { SportsEventRow(event: $0) }
                    if schedule.upcoming.count > upcomingLimit { Button("Show More Upcoming Events") { upcomingLimit += 50 } }
                }
            }
            if !busy && schedule.isEmpty && games.isEmpty {
                ContentUnavailableView("No Upcoming Listings", systemImage: "calendar", description: Text("Your TV guide has no matching programs in the next 48 hours. Check matching channels below or refresh your guide."))
            }
            MatchingSportsChannelsSection(channels: schedule.channelsWithoutListings)
            Section {
                LineupScopeControl()
                NavigationLink("TV Guide Status") { GuideStatusView() }
            } footer: { Text("Programs come from your provider’s TV guide. Matches use team and league names, including common aliases.") }
        }
        .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.hasSportsItem(item) && store.sportsLeagueIncluding(item) == nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Remove from Library", role: .destructive) { store.removeSportsItem(item) }
                    } label: { Label("Library Options", systemImage: "ellipsis") }
                }
            }
        }
        .task(id: request) {
            let current = request, name = item.name, matched = store.matchedSportsPrograms
            let sports = store.sportsData.index, item = item
            busy = true
            guard let index = store.queryIndex else { schedule = SportsSchedule(); busy = store.preparingCatalog; return }
            do {
                let result = try await catalogWork {
                    var value = try index.sports(at: current.date, following: [name], followedOnly: true, audience: current.audience)
                    value.live.removeAll { matched.contains($0.id) }; value.upcoming.removeAll { matched.contains($0.id) }
                    return (value, sports.schedule(for: [item], at: current.date))
                }
                try Task.checkCancellation()
                schedule = result.0; games = result.1.filter { !store.feeds(for: $0.id).isEmpty }; busy = false
            } catch { if !Task.isCancelled { busy = false } }
        }
    }
}

struct LeagueTeamsView: View {
    @Environment(AppStore.self) private var store
    let league: SportsLibraryItem
    @State private var query = ""
    @State private var searchPresented = false
    var body: some View {
        List {
            ForEach(store.sportsData.index.teams(in: league).filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { item in
                if store.hasSportsItem(item) { SportsLibraryRow(item: item) }
                else { NavigationLink { SportsLibraryItemView(item: item) } label: { SportsLibraryLabel(item: item) }.accessibilityIdentifier("sports-item-\(item.name)") }
            }
        }
        .navigationTitle("\(league.name) Teams").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search teams")
        .onSubmit(of: .search) { searchPresented = false }
    }
}
