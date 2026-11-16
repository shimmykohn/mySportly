import SwiftUI

/// Teams you follow, leagues you added, and favorite channels.
struct MyStuffView: View {
    @Environment(AppStore.self) private var store
    @State private var picking = false

    var body: some View {
        let teams = store.followedTeams, leagues = store.addedLeagues, channels = store.favorites
        List {
            if teams.isEmpty && leagues.isEmpty && channels.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Here Yet", systemImage: "star")
                } actions: {
                    Button("Follow Teams") { picking = true }.buttonStyle(.borderedProminent)
                }
            }
            if !teams.isEmpty {
                Section("Teams") {
                    ForEach(teams) { team in
                        NavigationLink { TeamPage(team: team) } label: { SportsItemLabel(item: team) }
                            .swipeActions { Button("Unfollow", role: .destructive) { store.unfollow(team) } }
                            .contextMenu { Button("Unfollow", systemImage: "minus.circle", role: .destructive) { store.unfollow(team) } }
                            .accessibilityIdentifier("my-stuff-team-\(team.name)")
                    }
                }
            }
            if !leagues.isEmpty {
                Section("Leagues") {
                    ForEach(leagues) { league in
                        NavigationLink { LeaguePage(league: league) } label: { SportsItemLabel(item: league) }
                            .swipeActions { Button("Remove", role: .destructive) { store.unfollow(league) } }
                            .contextMenu { Button("Remove League", systemImage: "minus.circle", role: .destructive) { store.unfollow(league) } }
                            .accessibilityIdentifier("my-stuff-league-\(league.name)")
                    }
                }
            }
            if !channels.isEmpty {
                Section("Channels") {
                    ForEach(channels) { channel in
                        Button { store.play(channel, source: "channel.\(channel.id)") } label: { ChannelRow(channel: channel).contentShape(.rect) }
                            .buttonStyle(.plain)
                            .playerSource("channel.\(channel.id)")
                            .swipeActions { Button("Remove Favorite", role: .destructive) { store.toggle(channel, "favorite") } }
                            .accessibilityIdentifier("my-stuff-channel-\(channel.id)")
                    }
                }
            }
        }
        .navigationTitle("My Stuff")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Follow Teams and Leagues", systemImage: "plus") { picking = true }.accessibilityIdentifier("my-stuff-add")
            }
        }
        .sheet(isPresented: $picking) { NavigationStack { FollowPicker() } }
    }
}

/// Logo, name and (for teams) league.
struct SportsItemLabel: View {
    @Environment(AppStore.self) private var store
    let item: SportsLibraryItem
    var body: some View {
        HStack(spacing: 12) {
            SportsLogo(url: store.logo(for: item), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                if item.kind == .team {
                    let league = store.sportsData.index.leagueName(for: item)
                    if !league.isEmpty { Text(league).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

/// Follow / Following for a team, Add to My Sports / Added for a league.
struct FollowButton: View {
    @Environment(AppStore.self) private var store
    let item: SportsLibraryItem
    var compact = false
    var body: some View {
        let following = store.isFollowing(item)
        let title = item.kind == .team ? (following ? "Following" : "Follow") : (following ? "Added" : "Add to My Sports")
        Button(title, systemImage: following ? "checkmark" : "plus") {
            following ? store.unfollow(item) : store.follow(item)
        }
        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        .accessibilityLabel(following ? "\(title) \(item.name)" : "\(title) \(item.name)")
        .accessibilityIdentifier("follow-\(item.name)")
    }
}

/// Erases the label style so one button can switch between styles.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
