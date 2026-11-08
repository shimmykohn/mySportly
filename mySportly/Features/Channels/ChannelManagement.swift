import SwiftUI

struct ChannelListView: View {
    @Environment(AppStore.self) private var store
    var favoritesOnly = false
    var initialCategory = "All"
    var followsLineup = false
    @State private var category = "All"
    @State private var query = ""
    @State private var showHidden = false
    @State private var selected = Set<String>()
    @State private var editMode = EditMode.inactive
    @State private var createGroup = false
    @State private var browser = ChannelBrowser()
    @State private var limit = 100
    private var request: ChannelBrowseRequest {
        var request = ChannelBrowseRequest()
        request.query = query; request.category = category
        request.includeHidden = showHidden; request.favoritesOnly = favoritesOnly
        if followsLineup { request.audience = store.audience }
        return request
    }
    var body: some View {
        List(selection: $selected) {
            Section {
                if followsLineup { LineupScopeControl() }
                Picker("Category", selection: $category) { Text("All").tag("All"); ForEach((store.directory?.categories ?? []).filter { $0 != "All" }, id: \.self) { Text($0).tag($0) } }
                Toggle("Include Hidden Channels", isOn: $showHidden)
            }
            if browser.loading { ProgressView("Finding channels…") }
            Section("\(browser.channels.count) Channels") {
                ForEach(browser.channels.prefix(limit)) { channel in NavigationLink { ChannelDetailView(channel: channel) } label: { ChannelRow(channel: channel, showProgram: false) }.tag(channel.id) }
                    .onMove { from, to in var values = browser.channels; values.move(fromOffsets: from, toOffset: to); store.reorder(values) }
                MoreChannelsRow(total: browser.channels.count, limit: $limit)
            }
        }
        .environment(\.editMode, $editMode)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always)).navigationTitle(favoritesOnly ? "Favorites" : "Channels")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(editMode.isEditing ? "Done" : "Edit") { editMode = editMode.isEditing ? .inactive : .active } }
            if !selected.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Menu("\(selected.count) Selected", systemImage: "ellipsis.circle") {
                        Button("Favorite", systemImage: "star") { store.bulk(selected, field: "favorite", value: true); selected.removeAll() }
                        Button("Hide", systemImage: "eye.slash") { store.bulk(selected, field: "hidden", value: true); selected.removeAll() }
                        Button("Unhide", systemImage: "eye") { store.bulk(selected, field: "hidden", value: false); selected.removeAll() }
                        Button("Create Group", systemImage: "folder.badge.plus") { createGroup = true }
                    }
                }
            }
        }
        .sheet(isPresented: $createGroup) { NavigationStack { GroupEditor(initialIDs: Array(selected)) } }
        .task { category = initialCategory }
        .task(id: BrowseTaskID(revision: store.queryRevision, request: request)) {
            limit = 100
            await browser.update(directory: store.directory, request: request)
        }
    }
}

