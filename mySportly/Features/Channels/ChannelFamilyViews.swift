import SwiftUI

extension AppStore {
    /// The numbered set a channel belongs to ("NFL" for "NFL 07"): the AI's
    /// answer once it has seen the name, else the local slot rules.
    func familyName(_ channel: Channel) -> String? {
        if aiResults.namesAsked.contains(channel.name) { return aiResults.families?[channel.name] }
        guard let groups = directory?.nameGroups, let id = groups.channelGroup[channel.id],
              let group = groups.byID[id], group.family else { return nil }
        return group.name
    }

    func collapseFamilies<Item>(_ items: [Item], channel: (Item) -> Channel) -> [FamilyEntry<Item>] {
        ChannelFamilies.collapse(items, channel: channel) { familyName($0) }
    }
}

/// One row for a numbered set: its name, size and how many are on now.
struct ChannelFamilyRow: View {
    @Environment(AppStore.self) private var store
    let name: String
    let channels: [Channel]

    var body: some View {
        let live = channels.filter { store.now(on: $0) != nil }.count
        NavigationLink { ChannelFamilyView(name: name, channels: channels) } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title3).foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    Text(live > 0 ? "\(channels.count) channels · \(live) on now" : "\(channels.count) channels")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("channel-family-\(name)")
    }
}

/// Every channel in a numbered set, with what each is showing.
struct ChannelFamilyView: View {
    let name: String
    let channels: [Channel]

    var body: some View {
        List(channels) { PlayableChannelRow(channel: $0) }
            .navigationTitle(name)
            .toolbarTitleDisplayMode(.inline)
    }
}
