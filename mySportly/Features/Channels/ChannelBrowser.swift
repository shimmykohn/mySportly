import SwiftUI

enum ChannelBrowseGrouping: Sendable { case none, sports, providerLabels }

struct BrowseTaskID: Hashable {
    var revision: Int
    var request: ChannelBrowseRequest
    var preferences: Int = 0
}

@MainActor @Observable final class ChannelBrowser {
    private(set) var channels: [Channel] = []
    private(set) var loading = false
    private(set) var categories: [String] = []
    private(set) var sportsGroups: [SportChannelGroup] = []
    private(set) var ungroupedChannels: [Channel] = []
    private(set) var providerGroups: [ProviderChannelGroup] = []
    private(set) var homeCategories: [CategoryChannelGroup] = []
    private(set) var featuredCategories: [CategoryChannelGroup] = []
    private(set) var otherCategories: [CategoryChannelGroup] = []

    func update(directory: ChannelDirectory?, request: ChannelBrowseRequest, preferences: RecommendationPreferences? = nil, matchingIDs: Set<String>? = nil, grouping: ChannelBrowseGrouping = .none, prepareHome: Bool = false) async {
        guard let directory else { channels = []; categories = []; sportsGroups = []; providerGroups = []; homeCategories = []; featuredCategories = []; otherCategories = []; ungroupedChannels = []; loading = true; return }
        loading = true
        do {
            if !request.query.isEmpty { try await Task.sleep(for: .milliseconds(180)) }
            let result = try await catalogWork {
                let channels = try directory.browse(request, preferences: preferences).filter { matchingIDs?.contains($0.id) ?? true }
                let sports = grouping == .sports ? try directory.groupedSports(in: channels) : (groups: [], remaining: channels)
                let labels = grouping == .providerLabels ? try directory.groupedProviderLabels(in: channels) : (groups: [], remaining: sports.remaining)
                let home = prepareHome ? try directory.homeCategories(in: channels, interests: preferences?.interests ?? []) : []
                return (channels, directory.categories(for: channels), sports.groups, labels, home)
            }
            try Task.checkCancellation()
            channels = result.0; categories = result.1; sportsGroups = result.2; providerGroups = result.3.groups
            ungroupedChannels = result.3.remaining; homeCategories = result.4; loading = false
            featuredCategories = result.4.filter(\.interested); otherCategories = result.4.filter { !$0.interested }
        } catch { /* The next view task owns the results and loading indicator. */ }
    }
}

struct MoreChannelsRow: View {
    let total: Int
    @Binding var limit: Int
    var body: some View {
        if total > limit {
            Button("Show More Channels", systemImage: "plus") { limit += 100 }
            Text("Showing \(min(limit, total)) of \(total) matching channels. Search includes the whole selected lineup.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LineupScopeControl: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        LineupScopePicker().pickerStyle(.menu)
        if store.lineupScope == .preferred {
            Text(summary).font(.caption).foregroundStyle(.secondary)
        } else if store.lineupScope == .unclassified {
            Text("Channels missing a preferred country or language label. Review their details to include them in your lineup.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var summary: String {
        let regions = store.regions.map { Locale.current.localizedString(forRegionCode: $0) ?? $0 }.joined(separator: ", ")
        let languages = store.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }.joined(separator: ", ")
        let choices = [regions, languages].filter { !$0.isEmpty }.joined(separator: " · ")
        return (choices.isEmpty ? "Choose languages and regions in Settings." : choices) +
            (store.audience.includeUnknownLanguage && !store.languages.isEmpty ? " · Unlabeled languages included" : "")
    }
}

struct LineupScopePicker: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Picker("Show", selection: Binding(get: { store.lineupScope }, set: { store.set("preferences.lineupScope", $0.rawValue) })) {
            ForEach(LineupScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("lineup-scope")
    }
}
