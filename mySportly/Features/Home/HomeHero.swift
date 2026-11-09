import SwiftUI

struct HomeHeroPager: View {
    let items: [HomeHero]
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        TabView {
            ForEach(items) { item in
                Group {
                    switch item {
                    case .game(let game): HeroGamePage(game: game)
                    case .channel(let channel): HeroChannelPage(item: channel)
                    }
                }
                .playerSource("hero.\(item.id)")
                .padding(.horizontal)
                .padding(.bottom, items.count > 1 ? 36 : 0)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
        .frame(height: (sizeClass == .regular ? 400 : 300) + (items.count > 1 ? 36 : 0))
    }
}

/// Team colors and both logos on Liquid Glass.
struct HeroGameArt: View {
    let away: SportsTeam?
    let home: SportsTeam?
    @State private var awayColor: Color?
    @State private var homeColor: Color?

    var body: some View {
        LinearGradient(colors: [awayColor ?? Color.secondary.opacity(0.35), homeColor ?? Color.secondary.opacity(0.2)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .top) {
                HStack(spacing: 24) {
                    SportsLogo(url: away?.logo, size: 56)
                    SportsLogo(url: home?.logo, size: 56)
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
                .glassEffect(in: .rect(cornerRadius: 24))
                .padding(.top, 18)
            }
            .task(id: away?.logo) { awayColor = await color(away?.logo) }
            .task(id: home?.logo) { homeColor = await color(home?.logo) }
    }

    private func color(_ url: URL?) async -> Color? {
        guard let url, let rgb = await SportsLogoCache.shared.color(url: url) else { return nil }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct HeroGamePage: View {
    @Environment(AppStore.self) private var store
    let game: HomeGame

    var body: some View {
        let teams = store.homeSports.teams
        let away = teams[game.game.awayID], home = teams[game.game.homeID]
        HeroCard {
            HeroGameArt(away: away, home: home)
        } details: {
            HomeGameBadge(game: game)
            Text("\(away?.libraryItem.name ?? "Away") at \(home?.libraryItem.name ?? "Home")")
                .font(.title3.bold()).lineLimit(2)
            if let league = store.homeSports.leagues[game.game.leagueID] { Text(league.name).font(.subheadline).opacity(0.85) }
        } actions: {
            if game.state == .live {
                Button("Watch", systemImage: "play.fill") { store.watchGame(game.game, source: "hero.\(game.id)") }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("home-hero-watch")
            }
            let playing = [away, home].compactMap { $0 }
            if !playing.isEmpty {
                Menu {
                    ForEach(playing) { team in
                        Button { store.toggleFollow(team) } label: {
                            Label(team.libraryItem.name, systemImage: store.isFollowing(team) ? "checkmark" : "plus")
                        }
                    }
                } label: {
                    if playing.contains(where: store.isFollowing) { Label("Following", systemImage: "checkmark") }
                    else { Label("Follow", systemImage: "plus") }
                }
                .buttonStyle(.glass)
            }
        }
    }
}

struct HeroChannelPage: View {
    @Environment(AppStore.self) private var store
    let item: HomeChannel

    var body: some View {
        if let channel = store.channelIndex[item.channelID] {
            let favorite = store.flag(channel, "favorite")
            HeroCard {
                LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.secondary.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(alignment: .top) {
                        ChannelLogo(url: channel.logo).frame(width: 130, height: 76)
                            .glassEffect(in: .rect(cornerRadius: 22)).padding(.top, 18)
                    }
            } details: {
                Text(store.name(channel)).font(.subheadline).opacity(0.85)
                Text(item.program?.title ?? store.name(channel)).font(.title3.bold()).lineLimit(2)
            } actions: {
                Button("Watch", systemImage: "play.fill") { store.play(channel, source: "hero.channel.\(channel.id)") }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("home-hero-watch")
                Button(favorite ? "Favorited" : "Favorite", systemImage: favorite ? "heart.fill" : "heart") { store.toggle(channel, "favorite") }
                    .buttonStyle(.glass)
            }
        }
    }
}

/// Artwork with a legible title area and actions along the bottom.
struct HeroCard<Art: View, Details: View, Actions: View>: View {
    @ViewBuilder let art: Art
    @ViewBuilder let details: Details
    @ViewBuilder let actions: Actions

    var body: some View {
        art
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    details
                    HStack(spacing: 10) { actions }.padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .clipShape(.rect(cornerRadius: 26))
            .accessibilityElement(children: .contain)
    }
}
