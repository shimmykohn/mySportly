import SwiftUI

struct GuideStatusView: View {
    @Environment(AppStore.self) private var store
    @State private var coverage = GuideCoverage()
    @State private var loading = true
    private struct Request: Equatable { let revision: Int; let date: Date; let audience: ChannelAudience }
    var body: some View {
        List {
            Section {
                LineupScopeControl()
                Text("Xtream sources import their provider’s EPG automatically. A separate XMLTV URL is optional and replaces that source’s guide.").font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Checking saved guide…") }
            Section("Selected Lineup") {
                LabeledContent("Channels") { Text(coverage.channels.formatted()).accessibilityIdentifier("guide-status-channels").accessibilityValue(String(coverage.channels)) }
                LabeledContent("Matched to Guide Listings") { Text(coverage.matched.formatted()).accessibilityIdentifier("guide-status-matched").accessibilityValue(String(coverage.matched)) }
                LabeledContent("Matched Automatically on This Device", value: coverage.automatic.formatted())
                LabeledContent("Showing a Program Now", value: coverage.onNow.formatted())
                LabeledContent("Unknown Channel Language", value: coverage.unknownLanguage.formatted())
            }
            Section {
                LabeledContent("Missing Guide ID", value: coverage.missingID.formatted())
                LabeledContent("ID Has No Saved Listings", value: coverage.unmatchedID.formatted())
                LabeledContent("No Remaining Guide Listings", value: coverage.noUpcoming.formatted())
                Text("A guide end time does not confirm that a game or stream has stopped.").font(.footnote).foregroundStyle(.secondary)
                Text("Missing IDs are matched locally using unique channel names, country and exact local station call signs. Ambiguous matches stay unassigned. No AI is used. For a correction, open Channel Details → Guide Mapping and Time.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Needs Attention") }
            Section("Sources") {
                ForEach(store.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name).font(.headline)
                        if let date = store.catalog.guideRefreshed[source.id] {
                            Text("Guide imported \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        } else { Text("No successful guide import recorded.").foregroundStyle(.secondary) }
                        Button("Refresh \(source.name)") { store.refresh(source) }.disabled(store.importingSource != nil)
                    }
                }
                Text("These counts use the saved guide. Refresh contacts your provider and downloads updated channels and listings.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("TV Guide Status")
        .task(id: Request(revision: store.queryRevision, date: store.clock, audience: store.audience)) {
            loading = true
            guard let index = store.queryIndex else { return }
            let date = store.clock, audience = store.audience
            do {
                let result = try await catalogWork { try index.coverage(at: date, audience: audience) }
                try Task.checkCancellation()
                coverage = result; loading = false
            } catch { }
        }
    }
}
