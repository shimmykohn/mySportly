import SwiftUI

struct DataOriginView: View {
    var body: some View {
        Form {
            Section("From Your Provider") {
                LabeledContent("Playlist", value: "Channels, stream addresses, original names and groups")
                LabeledContent("TV Guide", value: "Program titles, descriptions and scheduled times")
                Text("Game listings are matched from your guide and stream titles. An ended label follows the supplied time; it is not a verified final score.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("From API-SPORTS") {
                Text("This build includes a downloaded snapshot of team and league names and logo addresses. Logos are cached on your device. Current games and scores are not fetched from the sports API.")
            }
            Section("Built Into the App") {
                Text("Navigation, optional starting categories, common sport names, team aliases, and rules that recognize language, region and similar channel names. An offline sports directory fills gaps in the API snapshot.")
                Text("These are recognition aids. They do not invent channels or schedules.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your Choices and AI") {
                Text("You choose Jev’s category options. Jev’s accepted placements are saved; uncertain results wait for review. Your corrections take priority. Library contains only your saves and favorites.")
            }
        }.navigationTitle("Where Data Comes From")
    }
}

struct ChannelDataOriginView: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    private var classification: String {
        if store.flag(channel, "manual.category") { return "Your channel correction" }
        if let groups = store.directory?.nameGroups, let id = groups.channelGroup[channel.id], let group = groups.byID[id],
           let placement = groups.placements[id], placement.applies(to: group) {
            return placement.manual ? "Your group correction" : "Saved Jev decision"
        }
        return "Local recognition rules applied to provider names"
    }
    var body: some View {
        Form {
            Section("Provider Data") {
                LabeledContent("Original Name", value: channel.name)
                LabeledContent("Original Group", value: channel.group.isEmpty ? "Not supplied" : channel.group)
                LabeledContent("Source", value: store.sources.first { $0.id == channel.sourceID }?.name ?? "Unavailable")
            }
            Section("Organization") {
                LabeledContent("Shown Under", value: (store.directory?.taxonomyPath(for: channel.id) ?? [store.category(channel)]).joined(separator: " / "))
                LabeledContent("Chosen By", value: classification)
                if let details = store.directory?.metadata[channel.id] { Text(details.reason).font(.footnote).foregroundStyle(.secondary) }
            }
            Section { NavigationLink("About All App Data") { DataOriginView() } }
        }.navigationTitle("Data Source").navigationBarTitleDisplayMode(.inline)
    }
}
