import SwiftUI

struct SportsGamesSection: View {
    let games: [SportsGame]
    @State private var limit = 40
    var body: some View {
        if !games.isEmpty {
            Section {
                ForEach(games.prefix(limit)) { SportsGameRow(game: $0) }
                if games.count > limit { Button("Show More Games") { limit += 40 } }
            } header: { Text("Games") } footer: { Text("From your TV guide · broadcast times") }
        }
    }
}

struct SportsGameRow: View {
    @Environment(AppStore.self) private var store
    let game: SportsGame
    var showsTodayStatus = false
    var body: some View {
        let index = store.sportsData.index
        NavigationLink { SportsGameView(gameID: game.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SportsLogo(url: index.teams[game.awayID]?.logo, size: 28)
                    Text(index.teams[game.awayID]?.libraryItem.name ?? "Away team")
                }
                HStack {
                    SportsLogo(url: index.teams[game.homeID]?.logo, size: 28)
                    Text(index.teams[game.homeID]?.libraryItem.name ?? "Home team")
                }
                HStack {
                    Text(index.leagues[game.leagueID]?.name ?? "")
                    if showsTodayStatus {
                        if game.start <= store.clock { Text("On now · guide") }
                        else { Text(game.start, format: .dateTime.hour().minute()) }
                    } else { Text(game.start, format: .dateTime.weekday(.abbreviated).hour().minute()) }
                    Spacer()
                    let count = store.feeds(for: game.id).count
                    if count > 0 { Label("\(count)", systemImage: "play.tv").accessibilityLabel("\(count) matching streams") }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("sports-game-\(game.id)")
    }
}

struct SportsGameView: View {
    @Environment(AppStore.self) private var store
    let gameID: String
    @State private var selectedFeed = ""
    var body: some View {
        let index = store.sportsData.index
        List {
            if let game = store.game(gameID) {
                Section {
                    if let away = index.teams[game.awayID] { NavigationLink { SportsLibraryItemView(item: away.libraryItem) } label: { SportsLibraryLabel(item: away.libraryItem) } }
                    if let home = index.teams[game.homeID] { NavigationLink { SportsLibraryItemView(item: home.libraryItem) } label: { SportsLibraryLabel(item: home.libraryItem) } }
                    if let league = index.leagues[game.leagueID] { NavigationLink(league.name) { SportsLibraryItemView(item: league.libraryItem) } }
                    LabeledContent(game.guideEnd == nil ? "Starts" : "Guide Time") { Text(game.start, format: .dateTime.weekday().month().day().hour().minute()) }
                    if game.status == .postponed { Label("Postponed", systemImage: "clock.badge.exclamationmark") }
                    if game.status == .cancelled { Text("Cancelled") }
                    if store.demo { Text("Sample game · plays Apple’s public test video").font(.caption).foregroundStyle(.secondary) }
                }
                let feeds = store.feeds(for: game.id)
                let available = store.feeds(for: game.id, playableOnly: true)
                Section {
                    Picker("Stream", selection: $selectedFeed) {
                        Text("Automatic").tag("")
                        ForEach(feeds) { channel in Text(store.name(channel)).tag(channel.id) }
                    }.pickerStyle(.menu).accessibilityIdentifier("game-stream-picker")
                    Button("Watch", systemImage: "play.fill") {
                        store.watchGame(game, feed: feeds.first { $0.id == selectedFeed })
                    }.disabled(available.isEmpty || (!selectedFeed.isEmpty && !available.contains { $0.id == selectedFeed })).accessibilityIdentifier("watch-sports-game")
                    if store.matchingGames { ProgressView("Matching your streams…") }
                    else if feeds.isEmpty { Text("No matching stream in your lineup yet. Refresh your TV guide or check All Channels.").foregroundStyle(.secondary) }
                    else if available.isEmpty { Text(game.start > store.clock ? "Matching streams will be available at the guide time." : "The scheduled guide time has passed. This does not confirm that the game or stream has ended.").foregroundStyle(.secondary) }
                } header: { Text("Watch") } footer: { Text("Automatic uses your saved stream when available. Each choice opens one stream.") }
                if !feeds.isEmpty {
                    Section("Matching Streams") {
                        ForEach(feeds) { channel in
                            Button { selectedFeed = channel.id; store.watchGame(game, feed: channel) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.name(channel)).foregroundStyle(.primary)
                                    Text(streamDescription(channel)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.disabled(!available.contains { $0.id == channel.id })
                        }
                    }
                }
            } else { ContentUnavailableView("Game Unavailable", systemImage: "calendar", description: Text("This game is no longer in the saved schedule.")) }
        }
        .navigationTitle("Game").navigationBarTitleDisplayMode(.inline)
    }
    private func streamDescription(_ channel: Channel) -> String {
        [store.sources.first { $0.id == channel.sourceID }?.name ?? "", Locale.current.localizedString(forLanguageCode: store.language(channel)) ?? store.language(channel), channel.quality.isEmpty || channel.quality == "Auto" ? "" : "\(channel.quality) · provider label"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
