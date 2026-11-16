import SwiftUI

extension EnvironmentValues {
    /// Space the hero's art runs under at the top (status and navigation bars).
    @Entry var heroTopInset: CGFloat = 0
}

/// Edge to edge, as in the TV app: each page's colors run up under the bars
/// and fade into the page below.
struct HomeHeroPager: View {
    let items: [HomeHero]
    /// The most recent unfinished movie or episode, as the first page.
    var continuing: WatchProgress?
    var topInset: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let pages = items.count + (continuing == nil ? 0 : 1)
        TabView {
            if let continuing {
                HeroContinuePage(item: continuing).playerSource("hero.continue")
            }
            ForEach(items) { item in
                Group {
                    switch item {
                    case .game(let game): HeroGamePage(game: game)
                    case .channel(let channel): HeroChannelPage(item: channel)
                    }
                }
                .playerSource("hero.\(item.id)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: pages > 1 ? .always : .never))
        .environment(\.heroTopInset, topInset)
        .frame(height: (sizeClass == .regular ? 460 : 380) + topInset)
    }
}

/// Team colors and both logos on Liquid Glass.
struct HeroGameArt: View {
    let away: SportsTeam?
    let home: SportsTeam?
    @Environment(\.heroTopInset) private var topInset
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
                .padding(.top, 18 + topInset)
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
    @Environment(\.heroTopInset) private var topInset
    let item: HomeChannel

    var body: some View {
        if let channel = store.channelIndex[item.channelID] {
            let favorite = store.flag(channel, "favorite")
            HeroCard {
                LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.secondary.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(alignment: .top) {
                        ChannelLogo(url: channel.logo).frame(width: 130, height: 76)
                            .glassEffect(in: .rect(cornerRadius: 22)).padding(.top, 18 + topInset)
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

/// Full-bleed artwork with the title and actions over it. The art darkens
/// behind the text, then fades out into the page so the colors run on down.
struct HeroCard<Art: View, Details: View, Actions: View>: View {
    @ViewBuilder let art: Art
    @ViewBuilder let details: Details
    @ViewBuilder let actions: Actions
    static var fade: CGFloat { 72 }

    var body: some View {
        art
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.55), location: 0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.fade)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    details
                    HStack(spacing: 10) { actions }.padding(.top, 4)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.bottom, Self.fade - 8)
            }
            .accessibilityElement(children: .contain)
    }
}

/// A movie or episode in progress: its artwork across the page, the poster on
/// glass, and Resume.
struct HeroContinuePage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.heroTopInset) private var topInset
    let item: WatchProgress

    var body: some View {
        HeroCard {
            Color.clear
                .overlay {
                    AsyncImage(url: item.artwork) { phase in
                        if let image = phase.image { image.resizable().scaledToFill().blur(radius: 30).saturation(1.3) }
                        else { LinearGradient(colors: [.indigo.opacity(0.6), .secondary.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing) }
                    }
                }
                .clipped()
                .overlay(alignment: .top) {
                    Poster(url: item.artwork, title: item.title)
                        .frame(height: 150)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                        .padding(.top, 18 + topInset)
                }
        } details: {
            Label("Continue Watching", systemImage: "play.circle.fill").font(.caption.weight(.semibold)).opacity(0.9)
            Text(item.title).font(.title3.bold()).lineLimit(2)
            if !item.subtitle.isEmpty { Text(item.subtitle).font(.subheadline).opacity(0.85).lineLimit(1) }
            HStack(spacing: 8) {
                ProgressView(value: item.fraction).tint(.white).frame(maxWidth: 140)
                Text("\(item.remaining.watchDuration) left").font(.caption).opacity(0.85)
            }
        } actions: {
            Button("Resume", systemImage: "play.fill") { store.resume(item) }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("home-resume")
            Menu {
                Button("Mark as Watched", systemImage: "checkmark.circle") { store.setWatched(item, true) }
                Button("Remove from Continue Watching", systemImage: "minus.circle", role: .destructive) { store.clearProgress(item) }
            } label: { Label("More", systemImage: "ellipsis") }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
        }
        .accessibilityIdentifier("home-continue")
    }
}
