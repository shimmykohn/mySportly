import SwiftUI

struct MatchingSportsChannelsSection: View {
    @Environment(AppStore.self) private var store
    let channels: [FollowedSportsChannel]
    @State private var limit = 30
    var body: some View {
        if !channels.isEmpty {
            Section {
                ForEach(channels.prefix(limit)) { match in
                    Button { store.play(match.channel) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.name(match.channel)).font(.headline)
                            Text("Matches " + match.names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("followed-channel-\(match.id)")
                }
                if channels.count > limit { Button("Show More Channels") { limit += 30 } }
            } header: { Text("Matching Channels") } footer: {
                Text("These channel names match your saved sports, but have no scheduled guide listings. Tap to check the stream; a live game is not confirmed.")
            }
        }
    }
}

struct SportsEventRow: View {
    let event: SportsEvent
    var body: some View {
        NavigationLink { ProgramDetailView(program: event.program, channel: event.channel) } label: {
            VStack(alignment: .leading, spacing: 4) {
                ProgramRow(program: event.program)
                Text(event.channelName).font(.caption).foregroundStyle(.secondary)
                if !event.followedNames.isEmpty { Label(event.followedNames.joined(separator: ", "), systemImage: "bookmark").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
