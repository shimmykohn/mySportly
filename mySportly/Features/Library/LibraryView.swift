import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var filter = "All"
    private var items: [LibraryBookmark] {
        store.savedLibraryItems.filter {
            (filter == "All" || (filter == "Favorites" ? store.isLibraryFavorite($0) : $0.kind.rawValue == filter)) &&
            (query.isEmpty || $0.name.localizedStandardContains(query))
        }
    }
    var body: some View {
        @Bindable var store = store
        List {
            if items.isEmpty {
                if !query.isEmpty { ContentUnavailableView.search(text: query) }
                else { ContentUnavailableView("Save What You Watch", systemImage: "square.stack", description: Text("Add channels, categories, teams, or leagues with Add to Library. Star your favorites to keep them at the top.")) }
            } else {
                Section {
                    ForEach(items) { LibraryBookmarkRow(item: $0) }
                }
            }
            if query.isEmpty {
                Section {
                    NavigationLink { RecordingsView() } label: { Label("Recordings", systemImage: "record.circle") }
                    NavigationLink { RemindersView() } label: { Label("Reminders", systemImage: "bell") }
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your Library")
        .navigationDestination(item: $store.libraryRoute) { LibraryBookmarkDestination(item: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Show", selection: $filter) {
                        Text("All").tag("All"); Text("Favorites").tag("Favorites")
                        ForEach(LibraryBookmark.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                    }
                } label: { Label("Filter Library", systemImage: "line.3.horizontal.decrease") }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { AddToLibraryView() } label: { Label("Add to Library", systemImage: "plus") }.accessibilityIdentifier("add-to-library")
            }
        }
        .appToolbar()
    }
}

struct LibraryBookmarkRow: View {
    @Environment(AppStore.self) private var store
    let item: LibraryBookmark
    var body: some View {
        NavigationLink { LibraryBookmarkDestination(item: item) } label: {
            HStack {
                if item.kind == .team || item.kind == .league {
                    SportsLibraryLabel(item: SportsLibraryItem(name: item.reference, kind: item.kind == .team ? .team : .league))
                } else {
                    Label { VStack(alignment: .leading) { Text(item.name); Text(item.kind.rawValue).font(.caption).foregroundStyle(.secondary) } }
                        icon: { Image(systemName: item.kind.symbol) }
                }
                Spacer()
                if store.isLibraryFavorite(item) { Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("Favorite") }
            }
        }
        .accessibilityIdentifier("library-item-\(item.name)")
        .swipeActions(edge: .leading) { Button(store.isLibraryFavorite(item) ? "Unfavorite" : "Favorite", systemImage: "star") { store.setLibraryFavorite(item, !store.isLibraryFavorite(item)) }.tint(.orange) }
        .swipeActions { Button("Remove", role: .destructive) { store.removeLibraryItem(item) } }
        .contextMenu {
            Button(store.isLibraryFavorite(item) ? "Remove Favorite" : "Favorite", systemImage: "star") { store.setLibraryFavorite(item, !store.isLibraryFavorite(item)) }
            Button("Remove from Library", role: .destructive) { store.removeLibraryItem(item) }
        }
    }
}

struct LibraryBookmarkDestination: View {
    @Environment(AppStore.self) private var store
    let item: LibraryBookmark
    var body: some View {
        switch item.kind {
        case .channel:
            if let channel = store.channelIndex[item.reference] { ChannelDetailView(channel: channel) }
            else { ContentUnavailableView("Channel Unavailable", systemImage: "tv", description: Text("This saved channel is missing from the current playlist. Your saved item is kept for the next refresh.")) }
        case .category: TaxonomyChannelsView(path: item.path)
        case .channelGroup: TaxonomyChannelsView(path: [], nameGroup: item.reference)
        case .team, .league: SportsLibraryItemView(item: SportsLibraryItem(name: item.reference, kind: item.kind == .team ? .team : .league))
        case .collection:
            if let id = UUID(uuidString: item.reference) { GroupDetailView(groupID: id) }
        }
    }
}

struct LibrarySaveButton: View {
    @Environment(AppStore.self) private var store
    let item: LibraryBookmark
    var body: some View {
        Button(store.hasLibraryItem(item) ? "Remove from Library" : "Add to Library", systemImage: store.hasLibraryItem(item) ? "checkmark" : "plus") {
            if store.hasLibraryItem(item) { store.removeLibraryItem(item) } else { store.saveLibraryItem(item) }
        }.accessibilityIdentifier("save-library-item")
    }
}

struct AddToLibraryView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        List {
            Section {
                NavigationLink { ChannelListView() } label: { Label("Channels", systemImage: "tv") }
                NavigationLink { SportsFollowingView() } label: { Label("Teams & Leagues", systemImage: "sportscourt") }
                NavigationLink { GroupsView() } label: { Label("Your Collections", systemImage: "folder") }
            }
            Section("Categories") { ForEach(store.categories, id: \.self) { category in
                NavigationLink { CategoryChannelsView(category: category) } label: { Text(category) }
            } }
        }.navigationTitle("Add to Library")
    }
}

