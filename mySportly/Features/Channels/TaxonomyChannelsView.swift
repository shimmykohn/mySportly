import SwiftUI

struct TaxonomyBrowseRow: View {
    let group: TaxonomyBrowseGroup
    private var sport: ChannelSport? { ChannelSport.allCases.first { $0.title == group.name && group.path.first == "Sports" } }
    var body: some View {
        NavigationLink { TaxonomyChannelsView(path: group.path) } label: {
            Label { LabeledContent(group.name, value: "\(group.count.formatted()) channels") }
                icon: { Image(systemName: sport?.symbol ?? "folder") }
        }.accessibilityIdentifier(sport.map { "sport-group-\($0.rawValue)" } ?? (group.path.count == 3 ? "provider-group-\(group.name)" : "taxonomy-\(group.id)"))
    }
}

struct TaxonomyChannelsView: View {
    @Environment(AppStore.self) private var store
    let path: [String]
    var nameGroup: String? = nil
    @State private var query = ""
    @State private var loading = true
    @State private var children: [TaxonomyBrowseGroup] = []
    @State private var families: [CatalogNameGroup] = []
    @State private var channels: [Channel] = []
    @State private var limit = 100
    private var request: ChannelBrowseRequest {
        var result = ChannelBrowseRequest(); result.taxonomyPath = path; result.nameGroupID = nameGroup
        result.query = query; result.audience = store.audience; result.collapseVariants = true; result.excludeInactive = true
        return result
    }
    var body: some View {
        List {
            if loading && channels.isEmpty && children.isEmpty && families.isEmpty { ProgressView("Finding channels…") }
            if !children.isEmpty { Section("Subcategories") { ForEach(children) { TaxonomyBrowseRow(group: $0) } } }
            if !families.isEmpty {
                Section("Channel Groups") {
                    ForEach(families) { group in
                        NavigationLink { TaxonomyChannelsView(path: path, nameGroup: group.id) } label: {
                            LabeledContent(group.name, value: "\(group.channelIDs.count.formatted()) streams")
                        }.accessibilityIdentifier("name-group-\(group.id)")
                    }
                }
            }
            if !channels.isEmpty {
                Section(children.isEmpty && families.isEmpty ? "Channels" : "More Channels") {
                    ForEach(channels.prefix(limit)) { PlayableChannelRow(channel: $0) }
                    MoreChannelsRow(total: channels.count, limit: $limit)
                }
            }
            if !loading && channels.isEmpty && children.isEmpty && families.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle(nameGroup.flatMap { store.directory?.nameGroups.byID[$0]?.name } ?? path.last ?? "Channels")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Menu {
                LibrarySaveButton(item: savedItem)
                Button(store.isLibraryFavorite(savedItem) ? "Remove Favorite" : "Favorite", systemImage: "star") { store.setLibraryFavorite(savedItem, !store.isLibraryFavorite(savedItem)) }
                LineupScopePicker().pickerStyle(.inline)
            } label: { Label("Category Options", systemImage: "ellipsis") }
        } }
        .task(id: BrowseTaskID(revision: store.queryRevision, request: request)) {
            guard let directory = store.directory else { return }
            let request = request, path = path
            do {
                if !request.query.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
                let result = try await catalogWork {
                    let all = try directory.browse(request)
                    let grouped = request.query.isEmpty && request.nameGroupID == nil ? try directory.groupedTaxonomy(in: all, under: path) : (groups: [], remaining: all)
                    let counts = Dictionary(grouping: grouped.remaining) { directory.nameGroups.channelGroup[$0.id] ?? "" }
                    var families = request.query.isEmpty && request.nameGroupID == nil ? counts.filter { $0.value.count >= 2 }.keys.compactMap { directory.nameGroups.byID[$0] }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : []
                    if families.count == 1, counts.count == 1 { families = [] }
                    let familyIDs = Set(families.map(\.id))
                    let remaining = grouped.remaining.filter { !familyIDs.contains(directory.nameGroups.channelGroup[$0.id] ?? "") }
                    return (grouped.groups, families, remaining)
                }
                try Task.checkCancellation(); children = result.0; families = result.1; channels = result.2; limit = 100; loading = false
            } catch { if !Task.isCancelled { loading = false } }
        }
    }
    private var savedItem: LibraryBookmark {
        if let nameGroup { return LibraryBookmark(kind: .channelGroup, reference: nameGroup, name: store.directory?.nameGroups.byID[nameGroup]?.name ?? "Channel Group") }
        return .category(path)
    }
}