struct ChannelDetailView: View {
    @Environment(AppStore.self) private var store
    let channel: Channel
    @State private var rename = ""
    @State private var language = ""
    @State private var region = ""
    @State private var category = ""
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                ChannelRow(channel: channel)
                Button("Watch Now", systemImage: "play.fill") { store.play(channel) }
                LibrarySaveButton(item: store.bookmark(channel))
                Toggle("Favorite", isOn: Binding(get: { store.flag(channel, "favorite") }, set: { store.set(store.key(channel, "favorite"), $0) }))
                Toggle("Hidden", isOn: Binding(get: { store.flag(channel, "hidden") }, set: { store.set(store.key(channel, "hidden"), $0) }))
            }
            Section("Your Channel Details") {
                NavigationLink("Where These Details Come From") { ChannelDataOriginView(channel: channel) }
                TextField("Display Name", text: $rename).onSubmit { store.edit(channel, field: "name", value: rename) }
                Picker("Category", selection: $category) {
                    Text(store.category(channel)).tag(store.category(channel))
                    ForEach(Array(Set(ChannelCategory.allCases.map(\.rawValue) + store.categories)).filter { $0 != store.category(channel) }.sorted(), id: \.self) { Text($0).tag($0) }
                }
                TextField("Language Code (for example, en)", text: $language).textInputAutocapitalization(.never)
                TextField("Region Code (for example, US)", text: $region).textInputAutocapitalization(.characters)
                Button("Save Corrections") {
                    store.edit(channel, fields: ["name": rename, "category": category, "language": LocalePreferences.languageCode(language), "region": region.uppercased()])
                }
                Text("Your changes take priority over organizer suggestions and provider refreshes.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Stream Options") {
                Picker("Preferred Variant", selection: Binding(get: { store.personal.value(store.key(channel, "preferredVariant"), default: channel.id) }, set: { store.set(store.key(channel, "preferredVariant"), $0) })) {
                    ForEach(store.variants(of: channel)) { Text($0.name).tag($0.id) }
                }
                if store.variants(of: channel).count > 1 {
                    Button("Separate These Variants") { store.splitVariants(of: channel) }
                } else {
                    Toggle("Keep This Feed Separate", isOn: Binding(get: { store.flag(channel, "manual.variants") }, set: { store.set(store.key(channel, "manual.variants"), $0) }))
                }
                LabeledContent("Original Name", value: channel.name)
                LabeledContent("Provider Group", value: channel.group.isEmpty ? "Unspecified" : channel.group)
                LabeledContent("Channel Language", value: store.language(channel).isEmpty ? "Unknown" : (Locale.current.localizedString(forLanguageCode: store.language(channel)) ?? store.language(channel)))
                LabeledContent("Channel Region", value: store.region(channel).isEmpty ? "Unknown" : (Locale.current.localizedString(forRegionCode: store.region(channel)) ?? store.region(channel)))
                if let details = store.directory?.metadata[channel.id] { Text(details.reason + " Your corrections take priority.").font(.footnote).foregroundStyle(.secondary) }
                NavigationLink("Guide Mapping and Time") { GuideMappingView(channel: channel) }
            }
            Section("Coming Up") {
                ForEach(store.programs(for: channel).filter { $0.end > store.clock }.prefix(12)) { program in
                    NavigationLink { ProgramDetailView(program: program, channel: channel) } label: { ProgramRow(program: program) }
                }
                if store.programs(for: channel).isEmpty { Text("No guide is mapped to this channel.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(store.name(channel)).navigationBarTitleDisplayMode(.inline)
        .task { guard !loaded else { return }; loaded = true; rename = store.name(channel); language = store.language(channel); region = store.region(channel); category = store.category(channel) }
    }
}

struct GroupsView: View {
    @Environment(AppStore.self) private var store
    @State private var add = false
    var body: some View {
        List {
            ForEach(store.groups) { group in
                NavigationLink { GroupDetailView(groupID: group.id) } label: { LabeledContent(group.name, value: "\(group.channelIDs.count)") }
                    .swipeActions { Button("Delete", role: .destructive) { store.remove("group.\(group.id)") } }
            }
            if store.groups.isEmpty { ContentUnavailableView("Create Your Own Lineup", systemImage: "folder", description: Text("Group any channels together, such as Weekend or Family.")) }
        }
        .navigationTitle("Groups").toolbar { Button("Add Group", systemImage: "plus") { add = true } }
        .sheet(isPresented: $add) { NavigationStack { GroupEditor() } }
    }
}

struct GroupDetailView: View {
    @Environment(AppStore.self) private var store
    let groupID: UUID
    @State private var editing = false
    @State private var limit = 100
    var group: ChannelGroup? { store.groups.first { $0.id == groupID } }
    var body: some View {
        List { if let group {
            ForEach(group.channelIDs.prefix(limit).compactMap { store.channelIndex[$0] }) { PlayableChannelRow(channel: $0) }
            MoreChannelsRow(total: group.channelIDs.count, limit: $limit)
        } }
            .navigationTitle(group?.name ?? "Group")
            .toolbar { Button("Edit") { editing = true } }
            .sheet(isPresented: $editing) { if let group { NavigationStack { GroupEditor(group: group) } } }
    }
}

struct GroupEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var group: ChannelGroup?
    var initialIDs: [String] = []
    @State private var name = ""
    @State private var ids = Set<String>()
    @State private var query = ""
    @State private var loaded = false
    @State private var browser = ChannelBrowser()
    @State private var limit = 100
    private var request: ChannelBrowseRequest {
        var request = ChannelBrowseRequest(); request.query = query; request.includeHidden = true; return request
    }
    var body: some View {
        List {
            Section { TextField("Group Name", text: $name) }
            Section("\(ids.count) Channels Selected") {
                if browser.loading { ProgressView("Finding channels…") }
                ForEach(browser.channels.prefix(limit)) { channel in
                    Toggle(isOn: Binding(get: { ids.contains(channel.id) }, set: { if $0 { ids.insert(channel.id) } else { ids.remove(channel.id) } })) { ChannelRow(channel: channel, showProgram: false) }
                }
                MoreChannelsRow(total: browser.channels.count, limit: $limit)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always)).navigationTitle(group == nil ? "New Group" : "Edit Group")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") {
                let updated = ChannelGroup(id: group?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespaces), channelIDs: store.channels.map(\.id).filter { ids.contains($0) })
                store.set("group.\(updated.id)", updated); dismiss()
            }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .task { guard !loaded else { return }; loaded = true; name = group?.name ?? ""; ids = Set(group?.channelIDs ?? initialIDs) }
        .task(id: BrowseTaskID(revision: store.queryRevision, request: request)) {
            limit = 100
            await browser.update(directory: store.directory, request: request)
        }
    }
}
