import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Form {
            Section {
                NavigationLink { SourcesView() } label: { Label("Sources", systemImage: "antenna.radiowaves.left.and.right") }
                NavigationLink { LocaleSettingsView() } label: { Label("Region and Language", systemImage: "globe") }
                Picker("Appearance", selection: preference("preferences.appearance", fallback: "System")) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0) } }
            }
            Section("iCloud") {
                Toggle("Sync Personal Choices", isOn: Binding(get: { store.personal.cloudRequested }, set: { store.personal.requestCloudSync($0) }))
                if store.personal.syncChangeNeedsRelaunch { Label("Takes effect the next time you open the app.", systemImage: "info.circle").font(.footnote) }
                Text(store.personal.cloudStatus).foregroundStyle(.secondary)
            }
            Section { NavigationLink { OpenAIKeyView() } label: { Label("OpenAI", systemImage: "sparkles") }.accessibilityIdentifier("openai-settings") }
            Section { NavigationLink { AcknowledgementsView() } label: { Label("Acknowledgements", systemImage: "doc.text") } }
        }
        .navigationTitle("Settings")
    }
    private func preference<T: Codable>(_ key: String, fallback: T) -> Binding<T> { Binding(get: { store.personal.value(key, default: fallback) }, set: { store.set(key, $0) }) }
}

struct LocaleSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var addLanguage = false
    @State private var addRegion = false
    var body: some View {
        List {
            Section {
                LineupScopeControl()
                Toggle("Include Unknown Languages", isOn: Binding(get: { store.audience.includeUnknownLanguage }, set: { store.set("preferences.includeUnknownLanguage", $0) }))
            } header: { Text("Your Everyday Lineup") } footer: {
                Text("My Lineup filters Live, Guide, Sports, and Search by your selected regions and languages. A known different language is excluded. Unknown languages can be included when the region matches; an unknown region stays in Unclassified. Choose All Channels in the filter menu to browse everything. Your saved Library remains available.")
            }
            Section {
                ForEach(store.languages, id: \.self) { Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
                    .onMove { from, to in var values = store.languages; values.move(fromOffsets: from, toOffset: to); store.set("preferences.languages", values) }
                    .onDelete { indices in var values = store.languages; values.remove(atOffsets: indices); store.set("preferences.languages", values) }
                Button("Add Language") { addLanguage = true }
            } header: { Text("Preferred Channel Languages") } footer: { Text("Order languages by preference. This does not prove which audio tracks a stream supplies.") }
            Section("Preferred Regions") {
                ForEach(store.regions, id: \.self) { Text(Locale.current.localizedString(forRegionCode: $0) ?? $0) }
                    .onDelete { indices in var values = store.regions; values.remove(atOffsets: indices); store.set("preferences.regions", values) }
                Button("Add Region") { addRegion = true }
                Text("Regions describe channel editions, not your GPS location. English alone does not mean United States.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Playback") {
                Picker("Preferred Audio", selection: Binding(get: { store.personal.value("preferences.audioLanguage", default: store.languages.first ?? "en") }, set: { store.set("preferences.audioLanguage", $0) })) {
                    ForEach(Array(Set(store.languages + ["en"])).sorted(), id: \.self) { Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0).tag($0) }
                }
            }
        }
        .navigationTitle("Region and Language").toolbar { EditButton() }
        .sheet(isPresented: $addLanguage) { CodePicker(title: "Add Language", codes: Locale.LanguageCode.isoLanguageCodes.map(\.identifier), label: { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }) { code in if !store.languages.contains(code) { store.set("preferences.languages", store.languages + [code]) } } }
        .sheet(isPresented: $addRegion) { CodePicker(title: "Add Region", codes: Locale.Region.isoRegions.map(\.identifier), label: { Locale.current.localizedString(forRegionCode: $0) ?? $0 }) { code in if !store.regions.contains(code) { store.set("preferences.regions", store.regions + [code]) } } }
    }
}

struct CodePicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String; let codes: [String]; let label: (String) -> String; let choose: (String) -> Void
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(codes.filter { search.isEmpty || label($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search) }.sorted { label($0) < label($1) }, id: \.self) { code in
                Button(label(code)) { choose(code); dismiss() }.foregroundStyle(.primary)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always)).navigationTitle(title).toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct InterestsView: View {
    @Environment(AppStore.self) private var store
    private var categories: [String] {
        Array(Set(ChannelCategory.allCases.filter { $0 != .unknown }.map(\.rawValue) + store.categories.filter { $0 != "Unsorted" })).sorted()
    }
    var body: some View {
        Form {
            Section { NavigationLink("Teams and Leagues") { FollowPicker() } }
            Section("Interests") {
                ForEach(categories, id: \.self) { category in
                    Toggle(category, isOn: Binding(get: { store.interests.contains(category) }, set: { include in
                        store.set("preferences.interests", include ? Array(Set(store.interests + [category])).sorted() : store.interests.filter { $0 != category })
                    })).accessibilityIdentifier("interest-\(category)")
                }
            }
        }.navigationTitle("Interests and Sports")
    }
}