struct RecordingsView: View {
    @Environment(AppStore.self) private var store
    @State private var deleting: RecordingItem?
    var body: some View {
        List {
            Section { Text("Recordings are stored on this device. Recording stops when the app leaves the foreground.").font(.footnote).foregroundStyle(.secondary) }
            if store.recorder.items.isEmpty { ContentUnavailableView("No Recordings", systemImage: "record.circle", description: Text("Start a supported recording from the player.")) }
            ForEach(store.recorder.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline)
                    Text(item.channelName).foregroundStyle(.secondary)
                    Text(item.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    Text("\(item.status) · \(Duration.seconds(item.duration).formatted(.time(pattern: .hourMinuteSecond))) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                    if !item.detail.isEmpty { Text(item.detail).font(.footnote) }
                    if item.id == store.recorder.activeID { Button("Stop Recording") { Task { await store.recorder.stop() } } }
                    else if item.duration > 0 { Button("Play Recording", systemImage: "play") { Task { do { try await store.playback.playRecording(item); store.showPlayer = true } catch { store.inform("Recording unavailable", "Saved video could not be opened.") } } } }
                }
                .swipeActions { if item.id != store.recorder.activeID { Button("Delete", role: .destructive) { deleting = item } } }
            }
            if let error = store.recorder.errorMessage { Section { Text(error).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Recordings")
        .confirmationDialog("Delete this recording?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let item = deleting { Button("Delete Recording", role: .destructive) { do { try store.recorder.delete(item); deleting = nil } catch { store.inform("Couldn’t delete", error.localizedDescription) } } }
        }
    }
}

struct RemindersView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: ProgramReminder?
    var body: some View {
        List {
            if store.reminders.permission == .denied { Section { Text("Notifications are disabled. Enable them for mySportly in device Settings."); Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } } }
            if store.reminders.reminders.isEmpty { ContentUnavailableView("No Reminders", systemImage: "bell", description: Text("Open an upcoming program in Guide or Sports to set one.")) }
            ForEach(store.reminders.reminders) { reminder in
                Button { editing = reminder } label: {
                    VStack(alignment: .leading, spacing: 4) { Text(reminder.title).font(.headline); Text(reminder.channelName); Text(reminder.fireDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }.buttonStyle(.plain).swipeActions { Button("Cancel", role: .destructive) { Task { await store.reminders.cancel(reminder.id) } } }
            }
        }
        .navigationTitle("Reminders").task { await store.reminders.reload() }
        .sheet(item: $editing) { reminder in ReminderEditor(reminder: reminder) }
    }
}
private struct ReminderEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let reminder: ProgramReminder
    @State private var date = Date.now
    var body: some View {
        NavigationStack {
            Form { Text(reminder.title); DatePicker("Notify Me", selection: $date, in: Date.now...) }
                .navigationTitle("Edit Reminder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { do { try await store.reminders.reschedule(reminder, date: date); dismiss() } catch { store.inform("Reminder unavailable", error.localizedDescription) } } } }
                }
                .task { date = reminder.fireDate }
        }
    }
}
