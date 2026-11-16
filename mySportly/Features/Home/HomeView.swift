import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var choosingFollows = false
    /// Height of the status and navigation bars, which the hero's colors fill.
    @State private var topInset: CGFloat = 0

    var body: some View {
        @Bindable var store = store
        let content = store.homeContent
        let onNow = store.homeOnNow
        let isEmpty = content.hero.isEmpty && content.teamGames.isEmpty && content.leagueRows.isEmpty && content.channels.isEmpty
        let continuing = store.continueWatching.first
        let showsHero = (!content.hero.isEmpty || continuing != nil) && !(store.sources.isEmpty && !store.demo && !store.loading)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if let error = store.personal.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").padding(.horizontal)
                }
                if store.sources.isEmpty && !store.demo && !store.loading {
                    ContentUnavailableView {
                        Label("Your TV starts here", systemImage: "play.tv")
                    } description: {
                        Text("Connect an Xtream or M3U source to build your personal lineup.")
                    } actions: {
                        Button("Connect a Source") { store.showSetup = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    if showsHero {
                        HomeHeroPager(items: content.hero, continuing: continuing, topInset: topInset).accessibilityIdentifier("home-hero")
                    }
                    if content.showsFollowPrompt {
                        ContentUnavailableView {
                            Label("Follow Your Teams", systemImage: "sportscourt")
                        } actions: {
                            Button("Choose Teams and Leagues") { choosingFollows = true }.buttonStyle(.bordered)
                        }
                        .accessibilityElement(children: .contain).accessibilityIdentifier("home-follow-prompt")
                    } else {
                        if !content.teamGames.isEmpty {
                            HomeRow(title: "Your Teams", identifier: "home-teams") {
                                ForEach(content.teamGames) { HomeGameCard(game: $0) }
                            }
                        }
                        ForEach(content.leagueRows) { row in
                            HomeRow(title: row.league.name, identifier: "home-league-\(row.league.id)") {
                                ForEach(row.games) { HomeGameCard(game: $0) }
                            }
                        }
                    }
                    if !content.channels.isEmpty {
                        HomeRow(title: "Your Channels", identifier: "home-channels") {
                            ForEach(content.channels) { item in
                                if let channel = store.channelIndex[item.channelID] { HomeChannelCard(channel: channel, program: item.program) }
                            }
                        }
                    }
                    if !onNow.isEmpty {
                        HomeRow(title: "On Now", identifier: "home-on-now", action: { store.homeDestination = .guide }) {
                            ForEach(onNow) { item in
                                if let channel = store.channelIndex[item.channelID] { HomeChannelCard(channel: channel, program: item.program) }
                            }
                        }
                    }
                }
            }
            .padding(.top, showsHero ? 0 : 8).padding(.bottom, 8)
        }
        // The hero runs under the status and navigation bars. Measured outside
        // the ignored edge, where the bars' height is still reported.
        .ignoresSafeArea(edges: showsHero ? .top : [])
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .accessibilityIdentifier("home-root")
        // Verbatim: a localized key would format 1234 as "1,234".
        .accessibilityValue(Text(verbatim: "launch-ms=\(store.launchTimeline.milliseconds(to: .firstInteractive) ?? -1) ready=\(store.catalogReady ? 1 : 0)"))
        .navigationTitle("Home")
        .toolbar {
            if !store.catalogReady && isEmpty && !store.sources.isEmpty {
                ToolbarItem(placement: .principal) { ProgressView() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Guide", systemImage: "list.bullet.rectangle") { store.homeDestination = .guide }
                    .accessibilityIdentifier("home-guide")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "person.crop.circle") { store.showSettings = true }
                    .accessibilityIdentifier("home-profile")
            }
        }
        .navigationDestination(item: $store.homeDestination) { destination in
            switch destination {
            case .guide: GuideView().toolbarTitleDisplayMode(.inline)
            case .program(let program, let channel): ProgramDetailView(program: program, channel: channel)
            case .game(let id): SportsGameView(gameID: id)
            }
        }
        .refreshable { Task { await store.refreshDueSources(force: true) } }
        .sheet(isPresented: $choosingFollows) {
            NavigationStack { FollowPicker() }
        }
    }
}

/// A titled, horizontally scrolling shelf. With an action, the title opens more.
struct HomeRow<Content: View>: View {
    let title: String
    let identifier: String
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Text(title)
                            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(identifier + "-more")
                } else { Text(title) }
            }
            .font(.headline).padding(.horizontal).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) { content }
                    .scrollTargetLayout()
                    .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
