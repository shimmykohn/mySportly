import SwiftUI

struct TeamPage: View {
    @Environment(AppStore.self) private var store
    let team: SportsLibraryItem

    var body: some View {
        let games = store.upcomingGames(for: team)
        List {
            Section {
                VStack(spacing: 12) {
                    SportsLogo(url: store.logo(for: team), size: 96)
                    Text(team.name).font(.title2.bold()).multilineTextAlignment(.center)
                    let league = store.sportsData.index.leagueName(for: team)
                    if !league.isEmpty { Text(league).foregroundStyle(.secondary) }
                    FollowButton(item: team).buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            if store.isFollowing(team) {
                Section {
                    Toggle("Notify When Games Start", isOn: Binding(get: { store.notifiesGameStart(team) },
                                                                     set: { enabled in Task { await store.setNotifiesGameStart(team, enabled) } }))
                        .accessibilityIdentifier("team-notify")
                }
            }
            GameListSection(games: games)
        }
        .navigationTitle(team.name).navigationBarTitleDisplayMode(.inline)
    }
}

struct LeaguePage: View {
    @Environment(AppStore.self) private var store
    let league: SportsLibraryItem

    var body: some View {
        let games = store.upcomingGames(for: league)
        let teams = store.sportsData.index.teams(in: league)
        List {
            Section {
                VStack(spacing: 12) {
                    SportsLogo(url: store.logo(for: league), size: 96)
                    Text(league.name).font(.title2.bold())
                    FollowButton(item: league).buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            GameListSection(games: games)
            if !teams.isEmpty {
                Section("Teams") {
                    ForEach(teams) { team in
                        HStack {
                            NavigationLink { TeamPage(team: team) } label: { SportsItemLabel(item: team) }
                            FollowButton(item: team, compact: true).buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle(league.name).navigationBarTitleDisplayMode(.inline)
    }
}

/// Upcoming games on the user's channels, or one line saying there are none.
struct GameListSection: View {
    let games: [HomeGame]
    var body: some View {
        Section("Games") {
            if games.isEmpty {
                Text("No games on your channels this week.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) { ForEach(games) { HomeGameCard(game: $0) } }
                        .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }
}

/// Find teams and leagues to follow or add.
struct FollowPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: SportsFollowKind = .team
    @State private var query = ""

    var body: some View {
        let choices = store.sportsData.index.choices.filter {
            $0.kind == kind && (query.isEmpty || ([$0.name, $0.league] + $0.aliases).contains { $0.localizedStandardContains(query) })
        }
        List {
            Section {
                Picker("Show", selection: $kind) {
                    Text("Teams").tag(SportsFollowKind.team)
                    Text("Leagues").tag(SportsFollowKind.league)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(choices) { choice in
                    let item = SportsLibraryItem(name: choice.name, kind: kind)
                    HStack {
                        SportsItemLabel(item: item)
                        Spacer()
                        FollowButton(item: item, compact: true).buttonStyle(.borderless).font(.title3)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: kind == .team ? "Search teams" : "Search leagues")
        .navigationTitle(kind == .team ? "Follow Teams" : "Add Leagues").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
