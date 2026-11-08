import SwiftUI

struct RefreshSettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Form {
            Section {
                Picker("Playlist", selection: frequency("preferences.playlistRefresh", fallback: .daily)) {
                    ForEach(RefreshFrequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("playlist-refresh-frequency")
                Picker("TV Guide", selection: frequency("preferences.guideRefresh", fallback: .sixHours)) {
                    ForEach(RefreshFrequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.accessibilityIdentifier("guide-refresh-frequency")
            } footer: {
                Text("iOS chooses when background updates run. Opening the app also checks for overdue updates. A playlist update includes its guide; a guide update keeps your channels and saved organization.")
            }
            Section {
                Button("Refresh Now", systemImage: "arrow.clockwise") { Task { await store.refreshDueSources(force: true) } }
                    .disabled(store.importProgress != nil || store.refreshBatchRunning || store.demo)
                if let message = store.refreshMessage { Text(message).foregroundStyle(.secondary) }
            }
            ForEach(store.sources) { source in
                Section(source.name) {
                    LabeledContent("Playlist Updated", value: formatted(store.lastRefresh(source, kind: .playlist)))
                    LabeledContent("Guide Updated", value: formatted(store.lastRefresh(source, kind: .guide)))
                }
            }
        }.navigationTitle("Automatic Refresh")
    }
    private func formatted(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet" }
    private func frequency(_ key: String, fallback: RefreshFrequency) -> Binding<RefreshFrequency> {
        Binding(get: { RefreshFrequency(rawValue: store.personal.value(key, default: fallback.rawValue)) ?? fallback },
                set: { store.set(key, $0.rawValue); store.scheduleSourceRefresh() })
    }
}
