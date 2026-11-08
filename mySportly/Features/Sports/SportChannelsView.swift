import SwiftUI

struct SportChannelGroupRow: View {
    let group: SportChannelGroup
    var body: some View {
        NavigationLink {
            SportChannelsView(sport: group.sport)
        } label: {
            Label {
                LabeledContent(group.sport.title, value: group.count == 1 ? "1 channel" : "\(group.count.formatted()) channels")
            } icon: {
                Image(systemName: group.sport.symbol)
            }
        }
        .accessibilityIdentifier("sport-group-\(group.id)")
    }
}

struct SportChannelsView: View {
    @Environment(AppStore.self) private var store
    let sport: ChannelSport
    var providerGroup: String? = nil
    @State private var query = ""
    @State private var browser = ChannelBrowser()
    @State private var limit = 100

    private var request: ChannelBrowseRequest {
        var request = ChannelBrowseRequest()
        request.sport = sport; request.query = query; request.audience = store.audience
        request.providerGroup = providerGroup
        request.collapseVariants = true; request.excludeInactive = true
        return request
    }

    var body: some View {
        List {
            if browser.loading { ProgressView("Finding channels…") }
            if !browser.providerGroups.isEmpty {
                Section("Groups") {
                    ForEach(browser.providerGroups) { group in
                        NavigationLink {
                            SportChannelsView(sport: sport, providerGroup: group.label)
                        } label: { LabeledContent(group.label, value: "\(group.count.formatted()) channels") }
                            .accessibilityIdentifier("provider-group-\(group.id)")
                    }
                }
            }
            if !browser.ungroupedChannels.isEmpty || (!browser.loading && browser.channels.isEmpty) {
              Section(browser.providerGroups.isEmpty ? "\(browser.channels.count) Channels" : "More Channels") {
                ForEach(browser.ungroupedChannels.prefix(limit)) { PlayableChannelRow(channel: $0) }
                MoreChannelsRow(total: browser.ungroupedChannels.count, limit: $limit)
                if !browser.loading && browser.channels.isEmpty {
                    ContentUnavailableView.search(text: query.isEmpty ? sport.title : query)
                }
              }
            }
        }
        .navigationTitle(providerGroup ?? sport.title)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu { LineupScopePicker().pickerStyle(.inline) } label: { Label("Filter Channels", systemImage: "line.3.horizontal.decrease") }
            }
        }
        .task(id: BrowseTaskID(revision: store.queryRevision, request: request)) {
            limit = 100
            await browser.update(directory: store.directory, request: request, grouping: providerGroup == nil && query.isEmpty ? .providerLabels : .none)
        }
    }
}
