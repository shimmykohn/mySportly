import SwiftUI

struct SearchScreen: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var searchPresented = false
    @State private var groups = SearchGroups()
    @State private var searched = ""
    @State private var limit = 50
    @State private var searchTask: Task<Void, Never>?
    @State private var destination: BrowseDestination?

    private var text: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            if text.isEmpty {
                if !store.recentSearches.isEmpty {
                    Section {
                        ForEach(store.recentSearches, id: \.self) { recent in
                            Button { query = recent } label: { Label(recent, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary) }
                                .accessibilityIdentifier("search-recent-\(recent)")
                        }
                    } header: {
                        HStack {
                            Text("Recent")
                            Spacer()
                            Button("Clear") { store.clearRecentSearches() }.font(.subheadline).textCase(nil)
                        }
                    }
                }
                Section("Browse") { BrowseTiles(query: $query, destination: $destination).listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)) }
            } else if groups.isEmpty && searched == text {
                ContentUnavailableView.search(text: text).accessibilityIdentifier("search-empty")
            } else {
                if !groups.teams.isEmpty {
                    Section("Teams") {
                        ForEach(groups.teams) { team in
                            NavigationLink { TeamPage(team: team) } label: { SportsItemLabel(item: team) }
                        }
                    }
                    .accessibilityIdentifier("search-teams")
                }
                if !groups.liveNow.isEmpty {
                    Section("Live Now") { ForEach(groups.liveNow.prefix(limit)) { SearchResultRow(match: $0) } }
                        .accessibilityIdentifier("search-live")
                }
                if !groups.channels.isEmpty {
                    Section("Channels") {
                        ForEach(groups.channels.prefix(limit)) { SearchResultRow(match: $0) }
                        if groups.channels.count > limit { Button("Show More") { limit += 50 } }
                    }
                    .accessibilityIdentifier("search-channels")
                }
            }
        }
        .navigationTitle("Search")
        .navigationDestination(item: $destination) { destination in
            switch destination {
            case .category(let category): BrowseCategoryView(category: category)
            case .league(let league): LeaguePage(league: league)
            }
        }
        .searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Teams, channels and shows")
        .onChange(of: query) { _, _ in search() }
        .onSubmit(of: .search) { store.addRecentSearch(text) }
        .onChange(of: store.queryRevision) { _, _ in if !text.isEmpty { search() } }
        .onChange(of: store.sportsLinkRevision) { _, _ in if !text.isEmpty { search() } }
        .onAppear { receiveRoute() }
        .onChange(of: store.searchRequest) { _, _ in receiveRoute() }
        .onDisappear { searchTask?.cancel() }
    }

    private func receiveRoute() {
        guard let request = store.searchRequest else { return }
        query = request; store.searchRequest = nil
    }

    /// Local matching only: as-you-type, against the prepared index or, before
    /// it exists, the launch snapshot.
    private func search() {
        searchTask?.cancel()
        let request = text
        limit = 50
        guard !request.isEmpty else { groups = SearchGroups(); searched = ""; return }
        let ignored: Set<String> = ["find", "watch", "show", "me", "the", "a", "now", "tonight", "please", "on", "channel", "channels"]
        let keywords = request.lowercased().split(separator: " ").map(String.init).filter { !ignored.contains($0) }
        let tonight = request.localizedCaseInsensitiveContains("tonight")
        let start = tonight ? max(store.clock, Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: store.clock) ?? store.clock) : store.clock
        let end = tonight ? (Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: store.clock) ?? start + 21_600) : start + 1
        let choices = store.sportsData.index.choices, followed = Set(store.followedTeams.map(\.id)), date = store.clock
        guard let index = store.queryIndex else {
            groups = SearchGrouping.group(query: request, matches: store.snapshotMatches(keywords.isEmpty ? [request] : keywords), choices: choices, followedIDs: followed, at: date)
            searched = request
            return
        }
        let input = CatalogSearchRequest(keywords: keywords.isEmpty ? [request] : keywords, start: start, end: end, audience: store.audience)
        let audience = store.audience
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(120))
                let matches = try await catalogWork { try index.search(input) }
                try Task.checkCancellation()
                var found = SearchGrouping.group(query: request, matches: matches, choices: choices, followedIDs: followed, at: date)
                // Only when local matching found nothing: ask OpenAI what the
                // words mean, then search locally with that. Same place, no button.
                if found.isEmpty, request.split(separator: " ").count >= 2, store.openAI.configured {
                    searched = ""
                    let teams = choices.filter { $0.kind == .team }.map(\.name), leagues = choices.filter { $0.kind == .league }.map(\.name)
                    if let intent = await store.openAI.interpret(request, teams: teams, leagues: leagues, languages: store.languages) {
                        try Task.checkCancellation()
                        let window = Self.window(intent.time, now: date)
                        let interpreted = CatalogSearchRequest(keywords: intent.keywords.flatMap { $0.lowercased().split(separator: " ").map(String.init) },
                                                               start: window.start, end: window.end, language: intent.language ?? "", audience: audience)
                        let aiMatches = try await catalogWork { try index.search(interpreted) }
                        try Task.checkCancellation()
                        found = SearchGrouping.group(query: intent.keywords.first ?? request, matches: aiMatches, choices: choices, followedIDs: followed, at: date)
                    }
                }
                groups = found
                searched = request
            } catch {}
        }
    }
}

extension SearchScreen {
    static func window(_ time: String, now: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        switch time {
        case "tonight":
            let start = max(now, calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now)
            return (start, calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? start + 21_600)
        case "tomorrow":
            let day = calendar.startOfDay(for: now) + 86_400
            return (day, day + 86_400)
        case "weekend":
            let weekend = calendar.isDateInWeekend(now) ? now : (calendar.nextWeekend(startingAfter: now)?.start ?? now)
            return (weekend, weekend + 172_800)
        case "any": return (now, now + 604_800)
        default: return (now, now + 1)
        }
    }
}

private struct SearchResultRow: View {
    let match: CatalogMatch
    var body: some View {
        if let program = match.program {
            NavigationLink { ProgramDetailView(program: program, channel: match.channel) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    ProgramRow(program: program)
                    Text(match.name).font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            PlayableChannelRow(channel: match.channel)
        }
    }
}
