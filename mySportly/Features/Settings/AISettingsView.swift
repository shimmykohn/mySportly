import SwiftUI

struct AISettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var pending = 0
    var body: some View {
        Form {
            Section {
                NavigationLink { LocaleSettingsView() } label: {
                    LabeledContent("Languages and Regions", value: scopeLabel)
                }
                NavigationLink { AICategorySettingsView() } label: {
                    LabeledContent("Your Categories", value: "\(store.organizationPaths.count) choices")
                }
                NavigationLink("Interests on Live") { InterestsView() }
            } header: { Text("Your Lineup") } footer: {
                Text("Jev uses your selected regions and languages, including your Unknown Languages setting. Viewing All Channels does not expand AI processing. Your categories define its choices; interests decide what appears first on Live.")
            }
            Section {
                Toggle("Use Jev", isOn: Binding(get: { store.personal.value("preferences.cloudAI", default: false) }, set: { store.set("preferences.cloudAI", $0) }))
                NavigationLink { JevConnectionView() } label: {
                    LabeledContent("Connection", value: store.intelligence.jevConfigured ? "Connected" : "Add API Key")
                }
            } header: { Text("Channel Organization") } footer: {
                Text("The app groups matching channel names first. Jev chooses from your categories, then their subcategories. Only titles, provider folder names, and language/region labels are sent. Your key stays in this device’s Keychain.")
            }
            Section {
                if store.organization.run != nil { OrganizationRunStatus() }
                else {
                    Button("Organize My Lineup", systemImage: "sparkles") { store.organizeGroups(limit: 100_000) }
                        .disabled(pending == 0 || !store.intelligence.jevConfigured || !store.personal.value("preferences.cloudAI", default: false))
                        .accessibilityIdentifier("start-lineup-organization")
                    LabeledContent("New or Changed Groups", value: pending.formatted())
                }
                NavigationLink("Review Results") { OrganizerView() }
            } header: { Text("Progress and Results") } footer: {
                Text("Every completed batch is saved. Refreshes reuse unchanged results. A system Live Activity shows supported background runs; if iOS stops one, reopen the app and tap Resume. Saved decisions sync through your private iCloud account.")
            }
            Section {
                LabeledContent("On-device Search", value: store.intelligence.appleStatus)
                LabeledContent("New Category Names", value: store.intelligence.pccConfigured ? "Apple Cloud" : "Manual Review")
            } header: { Text("Apple Intelligence") } footer: {
                Text("Search interpretation is a separate, optional on-device action. New category suggestions require your approval; unfamiliar groups remain reviewable when cloud naming is unavailable.")
            }
            Section { NavigationLink("How It Works") { OrganizationHelpView() } }
        }
        .navigationTitle("AI")
        .task(id: store.queryRevision) {
            guard let index = store.directory?.nameGroups else { return }
            let audience = store.organizationAudience
            pending = (try? await catalogWork { index.pending(in: audience).count }) ?? 0
        }
    }
    private var scopeLabel: String {
        let regions = store.regions.map { Locale.current.localizedString(forRegionCode: $0) ?? $0 }
        let languages = store.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
        return (regions + languages).joined(separator: ", ")
    }
}

struct AICategorySettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var choosing = false
    var body: some View {
        List {
            Section {
                ForEach(store.organizationPaths, id: \.self) { path in
                    NavigationLink { CategoryPathEditor(original: path) } label: { Text(path.joined(separator: " › ")) }
                }
                .onDelete { indices in
                    var paths = store.organizationPaths; paths.remove(atOffsets: indices)
                    store.set("preferences.organizationPaths", paths)
                }
                Button("Add Category or Subcategory", systemImage: "plus") { adding = true }
                    .accessibilityIdentifier("add-ai-category")
            } header: { Text("Your Choices") } footer: {
                Text("Choose the names and subjects you want. Add a path such as Sports / American Football / NFL. These choices guide new decisions; saved group results stay intact until you change them.")
            }
            Section {
                Button("Choose Starting Categories") { choosing = true }
                Text("When nothing fits, Jev leaves the group for review. You can create a new category there. Favoriting teams or changing Interests affects priority, not the meaning of a category.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Your Categories").toolbar { EditButton() }
        .sheet(isPresented: $adding) { NavigationStack { CategoryPathEditor(original: nil) }.presentationDetents([.medium, .large]) }
        .sheet(isPresented: $choosing) { NavigationStack { CategorySuggestionsView() } }
    }
}

private struct CategorySuggestionsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var chosen = Set<String>()
    var body: some View {
        Form {
            Section {
                ForEach(ChannelCategory.allCases.filter { $0 != .unknown }, id: \.rawValue) { category in
                    Toggle(category.rawValue, isOn: Binding(get: { chosen.contains(category.rawValue) }, set: { value in
                        if value { chosen.insert(category.rawValue) } else { chosen.remove(category.rawValue) }
                    }))
                }
            } footer: { Text("Optional suggestions to start your list. You can rename, remove, or add your own choices afterward.") }
        }
        .navigationTitle("Choose Categories")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let additions = GroupTaxonomy.seedPaths.filter { chosen.contains($0[0]) }
                    store.set("preferences.organizationPaths", Array(Set(store.organizationPaths + additions)).sorted { $0.joined() < $1.joined() })
                    dismiss()
                }.disabled(chosen.isEmpty)
            }
        }
    }
}

private struct CategoryPathEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: [String]?
    @State private var text = ""
    @FocusState private var focused: Bool
    private var path: [String] { text.split(separator: "/", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    private var valid: Bool { !path.isEmpty && path.count <= 4 && path.allSatisfy(GroupNames.validLabel) }
    var body: some View {
        Form {
            Section {
                TextField("Category / Subcategory", text: $text)
                    .focused($focused)
                    .textInputAutocapitalization(.words).autocorrectionDisabled().accessibilityIdentifier("ai-category-path")
            } footer: { Text("Use up to four levels. Existing saved channels are kept when you edit these choices.") }
        }
        .navigationTitle(original == nil ? "Add Category" : "Edit Category")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var choices = store.organizationPaths.filter { $0 != original }
                    let taxonomy = GroupTaxonomy(paths: choices)
                    let canonical = taxonomy.canonical(path)
                    if !choices.contains(canonical) { choices.append(canonical) }
                    store.set("preferences.organizationPaths", choices); dismiss()
                }.disabled(!valid).accessibilityIdentifier("save-ai-category")
            }
            if original == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear { if text.isEmpty { text = original?.joined(separator: " / ") ?? "" } }
        .task { focused = true }
    }
}

/// Progress observes only the small run model, keeping channel rows out of its
/// update boundary. Native ProgressView also supports VoiceOver and Dynamic Type.
struct OrganizationRunStatus: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let progress = store.organization
        if progress.run != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(progress.isRunning ? "Organizing channels" : "Organization paused").font(.subheadline)
                    Spacer()
                    if progress.isRunning {
                        Button("Pause") { store.cancelOrganization() }.accessibilityIdentifier("pause-organization")
                    } else {
                        Button("Resume") { store.resumeOrganization() }.accessibilityIdentifier("resume-organization")
                    }
                }
                ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                    .accessibilityIdentifier("organization-progress")
                    .accessibilityValue("\(progress.completed) of \(progress.total)\(progress.backgroundActive ? ", background running" : "")")
                Text(progress.countLabel).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("organization-progress-count")
            }
        }
    }
}

