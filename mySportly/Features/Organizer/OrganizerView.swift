import SwiftUI

struct OrganizerView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var reviewOnly = false
    @State private var rows: [CatalogNameGroup] = []
    @State private var pending = 0
    @State private var reviewCount = 0
    @State private var limit = 60
    @State private var showConnection = false
    @State private var searchPresented = false
    private struct Request: Equatable { let catalog: Int; let personal: Int; let audience: ChannelAudience; let query: String; let review: Bool }
    private var request: Request { Request(catalog: store.queryRevision, personal: store.personal.revision, audience: store.organizationAudience, query: query, review: reviewOnly) }
    var body: some View {
        List {
            Section {
                NavigationLink { AISettingsView() } label: { Label("AI Settings", systemImage: "sparkles") }
                if store.organization.run != nil { OrganizationRunStatus() }
                else {
                    Button("Organize My Lineup", systemImage: "sparkles") { store.organizeGroups(limit: 100_000) }
                        .disabled(pending == 0 || !store.intelligence.jevConfigured || !store.personal.value("preferences.cloudAI", default: false))
                        .accessibilityIdentifier("organize-groups")
                }
            } header: { Text("Group Organizer") } footer: {
                Text("Shared titles → category → subcategory. Confident choices are saved and reused after refreshes. Your corrections take priority. Only names and language/region labels are sent; stream addresses and video stay on your device.")
            }
            if reviewCount > 0 {
                Section {
                    Toggle("Needs Review (\(reviewCount))", isOn: $reviewOnly)
                } footer: { Text("None requests a new name from Apple Private Cloud Compute. When unavailable, the group waits here for your correction. New names are reviewed before use.") }
            }
            Section {
                ForEach(rows.prefix(limit)) { group in
                    NavigationLink { OrganizerGroupDetail(group: group) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                            Text(summary(group)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("organizer-group-\(group.id)")
                }
                if rows.count > limit { Button("Show More Groups") { limit += 60 } }
            } header: {
                Text("\(rows.count.formatted()) Channel Groups").accessibilityIdentifier("organizer-result-count").accessibilityValue(String(rows.count))
            }
            Section {
                LabeledContent("New Name Fallback", value: "Apple Private Cloud Compute")
                Text(store.intelligence.pccStatus).font(.footnote).foregroundStyle(.secondary)
                NavigationLink("How Organization Works") { OrganizationHelpView() }
            }
        }
        .navigationTitle("Organizer")
        .searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always))
        .onSubmit(of: .search) { searchPresented = false }
        .sheet(isPresented: $showConnection) { NavigationStack { JevConnectionView() }.presentationDetents([.medium, .large]) }
        .task(id: request) {
            guard let index = store.directory?.nameGroups else { return }
            let request = request
            let values = store.personal.snapshotValues()
            do {
                if !request.query.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
                let result = try await catalogWork {
                    let placements = CatalogGroupIndex.savedPlacements(values)
                    let eligible = index.groups.filter { request.audience.includes(language: $0.language, region: $0.region) }
                    let pending = eligible.filter { placements[$0.id]?.isReusable(for: $0) != true }.count
                    let review = eligible.filter { placements[$0.id].map { $0.status != .classified } ?? false }.count
                    let rows = eligible.filter { group in
                        (!request.review || placements[group.id]?.status != .classified && placements[group.id] != nil) &&
                        (request.query.isEmpty || group.name.localizedCaseInsensitiveContains(request.query) || group.titles.contains { $0.localizedCaseInsensitiveContains(request.query) })
                    }
                    return (rows, pending, review)
                }
                try Task.checkCancellation(); rows = result.0; pending = result.1; reviewCount = result.2; limit = 60
            } catch { }
        }
    }
    private func summary(_ group: CatalogNameGroup) -> String {
        let placement: GroupPlacement? = store.personal.value("taxonomy.placement.\(group.id)", default: nil)
        let path = (placement?.path ?? group.localPath).joined(separator: " › ")
        let status = placement.map { $0.status == .classified ? ($0.manual ? "Your correction" : "Jev") : $0.status == .needsName ? "Needs a name" : "Needs review" } ?? "Not reviewed"
        return ["\(group.channelIDs.count) streams", path, status].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct OrganizerGroupDetail: View {
    @Environment(AppStore.self) private var store
    let group: CatalogNameGroup
    @State private var pathText = ""
    @State private var initialized = false
    @FocusState private var pathFocused: Bool
    @State private var limit = 12
    @State private var titleMatches: [String: String] = [:]
    private var placement: GroupPlacement? { store.personal.value("taxonomy.placement.\(group.id)", default: nil) }
    var body: some View {
        Form {
            Section("Category Path") {
                TextField("Category / Subcategory / League", text: $pathText)
                    .textInputAutocapitalization(.words).autocorrectionDisabled().accessibilityIdentifier("group-path")
                    .focused($pathFocused).submitLabel(.done).onSubmit { pathFocused = false }
                Button("Save Category Path", systemImage: "checkmark") {
                    pathFocused = false
                    store.setGroupPath(group, path: pathText.split(separator: "/", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                }.accessibilityIdentifier("save-group-path")
                Text("Examples: Sports / American Football / NFL, or News / Local. Names are editable; new paths become choices for other groups.").font(.footnote).foregroundStyle(.secondary)
            }
            if let placement {
                Section("Decision") {
                    LabeledContent("Source", value: placement.origin)
                    LabeledContent("Confidence", value: placement.confidence.formatted(.percent.precision(.fractionLength(0))))
                    if placement.status == .needsName {
                        Text(placement.proposedName == nil ? "No suitable choice. Add a name above, or retry after Apple cloud naming becomes available." : "Suggested name: \(placement.proposedName!)")
                        if let name = placement.proposedName {
                            Button("Use \(name)") { store.setGroupPath(group, path: placement.path + [name]) }
                        }
                    }
                    Button("Review Again with Jev") { store.retryGroup(group) }
                }
            }
            Section("Titles in This Group") {
                ForEach(Array(group.titles.prefix(limit)), id: \.self) { title in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                        if let match = titleMatches[title] { Text("Title matches: " + match).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if group.titles.count > limit { Button("Show More Titles") { limit += 30 } }
            }
            Section {
                Text("Grouping keeps every stream. Team and opponent matching uses the latest title and guide time; it does not inherit an old game from this group.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle(group.name)
        .task(id: store.sportsData.metadataRevision) {
            let reference = store.sportsData.reference, titles = group.titles, context = group.providerGroups.joined(separator: " ")
            do {
                let matches = try await catalogWork {
                    let parser = GuideGameParser(reference: reference)
                    var result: [String: String] = [:]
                    for (offset, title) in titles.enumerated() {
                        if offset.isMultiple(of: 64) { try Task.checkCancellation() }
                        if let teams = parser.opponents(title: title, context: context) {
                            result[title] = teams.map(\.name).joined(separator: " vs ")
                        }
                    }
                    return result
                }
                try Task.checkCancellation(); titleMatches = matches
            } catch { }
        }
        .task {
            guard !initialized else { return }; initialized = true
            pathText = (placement?.path ?? group.localPath).joined(separator: " / ")
        }
    }
}

struct JevConnectionView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    var body: some View {
        Form {
            Section {
                LabeledContent("Jev", value: store.intelligence.jevConfigured ? "Key saved on this device" : "Not connected")
                SecureField("Your TypeSafe API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save Key") {
                    do { try store.intelligence.saveJevKey(key); key = ""; dismiss() }
                    catch { store.inform("Couldn’t save key", error.localizedDescription) }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if store.intelligence.jevConfigured { Button("Remove Key", role: .destructive) {
                    do { store.cancelOrganization(); try store.intelligence.removeJevKey() }
                    catch { store.inform("Couldn’t remove key", error.localizedDescription) }
                } }
            } footer: { Text("Your personal key is stored in this device’s Keychain. It is not included in the app, playlist, or iCloud preferences.") }
        }.navigationTitle("Jev Connection")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() }.tint(.primary) } }
    }
}

struct OrganizationHelpView: View {
    var body: some View {
        List {
            Section("Your Content") {
                LabeledContent("Source", value: "Your provider or playlist")
                LabeledContent("Channel Group", value: "Matching names, with all streams retained")
                LabeledContent("Category", value: "Sports, News, or another broad subject")
                LabeledContent("Subcategory", value: "A narrower subject, such as American Football")
                LabeledContent("League", value: "A competition, such as NFL")
                LabeledContent("Team", value: "A participant in a league")
                LabeledContent("Game", value: "Opponents and a scheduled time")
                LabeledContent("Stream", value: "One playable feed for a channel or game")
            }
            Section("Your Choices") {
                LabeledContent("My Lineup", value: "Your language and region filter")
                LabeledContent("Interests", value: "Categories expanded first on Live")
                LabeledContent("Library", value: "Teams and leagues you save")
                LabeledContent("Favorite", value: "A saved item you want to prioritize")
                LabeledContent("Favorites Today", value: "Watchable guide matches now or later today")
            }
            Section("Organization") {
                Text("The app filters by your languages and regions, then groups shared names locally. Jev chooses from the category and subcategory names you manage in AI settings. None leaves a group for review so you can add a suitable name.")
                Text("Refreshes keep saved group decisions. Changed game titles are checked again against the guide. Manual corrections always win.")
            }
        }.navigationTitle("App Terms")
    }
}
