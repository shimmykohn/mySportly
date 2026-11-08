import SwiftUI

struct SportsView: View {
    @Environment(AppStore.self) private var store
    @State private var selection: Bool?
    @State private var showMatchingChannels = false
    private var result: SportsScreenResult { store.sportsScreen.result(followedOnly: followedOnly) }
    private var schedule: SportsSchedule { result.schedule }
    private var games: [SportsGame] { result.games }
    private var channelGroups: [TaxonomyBrowseGroup] { result.groups }
    private var busy: Bool { !store.sportsScreen.loaded.contains(followedOnly) }
    @State private var liveLimit = 50
    @State private var upcomingLimit = 50
    private var followedOnly: Bool { selection ?? !store.sportsFollowing.isEmpty }
    private var request: SportsScreenRequest {
        SportsScreenRequest(catalog: store.queryRevision, links: store.sportsLinkRevision,
            minute: Int(store.clock.timeIntervalSince1970 / 60), followedOnly: followedOnly,
            following: store.sportsFollowing, audience: store.audience)
    }

    var body: some View {
        List {
            Section {
                Picker("Sports", selection: Binding(get: { followedOnly }, set: { selection = $0 })) {
                    Text("All Sports").tag(false)
                    Text("My Sports").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("sports-scope")
                NavigationLink { SportsFollowingView() } label: {
                    LabeledContent("Add Teams and Leagues", value: "\(store.teams.count + store.leagues.count) saved")
                }.accessibilityIdentifier("manage-sports-following")
            }
            if store.demo { Label("Sample events", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            if !followedOnly && !channelGroups.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(channelGroups) { TaxonomyBrowseRow(group: $0) }
                    } label: {
                        Label("Browse by Sport", systemImage: "square.grid.2x2")
                    }
                }
            }
            SportsGamesSection(games: games)
            if busy { ProgressView("Finding sports…") }
            if !schedule.live.isEmpty {
                Section("On Now") {
                    ForEach(schedule.live.prefix(liveLimit)) { SportsEventRow(event: $0) }
                    if schedule.live.count > liveLimit { Button("Show More Live Events") { liveLimit += 50 } }
                }
            }
            if !schedule.upcoming.isEmpty {
                Section("Coming Up") {
                    ForEach(schedule.upcoming.prefix(upcomingLimit)) { SportsEventRow(event: $0) }
                    if schedule.upcoming.count > upcomingLimit { Button("Show More Upcoming Events") { upcomingLimit += 50 } }
                }
            }
            if !busy && schedule.isEmpty && games.isEmpty && (followedOnly || channelGroups.isEmpty) {
                ContentUnavailableView {
                    Label(followedOnly ? "No Upcoming Listings for Your Sports" : "No Matching Sports Listings", systemImage: "sportscourt")
                } description: {
                    Text(followedOnly ? "Your saved guide has no matching programs in the next 48 hours. A missing listing does not mean the game is unavailable." : "Events come from your TV guide. Try another lineup or check guide status.")
                } actions: {
                    if followedOnly {
                        if store.teams.isEmpty && store.leagues.isEmpty { NavigationLink("Add Teams and Leagues") { SportsFollowingView() } }
                        else { Button("Browse All Sports") { selection = false } }
                    }
                    NavigationLink("TV Guide Status") { GuideStatusView() }
                    NavigationLink("Sports Data") { SportsDataStatusView() }
                }
            }
            if followedOnly {
                Section {
                    DisclosureGroup("Channels Without Listings", isExpanded: $showMatchingChannels) {
                        if showMatchingChannels { UnscheduledSportsChannels(request: request) }
                    }
                }
            }
            if !schedule.isEmpty { Section { Text("From your TV guide · next 48 hours").font(.caption).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Sports")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    LineupScopeControl()
                    NavigationLink("TV Guide Status") { GuideStatusView() }
                } label: { Label("Sports Filters", systemImage: "line.3.horizontal.decrease") }
            }
        }.appToolbar()
        .task(id: request) {
            guard !store.sportsScreen.isCurrent(request), let index = store.queryIndex, let directory = store.directory else { return }
            let available = Set(store.sportsData.index.schedule(for: nil, at: store.clock).filter { !store.feeds(for: $0.id).isEmpty }.map(\.id))
            await store.sportsScreen.update(request, index: index, directory: directory, sports: store.sportsData.index,
                matched: store.matchedSportsPrograms, availableGames: available, at: store.clock)
        }
        .onChange(of: followedOnly) { liveLimit = 50; upcomingLimit = 50; showMatchingChannels = false }
    }
}

private struct UnscheduledSportsChannels: View {
    @Environment(AppStore.self) private var store
    let request: SportsScreenRequest
    @State private var channels: [FollowedSportsChannel] = []
    @State private var loading = true
    var body: some View {
        Group {
            if loading { ProgressView("Finding matching channels…") }
            MatchingSportsChannelsSection(channels: channels)
        }.task(id: request) {
            guard let index = store.queryIndex else { return }
            let date = store.clock
            do {
                let result = try await catalogWork {
                    try index.sports(at: date, following: request.following.map(\.name), followedOnly: true, audience: request.audience).channelsWithoutListings
                }
                try Task.checkCancellation(); channels = result; loading = false
            } catch { if !Task.isCancelled { loading = false } }
        }
    }
}

struct MatchingSportsChannelsSection: View {
    @Environment(AppStore.self) private var store
    let channels: [FollowedSportsChannel]
    @State private var limit = 30
    var body: some View {
        if !channels.isEmpty {
            Section {
                ForEach(channels.prefix(limit)) { match in
                    Button { store.play(match.channel) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.name(match.channel)).font(.headline)
                            Text("Matches " + match.names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("followed-channel-\(match.id)")
                }
                if channels.count > limit { Button("Show More Channels") { limit += 30 } }
            } header: { Text("Matching Channels") } footer: {
                Text("These channel names match your saved sports, but have no scheduled guide listings. Tap to check the stream; a live game is not confirmed.")
            }
        }
    }
}

struct SportsEventRow: View {
    let event: SportsEvent
    var body: some View {
        NavigationLink { ProgramDetailView(program: event.program, channel: event.channel) } label: {
            VStack(alignment: .leading, spacing: 4) {
                ProgramRow(program: event.program)
                Text(event.channelName).font(.caption).foregroundStyle(.secondary)
                if !event.followedNames.isEmpty { Label(event.followedNames.joined(separator: ", "), systemImage: "bookmark").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
