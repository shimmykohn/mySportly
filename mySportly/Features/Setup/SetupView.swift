import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        NavigationStack {
            List {
                SourceImportProgressSection()
                Section {
                    Label("Live TV, your way", systemImage: "play.tv").font(.title3.bold())
                    Text("Connect your source, choose what matters to you, and turn a crowded catalog into your own lineup.")
                }
                Section("Make It Yours") {
                    NavigationLink { LocaleSettingsView() } label: { Label("Region and Language", systemImage: "globe") }
                    NavigationLink { InterestsView() } label: { Label("Interests", systemImage: "heart") }
                    Text("Suggested from this device. Change these any time; channels outside your preferences stay available.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink { SourceForm() } label: { Label("Connect a Source", systemImage: "plus.circle") }
                    Button("Explore Sample Catalog", systemImage: "play.rectangle") { Task { await store.loadDemo(); store.showSetup = false } }
                } footer: { Text("No mySportly account. Your provider connection stays in Keychain. iCloud uses your existing Apple Account when available.") }
            }
            .navigationTitle("Welcome").toolbarTitleDisplayMode(.inline)
            .toolbar { if !store.sources.isEmpty || store.demo { ToolbarItem(placement: .confirmationAction) { Button("Done") { store.set("setup.complete", true); store.showSetup = false } } } }
        }
    }
}

struct SourceForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var source: TVSource?
    @State private var name = ""
    @State private var kind: SourceKind = .xtream
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var guide = ""
    @State private var output = "m3u8"
    @State private var limit = 1
    @State private var filePicker = false
    @State private var readingFile = false
    @State private var playlist: String?
    @State private var importedFilename: String?
    @State private var isFile = false
    @State private var error: String?
    @State private var loaded = false
    var body: some View {
        Form {
            Section("Source") {
                TextField("Name", text: $name)
                Picker("Connection", selection: $kind) { Text("Xtream Codes").tag(SourceKind.xtream); Text("M3U Playlist").tag(SourceKind.m3u) }.disabled(source != nil)
                if !isFile { TextField(kind == .xtream ? "Server URL" : "Playlist URL", text: $address).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if kind == .xtream {
                    TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    Picker("Stream Format", selection: $output) { Text("HLS (.m3u8)").tag("m3u8"); Text("MPEG-TS (.ts)").tag("ts") }
                } else {
                    Button(importedFilename ?? "Import M3U File", systemImage: "doc") { filePicker = true }.disabled(readingFile)
                    if readingFile { ProgressView("Reading playlist…") }
                    if isFile { Button("Use URL Instead") { isFile = false; playlist = nil; importedFilename = nil } }
                }
            }
            Section {
                TextField("Optional XMLTV URL", text: $guide).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("TV Guide") } footer: {
                Text(kind == .xtream ? "Leave blank to use your Xtream provider’s guide automatically. Enter a URL only to replace that guide." : "Leave blank to use the guide linked in your playlist, if supplied. Otherwise add an XMLTV URL.")
            }
            Section { Stepper("Allowed connections: \(limit)", value: $limit, in: 1...8) } footer: { Text("Use the limit in your provider subscription. Xtream may supply it automatically. Multiview and recording use additional connections.") }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            Section { Button(source == nil ? "Connect and Import" : "Save and Refresh", systemImage: "arrow.down.circle") { connect() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || store.importingSource != nil || readingFile) } footer: { Text("Connection details and token-bearing URLs are stored securely. Playback and recording depend on the formats your provider supplies.") }
        }
        .navigationTitle(source == nil ? "Add Source" : source!.name)
        .task { load() }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [UTType(filenameExtension: "m3u") ?? .plainText, UTType(filenameExtension: "m3u8") ?? .plainText, .plainText]) { result in
            do {
                let url = try result.get()
                readingFile = true
                Task {
                    defer { readingFile = false }
                    do {
                        let text = try await Task.detached(priority: .userInitiated) {
                            let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 64 * 1024 * 1024 else { throw CatalogError.tooLarge }
                            return try String(contentsOf: url, encoding: .utf8)
                        }.value
                        playlist = text; importedFilename = url.lastPathComponent; isFile = true
                        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                    } catch { self.error = store.safeError(error) }
                }
            } catch { self.error = store.safeError(error) }
        }
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        guard let source else { return }
        name = source.name; kind = source.kind; limit = source.connectionLimit
        do { if let secrets = try KeychainStore.credentials(source.id) { address = secrets.address; username = secrets.username; password = secrets.password; guide = secrets.guideAddress; output = secrets.output; isFile = secrets.isFile; if isFile { importedFilename = "Saved playlist file" } } }
        catch { self.error = error.localizedDescription }
    }
    private func connect() {
        do {
            if !isFile { _ = try HTTPClient.url(address) }
            if !guide.isEmpty { _ = try HTTPClient.url(guide) }
            if kind == .xtream && (username.isEmpty || password.isEmpty) { error = "Enter the provider username and password."; return }
            var source = source ?? TVSource(name: name, kind: kind)
            source.name = name.trimmingCharacters(in: .whitespaces); source.connectionLimit = limit; source.host = URL(string: address)?.host ?? "Imported file"
            store.connect(source, secrets: SourceSecrets(address: address, username: username, password: password, guideAddress: guide, output: output, isFile: isFile), playlist: playlist)
            dismiss()
        } catch { self.error = store.safeError(error) }
    }
}

struct SourcesView: View {
    @Environment(AppStore.self) private var store
    @State private var remove: TVSource?
    var body: some View {
        List {
            SourceImportProgressSection()
            ForEach(store.sources) { source in
                NavigationLink { SourceForm(source: source) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name).font(.headline)
                        Text("\(store.sourceChannelCounts[source.id, default: 0]) channels · \(source.host)").font(.subheadline).foregroundStyle(.secondary)
                        if let date = store.catalog.refreshed[source.id] {
                            Text("Updated \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("source-refresh-date")
                                .accessibilityValue(date.formatted(.iso8601))
                        }
                    }
                }
                .swipeActions { Button("Remove", role: .destructive) { remove = source }; Button("Refresh", systemImage: "arrow.clockwise") { store.refresh(source) } }
            }
            NavigationLink { SourceForm() } label: { Label("Add Source", systemImage: "plus") }
        }
        .navigationTitle("Sources")
        .confirmationDialog("Remove this source?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible) {
            if let source = remove { Button("Remove \(source.name)", role: .destructive) { Task { await store.removeSource(source); remove = nil } } }
        } message: { Text("This removes the catalog and connection details.") }
    }
}
