import SwiftUI

struct SearchScreen: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var searchPresented = false
    @State private var results: [CatalogMatch] = []
    @State private var visibleLimit = 100
    @State private var status = "Search channel names and TV guide listings."
    @State private var busy = false
    @State private var interpreting = false
    @State private var lineupRequest = false
    @State private var searchTask: Task<Void, Never>?
    @State private var generation = UUID()

    var body: some View {
        List {
            Section {
                LineupScopeControl()
                Text(status).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("search-status")
                if busy { ProgressView(interpreting ? "Interpreting your request…" : "Searching your saved lineup…") }
                if !query.isEmpty {
                    Button("Ask Apple Intelligence", systemImage: "sparkles") { search(usingAI: true) }
                        .disabled(busy || !store.intelligence.appleAvailable)
                }
            }
            if query.isEmpty {
                Section("Try a Search") {
                    ForEach(["basketball now", "news tonight", "English movies"], id: \.self) { suggestion in Button(suggestion) { query = suggestion } }
                }
            } else if results.isEmpty && !busy {
                ContentUnavailableView.search(text: query).accessibilityIdentifier("search-empty")
            }
            else if !results.isEmpty {
                Section {
                    ForEach(results.prefix(visibleLimit)) { SearchResultRow(match: $0) }
                    if results.count > visibleLimit {
                        Button("Show More Results", systemImage: "plus") { visibleLimit += 100 }
                        Text("Showing \(min(visibleLimit, results.count)) of \(results.count) channels. Refine your search to narrow the results.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("\(results.count) Matching Channels")
                        .accessibilityIdentifier("search-result-count").accessibilityValue(String(results.count))
                }
            }
        }
        .navigationTitle("Search").searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Channels, programs, or what to watch")
        .onChange(of: query) { _, _ in search(usingAI: false) }
        // Return submits a fast local search. Language-model interpretation is
        // explicit so opening Search or submitting a keyword never waits on AI.
        .onSubmit(of: .search) { searchPresented = false; search(usingAI: false) }
        .onChange(of: store.queryRevision) { _, _ in search(usingAI: false) }
        .onChange(of: store.audience) { _, _ in search(usingAI: false) }
        .onChange(of: store.clock) { _, _ in if !interpreting { search(usingAI: false) } }
        .onAppear { receiveSiriSearch(); if !query.isEmpty { search(usingAI: false) } }
        .onChange(of: store.searchRequest) { _, _ in receiveSiriSearch() }
        .onDisappear { searchTask?.cancel(); generation = UUID(); busy = false; interpreting = false }
    }

    private func receiveSiriSearch() {
        guard let text = store.searchRequest else { return }
        query = text; store.searchRequest = nil; searchPresented = false
        search(usingAI: false)
    }

    private func search(usingAI: Bool) {
        searchTask?.cancel()
        let token = UUID(); generation = token
        let request = query.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleLimit = 100; lineupRequest = false
        if !usingAI { results = [] }
        guard !request.isEmpty else {
            status = "Search channel names and TV guide listings."; busy = false; interpreting = false
            return
        }
        busy = true; interpreting = usingAI
        guard let index = store.queryIndex else {
            // The full index is still preparing: answer from the launch lineup.
            results = store.snapshotMatches(request.split(separator: " ").map(String.init))
            busy = false; interpreting = false
            status = "Keyword matches from your channels and guide."
            return
        }
        searchTask = Task {
            do {
                if !usingAI { try await Task.sleep(for: .milliseconds(250)) }
                var interpretation: SearchInterpretation?
                var aiUnavailable = false
                if usingAI {
                    do { interpretation = try await store.intelligence.interpret(request) }
                    catch { aiUnavailable = true }
                }
                try Task.checkCancellation()
                guard generation == token else { return }
                interpreting = false
                let ignored = Set(["find", "watch", "show", "me", "the", "a", "now", "tonight", "please", "channels", "make", "lineup"])
                let keywords = interpretation?.keywords ?? request.lowercased().split(separator: " ").map(String.init).filter { !ignored.contains($0) }
                let requestedTime = interpretation?.time ?? (request.localizedCaseInsensitiveContains("tonight") ? "tonight" : "now")
                let time = ["all", "now", "tonight", "weekend"].contains(requestedTime) ? requestedTime : "now"
                var date = time == "tonight" ? (Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: .now) ?? .now) : Date.now
                if time == "weekend", !Calendar.current.isDateInWeekend(date) { date = Calendar.current.nextWeekend(startingAfter: date)?.start ?? date }
                let interval: TimeInterval = time == "now" ? 1 : (time == "tonight" ? 21600 : (time == "weekend" ? 172800 : 604800))
                let input = CatalogSearchRequest(keywords: keywords, start: date, end: date.addingTimeInterval(interval),
                    sportsOnly: interpretation?.sportsOnly ?? false, favoritesOnly: interpretation?.favoritesOnly ?? false, language: interpretation?.language ?? "", audience: store.audience)
                let matches = try await catalogWork { try index.search(input) }
                try Task.checkCancellation()
                guard generation == token else { return }
                results = matches; busy = false; lineupRequest = interpretation?.wantsLineup ?? false
                status = aiUnavailable ? "Apple Intelligence is unavailable. Showing keyword matches." :
                    (interpretation == nil ? "Keyword matches from your channels and guide." : "Apple Intelligence interpreted the request. Results are matched against your actual catalog and guide.")
            } catch is CancellationError { }
            catch { if generation == token { busy = false; interpreting = false; status = "Search couldn’t finish. Try again." } }
        }
    }
}

private struct SearchResultRow: View {
    let match: CatalogMatch
    var body: some View {
        Group {
            if let program = match.program {
                NavigationLink { ProgramDetailView(program: program, channel: match.channel) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgramRow(program: program)
                        Text(match.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else { PlayableChannelRow(channel: match.channel) }
        }
    }
}
