import SwiftUI

struct LiveView: View {
    @Environment(AppStore.self) private var store
    @State private var browser = ChannelBrowser()
    var body: some View {
        List {
            if store.demo {
                Section { Label("Sample catalog and schedule", systemImage: "info.circle"); Text("These examples demonstrate the app. Connect your own source for live television.").font(.footnote).foregroundStyle(.secondary) }
            }
            if let error = store.personal.storageError { Section { Label(error, systemImage: "exclamationmark.triangle") } }
            if store.loading {
                // Opening and sync activity appears in the native header.
            } else if store.sources.isEmpty && !store.demo {
                ContentUnavailableView { Label("Your TV starts here", systemImage: "play.tv") } description: { Text("Connect an Xtream or M3U source to build your personal lineup.") } actions: { Button("Connect a Source") { store.showSetup = true }.buttonStyle(.borderedProminent) }
            } else {
                if !store.favoriteSports.isEmpty && !store.favoritesToday.isUpdating {
                    FavoritesTodaySection(listings: store.favoritesToday.listings)
                }
                if !store.favorites.isEmpty { Section("Favorites") { ForEach(store.favorites.prefix(12)) { PlayableChannelRow(channel: $0) } } }
                if !store.recent.isEmpty {
                    Section("Recently Watched") {
                        ForEach(store.recent.prefix(5)) { channel in
                            PlayableChannelRow(channel: channel, canRemoveFromHistory: true)
                        }
                    }
                }
                ForEach(browser.featuredCategories) { ExpandedCategorySection(group: $0) }
                if !browser.otherCategories.isEmpty {
                    Section("Categories") { ForEach(browser.otherCategories) { CategoryChannelGroupRow(group: $0) } }
                }
                if store.interests.isEmpty {
                    Section { NavigationLink { InterestsView() } label: { Label("Choose Interests", systemImage: "heart") } }
                }
                if !browser.loading && browser.channels.isEmpty {
                    Text("No channels match these preferences. Open Filters to change your lineup.").foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink { ChannelListView() } label: { Label("All Channels", systemImage: "tv") }
                        .accessibilityIdentifier("all-channels-link").accessibilityValue("\(store.lineup.count) channels")
                    NavigationLink { OrganizerView() } label: { Label("Organize Channels", systemImage: "wand.and.stars") }
                    if UIDevice.current.userInterfaceIdiom == .pad { Button("Open Multiview", systemImage: "rectangle.split.2x2") { store.showMultiview = true } }
                }
            }
        }
        .accessibilityIdentifier("home-root")
        .accessibilityValue("launch-ms=\(store.launchTimeline.milliseconds(to: .firstInteractive) ?? -1)")
        .navigationTitle("").navigationBarTitleDisplayMode(.inline).appToolbar()
        .toolbar {
            ToolbarItem(placement: .principal) { LiveLoadingIndicator(browser: browser) }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Section("Lineup") { LineupScopePicker().pickerStyle(.inline) }
                    NavigationLink { InterestsView() } label: { Label("Edit Interests", systemImage: "heart") }
                } label: { Label("Filter Channels", systemImage: "line.3.horizontal.decrease") }
                .accessibilityIdentifier(store.catalogReady ? "live-filters" : "live-filters-loading")
            }
        }
        .task(id: favoritesRequest) { await store.favoritesToday.update(favoritesRequest, store: store) }
        .refreshable { Task { await store.refreshDueSources(force: true) } }
        .task(id: BrowseTaskID(revision: store.queryRevision, request: browseRequest, preferences: store.personal.revision)) {
            await browser.update(directory: store.directory, request: browseRequest, preferences: store.recommendationPreferences, prepareHome: true)
        }
    }
    private var favoritesRequest: FavoritesTodayRequest {
        FavoritesTodayRequest(catalog: store.queryRevision, sports: store.sportsLinkRevision,
            minute: Int(store.clock.timeIntervalSince1970 / 60), favorites: store.favoriteSports, audience: store.audience)
    }
    private var browseRequest: ChannelBrowseRequest {
        var request = ChannelBrowseRequest(); request.audience = store.audience; request.collapseVariants = true; request.ranked = true; request.excludeInactive = true; return request
    }
}
