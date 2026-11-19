import SwiftUI

struct HomeGameCard: View {
    @Environment(AppStore.self) private var store
    let game: HomeGame

    var body: some View {
        let teams = store.homeSports.teams
        let away = teams[game.game.awayID], home = teams[game.game.homeID]
        Group {
            if game.state == .live {
                Button { store.watchGame(game.game, source: "game.\(game.id)") } label: { card(away: away, home: home) }
                    .playerSource("game.\(game.id)")
            } else {
                NavigationLink { SportsGameView(gameID: game.id) } label: { card(away: away, home: home) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-game-\(game.id)")
        .contextMenu {
            if game.state == .live { Button("Watch", systemImage: "play") { store.watchGame(game.game) } }
            Button("Game Details", systemImage: "info.circle") { store.homeDestination = .game(game.id) }
            ForEach([away, home].compactMap { $0 }) { team in
                let following = store.isFollowing(team)
                Button("\(following ? "Unfollow" : "Follow") \(team.libraryItem.name)", systemImage: following ? "minus.circle" : "plus.circle") { store.toggleFollow(team) }
            }
        }
    }

    private func card(away: SportsTeam?, home: SportsTeam?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SportsLogo(url: away?.logo, size: 34)
                Text("at").font(.caption).foregroundStyle(.secondary)
                SportsLogo(url: home?.logo, size: 34)
                Spacer(minLength: 0)
                HomeGameBadge(game: game)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(away?.libraryItem.name ?? "Away")
                Text(home?.libraryItem.name ?? "Home")
            }
            .font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(14)
        .frame(width: 230, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 18))
        .contentShape([.interaction, .contextMenuPreview], .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// A red LIVE capsule, or the start time (with the weekday when it isn't today).
struct HomeGameBadge: View {
    let game: HomeGame
    var body: some View {
        if game.state == .live {
            Text("LIVE").font(.caption2.bold()).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3).background(.red, in: .capsule)
        } else {
            Text(game.game.start, format: Calendar.current.isDateInToday(game.game.start) ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

struct HomeChannelCard: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    let program: GuideProgram?

    var body: some View {
        Button { store.play(channel, source: "channel.\(channel.id)") } label: {
            VStack(alignment: .leading, spacing: 8) {
                ChannelLogo(url: channel.logo)
                    .frame(width: 150, height: 84)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 16))
                Text(store.name(channel)).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let program { Text(program.title).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            .frame(width: 150, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .playerSource("channel.\(channel.id)")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-channel-\(channel.id)")
        .contextMenu {
            ChannelActions(channel: channel)
            if let program { Button("Program Details", systemImage: "info.circle") { store.homeDestination = .program(program, channel) } }
        }
    }
}

struct ChannelLogo: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFit().padding(12) } placeholder: {
            Image(systemName: "tv").font(.title2).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}
