import SwiftUI

/// Picks the second stream for two-up viewing: live games first, then
/// favorites and recents, or any channel by name.
struct SecondStreamPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    let games = store.secondGameChoices
                    if !games.isEmpty {
                        Section("Live Games") {
                            ForEach(games) { game in
                                Button { store.watchSecondGame(game.game); dismiss() } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(store.gameTitle(game.game) ?? "Game").font(.headline).foregroundStyle(.primary)
                                        if let league = store.homeSports.leagues[game.game.leagueID]?.name {
                                            Text(league).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityIdentifier("second-game-\(game.id)")
                            }
                        }
                    }
                    channels("Favorites", store.favorites)
                    channels("Recent", store.recent)
                } else {
                    let matches = matches
                    if matches.isEmpty { ContentUnavailableView.search(text: query) }
                    else { channels("Channels", matches) }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Channels")
            .safeAreaInset(edge: .bottom) {
                Text(oneStreamPlan
                     ? "Your provider plan allows one stream at a time, so the second may not start."
                     : "Plays under what’s on now with its sound off.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal).padding(.vertical, 8)
            }
            .navigationTitle("Watch Two")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var oneStreamPlan: Bool {
        store.sources.first { $0.id == store.playback.channel?.sourceID }.map { $0.connectionLimit < 2 } ?? false
    }

    private var playing: Set<String> { Set([store.playback.channel?.id, store.secondPlayback.channel?.id].compactMap { $0 }) }

    private var matches: [Channel] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let playing = playing
        return Array(store.channels.lazy.filter { !playing.contains($0.id) && !store.flag($0, "hidden") && store.name($0).localizedStandardContains(text) }.prefix(50))
    }

    @ViewBuilder private func channels(_ title: String, _ list: [Channel]) -> some View {
        let playing = playing
        let shown = list.filter { !playing.contains($0.id) }
        if !shown.isEmpty {
            Section(title) {
                ForEach(shown) { channel in
                    Button { store.playSecond(channel); dismiss() } label: { ChannelRow(channel: channel).contentShape(.rect) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("second-channel-\(channel.id)")
                }
            }
        }
    }
}
