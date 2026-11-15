import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var choosingFollows = false

    var body: some View {
        let content = store.homeContent
        let isEmpty = content.hero.isEmpty && content.teamGames.isEmpty && content.leagueRows.isEmpty && content.channels.isEmpty
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
                    if let latest = store.continueWatching.first {
                        HomeContinueCard(item: latest).padding(.horizontal)
                    }
                    if !content.hero.isEmpty {
                        HomeHeroPager(items: content.hero).accessibilityIdentifier("home-hero")
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
                }
            }
            .padding(.vertical, 8)
        }
        .accessibilityIdentifier("home-root")
        // Verbatim: a localized key would format 1234 as "1,234".
        .accessibilityValue(Text(verbatim: "launch-ms=\(store.launchTimeline.milliseconds(to: .firstInteractive) ?? -1) ready=\(store.catalogReady ? 1 : 0)"))
        .navigationTitle("Home")
        .toolbar {
            if !store.catalogReady && isEmpty && !store.sources.isEmpty {
                ToolbarItem(placement: .principal) { ProgressView() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "person.crop.circle") { store.showSettings = true }
                    .accessibilityIdentifier("home-profile")
            }
        }
        .refreshable { Task { await store.refreshDueSources(force: true) } }
        .sheet(isPresented: $choosingFollows) {
            NavigationStack { FollowPicker() }
        }
    }
}

/// A titled, horizontally scrolling shelf.
struct HomeRow<Content: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).padding(.horizontal).accessibilityAddTraits(.isHeader)
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

/// The most recent unfinished movie or episode, first thing on Home.
private struct HomeContinueCard: View {
    @Environment(AppStore.self) private var store
    let item: WatchProgress

    var body: some View {
        HStack(spacing: 14) {
            Poster(url: item.artwork, title: item.title).frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Continue Watching").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(item.title).font(.headline).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 8) {
                    ProgressView(value: item.fraction)
                    Text("\(item.remaining.watchDuration) left").font(.caption).foregroundStyle(.secondary).fixedSize()
                }
            }
            Button("Resume", systemImage: "play.fill") { store.resume(item) }
                .labelStyle(.iconOnly).font(.title3)
                .buttonStyle(.glassProminent).buttonBorderShape(.circle)
                .accessibilityIdentifier("home-resume")
        }
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 18))
        .contextMenu {
            Button("Mark as Watched", systemImage: "checkmark.circle") { store.setWatched(item, true) }
            Button("Remove from Continue Watching", systemImage: "minus.circle", role: .destructive) { store.clearProgress(item) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-continue")
    }
}
