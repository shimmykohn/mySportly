import Foundation
import Observation
import SwiftUI
import WidgetKit
import AppIntents
import os

enum AppTab: String, CaseIterable, Codable, Hashable { case home = "Home", guide = "Guide", myStuff = "My Stuff", search = "Search" }
struct ChannelGroup: Codable, Identifiable, Hashable { var id = UUID(); var name: String; var channelIDs: [String] }
struct AppNotice: Identifiable { let id = UUID(); var title: String; var message: String }

@MainActor @Observable final class AppStore {
    #if DEBUG
    /// Device diagnostics reuse the live store to avoid registering a second
    /// CloudKit mirroring handler for the same persistent database.
    static weak var runningForDeviceChecks: AppStore?
    #endif
    let personal: PersonalStore
    let playback = PlaybackController()
    let intelligence = IntelligenceService()
    let organization = OrganizationProgress()
    let sportsData = SportsDataStore()
    private(set) var gameLinks: [String: [SportsFeedLink]] = [:]
    /// Home's games; restored from the launch snapshot, replaced by guide matching.
    private(set) var homeSports = HomeSportsData()
    private(set) var matchedSportsPrograms = Set<String>()
    private(set) var sportsLinkRevision = 0
    private(set) var matchingGames = false
    private(set) var activeSportsGameID: String?
    @ObservationIgnored private var sportsMatchTask: Task<Void, Never>?
    private let cache = CatalogCache()
    private(set) var launchTimeline = LaunchTimeline()
    @ObservationIgnored private let launchSignposter = OSSignposter(subsystem: "app.iska.mysportly", category: "Launch")
    private let provider = ProviderClient()
    private(set) var catalog = CatalogSnapshot()
    private(set) var channels: [Channel] = []
    private(set) var channelIndex: [String: Channel] = [:]
    private(set) var lineup: [Channel] = []
    private(set) var favorites: [Channel] = []
    private(set) var categories: [String] = []
    private(set) var sourceChannelCounts: [UUID: Int] = [:]
    private(set) var queryIndex: CatalogQueryIndex?
    private(set) var queryRevision = 0
    private(set) var directory: ChannelDirectory?
    private(set) var preparingCatalog = false
    @ObservationIgnored private var requestedPersonalRevision = -1
    @ObservationIgnored private var preparationID = UUID()
    @ObservationIgnored private var queryIndexTask: Task<Void, Never>?
    @ObservationIgnored private var launchSnapshotTask: Task<Void, Never>?
    @ObservationIgnored private var preparedStages: PreparedStages?
    @ObservationIgnored private var stagesSaveTask: Task<Void, Never>?
    @ObservationIgnored private let catalogLifetime = CatalogSnapshotLifetime()
    @ObservationIgnored private var widgetTask: Task<Void, Never>?
    @ObservationIgnored private var intentCatalogTask: Task<Void, Never>?
    @ObservationIgnored private var sportsLibraryRevision = -1
    @ObservationIgnored private var savedSports: [SportsLibraryItem] = []
    @ObservationIgnored private var sportsMembershipRevision = -1
    @ObservationIgnored private var sportsMembershipMetadataRevision = -1
    @ObservationIgnored private var cachedSportsMembership = SportsLibraryMembership()
    private var guideIndex: [String: [GuideProgram]] = [:]
    private var sourceGuideIDs: [UUID: [String]] = [:]
    private(set) var guideMatches: [String: GuideMatch] = [:]
    private(set) var playbackAlternatives: [String: [String]] = [:]
    var selectedTab: AppTab = .home
    var showPlayer = false
    /// The tapped item the player zooms out of; nil uses the mini player.
    var playerSourceID: String?
    var showSettings = false
    var showSetup = false
    var notice: AppNotice?
    var loading = true
    /// True once the full saved catalog has been prepared at least once.
    // Settable by tests; the app sets it only after the full catalog is prepared.
    var catalogReady = false
    private(set) var routingReady = false
    var clock = Date.now
    private(set) var importProgress: SourceImportProgress?
    var importingSource: UUID?
    var organizerProgress: String? { organization.isRunning ? organization.countLabel : nil }
    var suggestions: [ChannelSuggestion] = []
    private(set) var suggestionRevision = 0
    private(set) var variantGroups: [[String]] = []
    private(set) var preparingOrganization = false
    @ObservationIgnored private var organizationPreparation: Task<Void, Never>?
    @ObservationIgnored private var organizationRevision = -1
    @ObservationIgnored private var organizationUsesCachedAI = true
    private var importTask: Task<Bool, Never>?
    private var organizeTask: Task<Void, Never>?
    private var importRequiresExistingSource = false
    private(set) var refreshingSource = false
    private var loaded = false
    let backgroundRefresh = SourceRefreshCoordinator()
    private(set) var refreshBatchRunning = false
    private(set) var refreshMessage: String?
    var searchRequest: String?
    var libraryRoute: LibraryBookmark?
    var demo = false
    private var attemptedRestores = Set<UUID>()

    init(inMemory: Bool = false, registerBackground: Bool = false) {
        let created = ContinuousClock.now, createdWall = Date()
        personal = PersonalStore(inMemory: inMemory)
        let processStart = LaunchTimeline.processStartDate().map { LaunchTimeline.instant(for: $0, now: created, wallNow: createdWall) } ?? created
        launchTimeline.mark(.processStart, at: processStart)
        launchTimeline.mark(.storeCreated, at: created)
        playback.quality = StreamQuality(rawValue: personal.value("preferences.streamQuality", default: "Auto")) ?? .automatic
        playback.onFailure = { [weak self] in self?.offerAlternate() }
        sportsData.onUpdate = { [weak self] in self?.matchSportsGames() }
        if !inMemory && registerBackground {
            backgroundRefresh.register(store: self)
            #if DEBUG
            Self.runningForDeviceChecks = self
            #endif
        }
    }

    var sources: [TVSource] { demo ? [SampleCatalog.source] : personal.keys(prefix: "source.").compactMap { personal.value($0, default: Optional<TVSource>.none) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var groups: [ChannelGroup] { personal.keys(prefix: "group.").compactMap { personal.value($0, default: Optional<ChannelGroup>.none) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var recent: [Channel] {
        personal.keys(prefix: "history.").map { ($0, personal.value($0, default: Date.distantPast)) }.sorted { $0.1 > $1.1 }.prefix(12).compactMap { channelIndex[String($0.0.dropFirst(8))] }.filter { !flag($0, "hidden") }
    }
    var languages: [String] { personal.value("preferences.languages", default: LocalePreferences.suggestedLanguages) }
    var regions: [String] { personal.value("preferences.regions", default: [Locale.current.region?.identifier ?? "US"]) }
    var lineupScope: LineupScope { LineupScope(rawValue: personal.value("preferences.lineupScope", default: LineupScope.preferred.rawValue)) ?? .preferred }
    var audience: ChannelAudience { ChannelAudience(scope: lineupScope, languages: languages, regions: regions, includeUnknownLanguage: personal.value("preferences.includeUnknownLanguage", default: true)) }
    // Browsing All Channels never authorizes sending other regions to Jev.
    var organizationAudience: ChannelAudience { ChannelAudience(scope: .preferred, languages: languages, regions: regions, includeUnknownLanguage: personal.value("preferences.includeUnknownLanguage", default: true)) }
    var organizationPaths: [[String]] {
        // Existing organizers retain their starting choices. New profiles choose
        // their own list before the first run, optionally using suggestions.
        personal.value("preferences.organizationPaths", default: demo || !personal.keys(prefix: "taxonomy.placement.").isEmpty ? GroupTaxonomy.seedPaths : [])
    }
    var interests: [String] { personal.value("preferences.interests", default: [String]()) }
    var teams: [String] { sportsLibrary.filter { $0.kind == .team }.map(\.name) }
    var leagues: [String] { sportsLibrary.filter { $0.kind == .league }.map(\.name) }
    private var explicitSportsLibrary: [SportsLibraryItem] {
        let revision = personal.revision
        if sportsLibraryRevision == revision { return savedSports }
        var items: [String: SportsLibraryItem] = [:]
        for kind in SportsFollowKind.allCases {
            let legacy: [String] = personal.value(kind == .team ? "preferences.teams" : "preferences.leagues", default: [])
            for name in legacy {
                let item = SportsLibraryItem(name: name, kind: kind)
                if item.name.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) { items[item.id] = item }
            }
        }
        for key in personal.keys(prefix: "sports.library.") {
            guard let entry: SportsLibraryEntry = personal.value(key, default: Optional<SportsLibraryEntry>.none) else { continue }
            if entry.saved { items[entry.item.id] = entry.item }
            else { items.removeValue(forKey: entry.item.id) }
        }
        savedSports = items.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        sportsLibraryRevision = revision
        return savedSports
    }
    var sportsMembership: SportsLibraryMembership {
        let revision = personal.revision, metadata = sportsData.metadataRevision
        if sportsMembershipRevision != revision || sportsMembershipMetadataRevision != metadata {
            cachedSportsMembership = SportsLibraryMembership(saved: explicitSportsLibrary, choices: sportsData.index.choices)
            sportsMembershipRevision = revision; sportsMembershipMetadataRevision = metadata
        }
        return cachedSportsMembership
    }
    var sportsLibrary: [SportsLibraryItem] { sportsMembership.directItems }
    var sportsFollowing: [SportsLibraryItem] { sportsMembership.following }
    var favoriteSports: [SportsLibraryItem] { sportsLibrary.filter { isSportsFavorite($0) } }
    func hasSportsItem(_ item: SportsLibraryItem) -> Bool { sportsLibrary.contains { $0.id == item.id } }
    func sportsLeagueIncluding(_ item: SportsLibraryItem) -> SportsLibraryItem? { hasSportsItem(item) ? nil : sportsMembership.leagueIncluding(item) }
    func isSportsFavorite(_ item: SportsLibraryItem) -> Bool { personal.value("sports.favorite.\(item.id)", default: false) }
    func saveSportsItem(_ item: SportsLibraryItem) {
        guard item.name.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains), !hasSportsItem(item) else { return }
        set("sports.library.\(item.id)", SportsLibraryEntry(item: item, saved: true))
    }
    func removeSportsItem(_ item: SportsLibraryItem) {
        do {
            try personal.write(["sports.library.\(item.id)": try JSONEncoder().encode(SportsLibraryEntry(item: item, saved: false)),
                                "sports.favorite.\(item.id)": nil])
        } catch { inform("Changes weren’t saved", error.localizedDescription) }
    }
    func setSportsFavorite(_ item: SportsLibraryItem, _ favorite: Bool) {
        guard hasSportsItem(item) else { return }
        do {
            var updates: [String: Data?] = ["sports.favorite.\(item.id)": try JSONEncoder().encode(favorite)]
            // Favoriting an inherited team is an explicit choice to keep it,
            // even if its league is removed later. Save both atomically.
            if favorite { updates["sports.library.\(item.id)"] = try JSONEncoder().encode(SportsLibraryEntry(item: item, saved: true)) }
            try personal.write(updates)
        } catch { inform("Changes weren’t saved", error.localizedDescription) }
    }
    var usesHistory: Bool { personal.value("preferences.history", default: true) }
    var canUndo: Bool { personal.has("organizer.undo") }

    func load() async {
        guard !loaded else { return }; loaded = true
        launchTimeline.mark(.loadStarted)
        if ProcessInfo.processInfo.arguments.contains("--demo") { await loadDemo(); loading = false; catalogReady = true; routingReady = true; AppRouteInbox.consume(using: self); return }
        #if DEBUG
        do {
            if try intelligence.importDevelopmentCredential() { try personal.set("preferences.cloudAI", true) }
        } catch { inform("Jev setup", "The key could not be saved in this device’s Keychain.") }
        #endif
        #if DEBUG
        if SyntheticCatalogSeed.requested, !personal.has("source.\(SyntheticCatalogSeed.sourceID)") {
            let seed = SyntheticCatalogSeed.snapshot()
            try? await cache.save(seed)
            try? personal.set("source.\(SyntheticCatalogSeed.sourceID)", SyntheticCatalogSeed.source)
            try? personal.set("setup.complete", true)
            for index in [0, 3, 6, 9, 12] { try? personal.set("channel.seed.\(index).favorite", true) }
            print("[Launch] seeded synthetic catalog")
        }
        #endif
        Task { await sportsData.load() }
        // First frame: the small launch snapshot. The full catalog, cloud
        // status and network work all follow once Home is interactive.
        let snapshotRead = launchSignposter.beginInterval("snapshot")
        let snapshot = await cache.loadLaunchSnapshot()?.active(sources: Set(sources.map(\.id)), now: .now)
        launchSignposter.endInterval("snapshot", snapshotRead)
        #if DEBUG
        print("[Launch] snapshotReadDone=\(launchTimeline.milliseconds(at: .now)) channels=\(snapshot?.channels.count ?? -1)")
        #endif
        if let snapshot, !snapshot.channels.isEmpty {
            apply(snapshot)
            launchTimeline.mark(.snapshotLoaded)
            showFirstFrame()
        }
        let catalogLoad = launchSignposter.beginInterval("catalogLoad")
        do { catalog = try await cache.load(); catalog.pruneGuide(now: .now) }
        catch { inform("Saved catalog unavailable", "Your personal choices are safe. Refresh your sources to restore the local catalog.") }
        launchSignposter.endInterval("catalogLoad", catalogLoad)
        launchTimeline.mark(.catalogDecoded)
        let prepare = launchSignposter.beginInterval("prepare")
        preparedStages = await cache.loadPreparedStages()
        rebuild(force: true)
        await waitForCatalog()
        launchSignposter.endInterval("prepare", prepare)
        catalogReady = true
        showFirstFrame()
        let restoreState = launchSignposter.beginInterval("restoreState")
        let revision = personal.revision
        await personal.refreshCloudStatus()
        await organization.restore()
        if personal.revision != revision { rebuild() }
        launchSignposter.endInterval("restoreState", restoreState)
        updateIntentCatalog()
        await restoreMissingSources()
        routingReady = true
        AppRouteInbox.consume(using: self)
        #if DEBUG
        await DevelopmentGroupAudit.runIfRequested(store: self)
        #endif
        if backgroundRefresh.registered && UIApplication.shared.applicationState == .active && !ProcessInfo.processInfo.arguments.contains("--group-audit") {
            Task { await self.refreshDueSources() }
        }
    }

    private func showFirstFrame() {
        guard loading else { return }
        loading = false
        showSetup = !personal.value("setup.complete", default: false)
        launchTimeline.mark(.firstInteractive)
    }

    /// Fills the published lineup from the launch snapshot until the full
    /// prepared catalog replaces it.
    private func apply(_ snapshot: LaunchSnapshot) {
        let byID = Dictionary(snapshot.channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        channels = snapshot.channels
        channelIndex = byID
        lineup = snapshot.lineupIDs.compactMap { byID[$0] }
        favorites = snapshot.favoriteIDs.compactMap { byID[$0] }
        guideIndex = snapshot.guide
        guideMatches = snapshot.guideMatches
        homeSports = snapshot.sports ?? HomeSportsData()
        gameLinks = homeSports.links
    }

    var homeFollows: HomeFollows {
        let items = sportsLibrary
        return HomeFollows(teamIDs: Set(items.filter { $0.kind == .team }.map(\.id)), leagueIDs: Set(items.filter { $0.kind == .league }.map(\.id)))
    }

    var homeContent: HomeContent {
        var counts: [String: Int] = [:]
        for gameID in homeSports.links.keys {
            counts[gameID] = feeds(for: gameID).count
        }
        return HomeContent.build(sports: homeSports, follows: homeFollows, feedCounts: counts,
                                 favorites: favorites.map { HomeChannel(channelID: $0.id, program: now(on: $0)) }, at: clock)
    }

    func isFollowing(_ team: SportsTeam) -> Bool { homeFollows.teamIDs.contains(team.libraryItem.id) }
    func toggleFollow(_ team: SportsTeam) {
        if isFollowing(team) { removeSportsItem(team.libraryItem) } else { saveSportsItem(team.libraryItem) }
    }

    /// Search before the full index exists: snapshot channels whose display
    /// name contains every keyword, in lineup order.
    func snapshotMatches(_ keywords: [String]) -> [CatalogMatch] {
        guard !keywords.isEmpty else { return [] }
        return channels.compactMap { channel in
            let display = name(channel)
            let hit = keywords.allSatisfy { display.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return hit ? CatalogMatch(channel: channel, name: display, program: now(on: channel)) : nil
        }
    }

    func loadDemo() async {
        demo = true; catalog = SampleCatalog.snapshot()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-intent-search") {
            let intent = SearchTVIntent(); intent.criteria = StringSearchCriteria(term: "Sample News")
            _ = try? await intent.perform()
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-empty-favorites") {
            let item = SportsLibraryItem(name: "Dallas Cowboys", kind: .team)
            try? personal.set("sports.library.\(item.id)", SportsLibraryEntry(item: item, saved: true))
            try? personal.set("sports.favorite.\(item.id)", true)
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-refresh-check") {
            refreshingSource = true
            importProgress = SourceImportProgress(sourceName: "Sample source")
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-sports-api-check") {
            let now = Date.now
            catalog.programs.removeAll { $0.guideID == "sports" }
            catalog.programs.append(GuideProgram(id: "sample.game.program", sourceID: SampleCatalog.sourceID, guideID: "sports", title: "New York Knicks vs Boston Celtics", start: now - 15 * 60, end: now + 2 * 3600, categories: ["NBA"]))
            var alternate = catalog.channels[2]; alternate.id = "sample.sports.alternate"; alternate.name = "Sample Sports Alternate HD"
            catalog.channels.append(alternate)
            try? sportsData.useSample(SportsCatalog(fetchedAt: now.timeIntervalSince1970,
                leagues: [SportsLeague(id: "sample.nba", name: "NBA")],
                teams: [SportsTeam(id: "sample.knicks", name: "New York Knicks", leagueID: "sample.nba", logo: URL(string: "https://media.api-sports.io/basketball/teams/151.png")), SportsTeam(id: "sample.celtics", name: "Boston Celtics", leagueID: "sample.nba", logo: URL(string: "https://media.api-sports.io/basketball/teams/133.png"))],
                games: [SportsGame(id: "sample.game", leagueID: "sample.nba", homeID: "sample.knicks", awayID: "sample.celtics", timestamp: (now - 15 * 60).timeIntervalSince1970, status: .live)]))
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-home-follows") {
            saveSportsItem(SportsLibraryItem(name: "New York Knicks", kind: .team))
            saveSportsItem(SportsLibraryItem(name: "NBA", kind: .league))
            try? personal.set("channel.sample.0.favorite", true)
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-sports-check") {
            for index in catalog.programs.indices where catalog.programs[index].guideID == "sports" {
                catalog.programs[index].title = "Sample NBA Basketball · Knicks vs Celtics"
            }
            catalog.channels.append(Channel(id: "sample.unscheduled", sourceID: SampleCatalog.sourceID, name: "Sample NFL · Cowboys at Packers", group: "NFL", language: "en", region: "US"))
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-home-check") {
            try? personal.set("history.sample.0", Date.now)
            try? personal.set("history.sample.2", Date.now - 60)
            catalog.channels.append(Channel(id: "sample.idle", sourceID: SampleCatalog.sourceID, name: "- NO EVENT STREAMING - | US: Sample PPV 7", group: "Sports", language: "en", region: "US"))
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-sport-groups") {
            try? personal.set("preferences.interests", ProcessInfo.processInfo.arguments.contains("--demo-no-sports-interest") ? ["News"] : ["Sports"])
            for (sport, count) in [("Golf", 10), ("Tennis", 12)] {
                for number in 1...count {
                    catalog.channels.append(Channel(id: "sample.\(sport.lowercased()).\(number)", sourceID: SampleCatalog.sourceID,
                        name: ":\(sport) \(String(format: "%02d", number))", group: "US", language: "en", region: "US"))
                }
            }
            for prefix in ["NFL", "NCAAF", "NEWLEAGUE"] {
                for number in 1...2 {
                    catalog.channels.append(Channel(id: "sample.\(prefix.lowercased()).\(number)", sourceID: SampleCatalog.sourceID,
                        name: "\(prefix) \(number)", group: "US | American Football", language: "en", region: "US"))
                }
            }
        }
        #endif
        rebuild(force: true)
        await waitForCatalog()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-organization-progress") { startDemoOrganization() }
        #endif
    }

    // UI mutations only enqueue work. The immutable snapshot is built away from
    // the main actor and published together, so no view sees half an index.
    func rebuild(force: Bool = false) {
        let active = Set(sources.map(\.id))
        if importRequiresExistingSource, let importingSource, !active.contains(importingSource) { cancelImport() }
        if let source = playback.channel?.sourceID, !active.contains(source) { playback.stop() }
        if !personal.value("preferences.cloudAI", default: false) { cancelOrganization() }
        guard force || requestedPersonalRevision != personal.catalogRevision else { return }
        requestedPersonalRevision = personal.catalogRevision
        queryIndexTask?.cancel()
        organizationPreparation?.cancel()
        organizationRevision = -1
        let id = UUID(); preparationID = id
        preparingCatalog = true
        let channels = catalog.channels, programs = catalog.programs, overrides = personal.snapshotValues(), guideChannels = catalog.guideChannels, stages = preparedStages
        queryIndexTask = Task { [weak self] in
            do {
                let prepared = try await catalogWork {
                    try PreparedCatalog(channels: channels, programs: programs, activeSources: active, overrides: overrides, guideChannels: guideChannels, stages: stages)
                }
                guard !Task.isCancelled, let self, self.preparationID == id else { return }
                self.directory = prepared.directory
                self.channels = prepared.directory.channels
                self.channelIndex = prepared.channelsByID
                self.lineup = prepared.directory.lineup
                self.favorites = prepared.directory.favorites
                self.categories = prepared.directory.visibleCategories
                self.sourceChannelCounts = prepared.directory.sourceCounts
                self.guideIndex = prepared.guide
                self.sourceGuideIDs = prepared.guideIDs
                self.guideMatches = prepared.guideMappings.matches
                self.playbackAlternatives = prepared.playbackAlternatives
                self.queryIndex = prepared.query
                self.queryRevision += 1
                self.preparingCatalog = false
                if self.launchTimeline.milliseconds(to: .catalogPrepared) == nil {
                    self.launchTimeline.mark(.catalogPrepared)
                    #if DEBUG
                    print("[Launch] " + self.launchTimeline.summary + " channels=\(channels.count) listings=\(programs.count)")
                    #endif
                }
                self.matchSportsGames()
                self.updateWidgetSnapshot()
                self.updateIntentCatalog()
                self.saveLaunchSnapshot()
                if let fresh = prepared.freshStages { self.savePreparedStages(fresh) }
                await self.catalogLifetime.retain(prepared, revision: self.queryRevision)
            } catch {
                guard let self, self.preparationID == id else { return }
                self.preparingCatalog = false
            }
        }
    }

    /// Debounced so a burst of personal edits or a rebuild followed by game
    /// matching writes the snapshot once. Built from published state.
    private func saveLaunchSnapshot() {
        guard !demo else { return }
        launchSnapshotTask?.cancel()
        let cache = cache
        guard !sources.isEmpty else { launchSnapshotTask = Task { await cache.removeLaunchSnapshot() }; return }
        let recentIDs = personal.keys(prefix: "history.").map { ($0, personal.value($0, default: Date.distantPast)) }
            .sorted { $0.1 > $1.1 }.prefix(12).map { String($0.0.dropFirst("history.".count)) }
        var manual: [String: String] = [:]
        for key in personal.keys(prefix: "channel.") where key.hasSuffix(".guideID") {
            if let id: String = personal.value(key, default: Optional<String>.none) { manual[String(key.dropFirst("channel.".count).dropLast(".guideID".count))] = id }
        }
        var sports = homeSports.relevant(to: homeFollows, at: .now)
        sports.links = Dictionary(uniqueKeysWithValues: sports.games.map { game in
            let accepted = Set(feeds(for: game.id).map(\.id))
            return (game.id, (gameLinks[game.id] ?? []).filter { accepted.contains($0.channelID) })
        }.filter { !$0.1.isEmpty })
        let favorites = favorites, lineup = lineup, channels = channelIndex, guide = guideIndex, matches = guideMatches
        launchSnapshotTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let snapshot = try? await catalogWork({
                LaunchSnapshot(favorites: favorites, recentIDs: recentIDs, lineup: lineup, channelsByID: channels, guide: guide,
                               guideMatches: matches, manualGuideIDs: manual, sports: sports, now: .now)
            }) else { return }
            try? await cache.saveLaunchSnapshot(snapshot)
        }
    }

    /// Reused by later rebuilds at once; written to disk for the next launch.
    private func savePreparedStages(_ stages: PreparedStages) {
        guard !demo else { return }
        preparedStages = stages
        stagesSaveTask?.cancel()
        let cache = cache
        guard !sources.isEmpty else { stagesSaveTask = Task { await cache.removePreparedStages() }; return }
        stagesSaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? await cache.savePreparedStages(stages)
        }
    }

    func waitForCatalog() async {
        repeat {
            let id = preparationID
            await queryIndexTask?.value
            if id == preparationID { return }
        } while !Task.isCancelled
    }

    func key(_ channel: Channel, _ field: String) -> String { "channel.\(channel.id).\(field)" }
    func name(_ channel: Channel) -> String { let custom: String = personal.value(key(channel, "name"), default: ""); return custom.isEmpty ? channel.name : custom }
    func flag(_ channel: Channel, _ field: String) -> Bool { personal.value(key(channel, field), default: false) }
    func language(_ channel: Channel) -> String { personal.value(key(channel, "language"), default: directory?.metadata[channel.id]?.language ?? channel.language) }
    func region(_ channel: Channel) -> String { personal.value(key(channel, "region"), default: directory?.metadata[channel.id]?.region ?? channel.region) }
    func category(_ channel: Channel) -> String { personal.value(key(channel, "category"), default: directory?.metadata[channel.id]?.category ?? "Unsorted") }
    func set<T: Encodable>(_ key: String, _ value: T) {
        do {
            var changes: [String: Data?] = [key: try JSONEncoder().encode(value)]
            if key.hasPrefix("channel."), key.hasSuffix(".favorite"),
               let channel = channelIndex[String(key.dropFirst(8).dropLast(9))] {
                let item = bookmark(channel)
                if (value as? Bool) == true || flag(channel, "favorite") {
                    changes["library.item.\(item.id)"] = try JSONEncoder().encode(item)
                }
            }
            try personal.write(changes); rebuild()
        } catch { inform("Changes weren’t saved", error.localizedDescription) }
    }
    func remove(_ key: String) { do { try personal.remove(key); rebuild() } catch { inform("Changes weren’t saved", error.localizedDescription) } }
    func toggle(_ channel: Channel, _ field: String) { set(key(channel, field), !flag(channel, field)) }
    func edit(_ channel: Channel, field: String, value: String) {
        edit(channel, fields: [field: value])
    }
    func edit(_ channel: Channel, fields: [String: String]) {
        do {
            var updates: [String: Data?] = [:]
            for (field, value) in fields {
                updates[key(channel, field)] = try JSONEncoder().encode(value)
                updates[key(channel, "manual.\(field)")] = try JSONEncoder().encode(true)
            }
            try personal.write(updates)
            rebuild()
        } catch { inform("Changes weren’t saved", error.localizedDescription) }
    }
    func saveGuideMapping(_ channel: Channel, guideID: String?, offset: Int?) {
        do {
            try personal.write([key(channel, "guideID"): try guideID.map { try JSONEncoder().encode($0) },
                                key(channel, "guideOffset"): try offset.map { try JSONEncoder().encode($0) }])
            rebuild()
        } catch { inform("Mapping wasn’t saved", error.localizedDescription) }
    }
    func reorder(_ channels: [Channel]) {
        do { try personal.write(Dictionary(uniqueKeysWithValues: try channels.enumerated().map { (key($0.element, "order"), Optional(try JSONEncoder().encode($0.offset))) })); rebuild() }
        catch { inform("Order wasn’t saved", error.localizedDescription) }
    }
    func bulk(_ ids: Set<String>, field: String, value: Bool) {
        do {
            var changes = Dictionary(uniqueKeysWithValues: try ids.map { ("channel.\($0).\(field)", Optional(try JSONEncoder().encode(value))) })
            if field == "favorite" {
                for id in ids { if let channel = channelIndex[id], value || flag(channel, "favorite") {
                    let item = bookmark(channel); changes["library.item.\(item.id)"] = try JSONEncoder().encode(item)
                } }
            }
            try personal.write(changes); rebuild()
        }
        catch { inform("Changes weren’t saved", error.localizedDescription) }
    }

    func programs(for channel: Channel) -> [GuideProgram] {
        let guideID = guideID(for: channel)
        let offset: Int = personal.value(key(channel, "guideOffset"), default: 0)
        let programs = guideIndex[channel.sourceID.uuidString + "|" + guideID] ?? []
        guard offset != 0 else { return programs }
        return programs.map { var item = $0; item.start += Double(offset) * 60; item.end += Double(offset) * 60; return item }
    }
    func now(on channel: Channel, at date: Date? = nil) -> GuideProgram? { programs(for: channel).first { $0.isLive(at: date ?? clock) } }
    func next(on channel: Channel, at date: Date? = nil) -> GuideProgram? { programs(for: channel).first { $0.start > (date ?? clock) } }
    func guideIDs(for sourceID: UUID) -> [String] { sourceGuideIDs[sourceID] ?? [] }
    func guideID(for channel: Channel) -> String { personal.value(key(channel, "guideID"), default: automaticGuideID(for: channel)) }
    func automaticGuideID(for channel: Channel) -> String { guideMatches[channel.id]?.guideID ?? channel.guideID }
    func relevance(_ channel: Channel) -> [String] {
        var reasons: [String] = []
        if flag(channel, "favorite") { reasons.append("One of your favorites") }
        if languages.contains(language(channel)) { reasons.append("Preferred language") }
        if regions.contains(region(channel)) { reasons.append("Preferred region") }
        if interests.contains(where: { category(channel).localizedCaseInsensitiveContains($0) }) { reasons.append("Matches your interests") }
        if let program = now(on: channel), (teams + leagues).contains(where: { program.title.localizedCaseInsensitiveContains($0) }) { reasons.append("A team or league you follow") }
        if usesHistory && personal.has("history.\(channel.id)") { reasons.append("Recently watched") }
        return reasons
    }
    var recommendationPreferences: RecommendationPreferences {
        RecommendationPreferences(languages: languages, regions: regions, interests: interests, following: sportsFollowing.map(\.name),
            watched: usesHistory ? Set(personal.keys(prefix: "history.").map { String($0.dropFirst(8)) }) : [])
    }

    func connect(_ source: TVSource, secrets: SourceSecrets, playlist: String? = nil, persistConfiguration: Bool = true, kind: SourceRefreshKind = .playlist, quiet: Bool = false) {
        guard importTask == nil else { return }
        if !persistConfiguration {
            UserDefaults.standard.set(Date.now, forKey: attemptKey(source, kind))
            if kind == .playlist { UserDefaults.standard.set(Date.now, forKey: attemptKey(source, .guide)) }
        }
        let sourceKey = "source.\(source.id)"
        let expectedVersion = personal.version(sourceKey)
        importRequiresExistingSource = personal.has(sourceKey)
        refreshingSource = !persistConfiguration
        let progress = SourceImportProgress(sourceName: source.name)
        importingSource = source.id; importProgress = progress
        let (updates, continuation) = AsyncStream<ImportUpdate>.makeStream(bufferingPolicy: .bufferingNewest(1))
        importTask = Task { () -> Bool in
            let observeProgress = Task { for await update in updates { progress.receive(update) } }
            defer {
                continuation.finish(); observeProgress.cancel()
                importTask = nil; importingSource = nil; importProgress = nil; importRequiresExistingSource = false; refreshingSource = false
            }
            do {
                let sourcePlaylist = secrets.isFile && playlist == nil ? try await cache.playlist(source.id) : playlist
                let result: ProviderImport
                if kind == .guide {
                    let guide = try await provider.refreshGuide(source, secrets: secrets, savedURL: catalog.guideURLs[source.id], channelCount: sourceChannelCounts[source.id] ?? 0) { continuation.yield($0) }
                    result = ProviderImport(channels: [], programs: guide.programs, guideChannels: guide.channels)
                } else {
                    result = try await provider.importSource(source, secrets: secrets, playlist: sourcePlaylist) { continuation.yield($0) }
                }
                try Task.checkCancellation()
                progress.beginSaving(result)
                personal.reload()
                guard ImportPolicy.canCommit(expectedVersion: expectedVersion, currentVersion: personal.version(sourceKey)) else { throw CancellationError() }
                var updated = source; updated.refreshedAt = .now
                if let limit = result.connectionLimit, limit > 0 { updated.connectionLimit = limit }
                if let playlist { try await cache.savePlaylist(playlist, sourceID: source.id) }
                let previous = demo ? ((try? await cache.load()) ?? CatalogSnapshot()) : catalog
                let next = try await catalogWork {
                    try Task.checkCancellation()
                    var next = previous
                    if kind == .guide {
                        next.replaceGuide(sourceID: source.id, guide: TVGuide(channels: result.guideChannels, programs: result.programs ?? []))
                    } else {
                        next.replace(sourceID: source.id, channels: result.channels, programs: result.programs, guideChannels: result.guideChannels)
                        next.guideURLs[source.id] = result.guideURL
                    }
                    next.pruneGuide(now: .now)
                    return next
                }
                try await cache.save(next)
                try Task.checkCancellation()
                personal.reload()
                guard ImportPolicy.canCommit(expectedVersion: expectedVersion, currentVersion: personal.version(sourceKey)) else { throw CancellationError() }
                // A catalog refresh never writes a new cloud source event. A removal on another
                // device must remain authoritative even when its tombstone has not arrived yet.
                if persistConfiguration {
                    try KeychainStore.save(secrets, sourceID: source.id, sync: personal.cloudRequested)
                    try personal.set(sourceKey, updated)
                }
                demo = false; catalog = next; rebuild(force: true)
                await waitForCatalog()
                try Task.checkCancellation()
                if let warning = result.guideWarning { refreshMessage = warning; if !quiet { inform("Guide refresh", warning) } }
                showSetup = false
                if !personal.value("setup.complete", default: false) { try personal.set("setup.complete", true) }
                return result.guideWarning == nil
            } catch is CancellationError { }
            catch { if !Task.isCancelled { refreshMessage = safeError(error); if !quiet { inform("Couldn’t connect", safeError(error)) } } }
            return false
        }
    }
    func cancelImport() { importTask?.cancel() }
    func refresh(_ source: TVSource, kind: SourceRefreshKind = .playlist) {
        do {
            guard let secrets = try KeychainStore.credentials(source.id) else { inform("Connection details needed", "Open this source and enter its connection details. iCloud Keychain may still be syncing."); return }
            connect(source, secrets: secrets, persistConfiguration: false, kind: kind)
        } catch { inform("Keychain unavailable", error.localizedDescription) }
    }
    func restoreMissingSources() async {
        // Scene activation can arrive while load() is still decrypting the cache.
        // Empty in-memory channels at that point do not mean a source is missing.
        guard catalogReady, !demo else { return }
        await waitForCatalog()
        for source in sources where !channels.contains(where: { $0.sourceID == source.id }) && !attemptedRestores.contains(source.id) {
            guard importTask == nil, (try? KeychainStore.credentials(source.id)) != nil else { continue }
            attemptedRestores.insert(source.id); refresh(source)
            _ = await importTask?.value
        }
    }
    func removeSource(_ source: TVSource) async {
        if importingSource == source.id { cancelImport(); _ = await importTask?.value }
        if playback.channel?.sourceID == source.id { playback.stop() }
        do {
            try personal.remove("source.\(source.id)")
            rebuild()
            try KeychainStore.remove("source.\(source.id)")
            try KeychainStore.remove("source.\(source.id)", sync: true)
            catalog.channels.removeAll { $0.sourceID == source.id }; catalog.programs.removeAll { $0.sourceID == source.id }
            catalog.guideChannels.removeAll { $0.sourceID == source.id }
            catalog.refreshed.removeValue(forKey: source.id)
            catalog.guideRefreshed.removeValue(forKey: source.id)
            catalog.guideURLs.removeValue(forKey: source.id)
            catalog.pruneGuide(now: .now)
            try await cache.save(catalog); try await cache.removePlaylist(source.id); rebuild(force: true)
            await waitForCatalog()
        } catch { inform("Source removal", safeError(error)) }
    }

    func play(_ channel: Channel, gameID: String? = nil, explicitFeed: Bool = false, source zoomSource: String? = nil) {
        do {
            let preferred: String = personal.value(key(channel, "preferredVariant"), default: channel.id)
            let chosen = !explicitFeed ? (channelIndex[preferred] ?? channel) : channel
            guard sources.contains(where: { $0.id == chosen.sourceID }) else { throw CatalogError.rejected }
            let secrets = try KeychainStore.credentials(chosen.sourceID) ?? SourceSecrets()
            let url = try provider.playbackURL(chosen, secrets: secrets)
            let options = gameID.map { feeds(for: $0, playableOnly: true) } ?? variants(of: chosen)
            let alternates = options.filter { $0.id != chosen.id && $0.sourceID == chosen.sourceID }.prefix(2).compactMap { alternate -> PlaybackAlternative? in
                guard let url = try? provider.playbackURL(alternate, secrets: secrets) else { return nil }
                return PlaybackAlternative(channel: alternate, url: url)
            }
            activeSportsGameID = gameID
            playback.play(chosen, url: url, title: now(on: chosen)?.title, preferredLanguage: personal.value("preferences.audioLanguage", default: languages.first ?? "en"), alternates: alternates)
            if usesHistory { try personal.set("history.\(chosen.id)", Date.now) }
            if !showPlayer { playerSourceID = zoomSource }
            showPlayer = true
        } catch { inform("Playback unavailable", safeError(error)) }
    }
    /// Previous or next channel: through favorites when the playing channel is
    /// one of at least two, otherwise through the lineup.
    func stepChannel(by offset: Int) {
        let current = playback.channel
        let list = favorites.count > 1 && current.map { flag($0, "favorite") } == true ? favorites : lineup
        guard let id = ChannelStepping.neighbor(of: current?.id, in: list.map(\.id), offset: offset), let channel = channelIndex[id] else { return }
        play(channel)
    }
    /// The player's title: the game, else the current program, else the channel.
    var playerTitle: String {
        guard let channel = playback.channel else { return "" }
        if let gameID = activeSportsGameID, let game = game(gameID) {
            let teams = sportsData.index.teams.isEmpty ? homeSports.teams : sportsData.index.teams
            if let away = teams[game.awayID] ?? homeSports.teams[game.awayID], let home = teams[game.homeID] ?? homeSports.teams[game.homeID] {
                return "\(away.libraryItem.name) at \(home.libraryItem.name)"
            }
        }
        return now(on: channel)?.title ?? name(channel)
    }
    /// "Channel · League" for games, else the channel name when the title is a program.
    var playerSubtitle: String {
        guard let channel = playback.channel else { return "" }
        let league = activeSportsGameID.flatMap { game($0) }.flatMap { sportsData.index.leagues[$0.leagueID] ?? homeSports.leagues[$0.leagueID] }?.name
        let title = playerTitle
        return [title == name(channel) ? nil : name(channel), league].compactMap { $0 }.joined(separator: " · ")
    }
    func previousChannel() { if let previous = playback.previous, let channel = channelIndex[previous.id] { play(channel) } }
    func variants(of channel: Channel) -> [Channel] {
        let group: [String] = personal.value(key(channel, "variants"), default: playbackAlternatives[channel.id] ?? [channel.id])
        return group.compactMap { channelIndex[$0] }
    }
    func matchSportsGames() {
        sportsMatchTask?.cancel()
        // Still preparing: keep the games and links the launch snapshot restored.
        guard let query = queryIndex else { matchingGames = false; return }
        guard !sportsData.reference.teams.isEmpty else {
            gameLinks = [:]; matchedSportsPrograms = []; matchingGames = false; sportsLinkRevision += 1; return
        }
        let index = sportsData.reference, refreshed = catalog.refreshed, date = clock
        let revision = queryRevision, sportsRevision = sportsData.metadataRevision
        matchingGames = true
        sportsMatchTask = Task { [weak self] in
            do {
                let result = try await catalogWork { try query.guideGames(reference: index, refreshed: refreshed, at: date) }
                guard !Task.isCancelled, let self, self.queryRevision == revision, self.sportsData.metadataRevision == sportsRevision else { return }
                let links = result.links
                self.sportsData.showGuideGames(result.index)
                self.gameLinks = links
                var home = HomeSportsData()
                home.games = result.index.orderedGames; home.teams = result.index.teams; home.leagues = result.index.leagues; home.links = links
                self.homeSports = home
                self.saveLaunchSnapshot()
                self.matchedSportsPrograms = Set(links.values.flatMap { $0.compactMap(\.programID) })
                self.matchingGames = false; self.sportsLinkRevision += 1
            } catch { if !Task.isCancelled { self?.matchingGames = false } }
        }
    }
    func waitForSportsMatching() async { await sportsMatchTask?.value }
    func feeds(for gameID: String, playableOnly: Bool = false) -> [Channel] {
        let date = clock
        if playableOnly, game(gameID)?.canWatch(at: date) != true { return [] }
        return (gameLinks[gameID] ?? []).compactMap { link in
            // Before the full catalog, links come from the launch snapshot,
            // which kept only feeds that matched the audience when saved.
            guard (!playableOnly || link.isValid(at: date)), let channel = channelIndex[link.channelID], !flag(channel, "hidden"),
                  !catalogReady || audience.includes(language: language(channel), region: region(channel)) else { return nil }
            return channel
        }.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
    }
    /// A matched game, or one restored from the launch snapshot.
    func game(_ id: String) -> SportsGame? { sportsData.index.games[id] ?? homeSports.games.first { $0.id == id } }
    func watchGame(_ game: SportsGame, feed: Channel? = nil, source: String? = nil) {
        let available = feeds(for: game.id, playableOnly: true)
        if let feed, !available.contains(where: { $0.id == feed.id }) {
            inform("Stream unavailable", "This stream is no longer matched to this game. Choose another stream."); return
        }
        let saved: String = personal.value("sports.feed.\(game.id)", default: "")
        guard let chosen = feed.flatMap({ requested in available.first { $0.id == requested.id } }) ?? available.first(where: { $0.id == saved }) ?? available.first else {
            inform("No stream available now", "This game has no current matching feed in your lineup."); return
        }
        if let feed { set("sports.feed.\(game.id)", feed.id) }
        play(chosen, gameID: game.id, explicitFeed: true, source: source)
    }
    var playerFeeds: [Channel] {
        guard let channel = playback.channel else { return [] }
        let available = activeSportsGameID.map { feeds(for: $0, playableOnly: true) } ?? variants(of: channel)
        return available.contains(where: { $0.id == channel.id }) ? available : [channel] + available
    }
    func selectPlayerFeed(_ id: String) {
        guard let feed = playerFeeds.first(where: { $0.id == id }), feed.id != playback.channel?.id else { return }
        if let gameID = activeSportsGameID, let game = sportsData.index.games[gameID] { watchGame(game, feed: feed) }
        else { play(feed, explicitFeed: true) }
    }
    func splitVariants(of channel: Channel) {
        do {
            var updates: [String: Data?] = [:]
            for variant in variants(of: channel) {
                updates[key(variant, "variants")] = try JSONEncoder().encode([variant.id])
                updates[key(variant, "manual.variants")] = try JSONEncoder().encode(true)
                updates.updateValue(nil, forKey: key(variant, "preferredVariant"))
            }
            try personal.write(updates); rebuild()
        } catch { inform("Variants weren’t separated", error.localizedDescription) }
    }
    private func offerAlternate() {
        guard let channel = playback.channel else { return }
        let available = variants(of: channel).filter { $0.id != channel.id }
        if !available.isEmpty {
            playback.errorMessage = (playback.errorMessage ?? "This stream couldn’t reconnect.") + " Choose another stream below."
        }
    }

    func prepareOrganization(useCachedAI: Bool = true) {
        guard organizationRevision != queryRevision || organizationUsesCachedAI != useCachedAI else { return }
        organizationPreparation?.cancel()
        organizationRevision = queryRevision
        organizationUsesCachedAI = useCachedAI
        let revision = queryRevision, channels = channels, decisions = catalog.decisions
        preparingOrganization = true
        organizationPreparation = Task { [weak self] in
            do {
                let result = try await catalogWork {
                    let suggestions = ChannelOrganizer.metadataSuggestions(channels).map { suggestion in
                        guard useCachedAI, let cached = decisions[suggestion.channelID], cached.fingerprint == suggestion.fingerprint else { return suggestion }
                        return cached
                    }
                    try Task.checkCancellation()
                    return (suggestions, ChannelOrganizer.variantGroups(channels))
                }
                guard !Task.isCancelled, let self, self.queryRevision == revision else { return }
                self.suggestions = result.0
                self.suggestionRevision += 1
                self.variantGroups = result.1
                self.preparingOrganization = false
            } catch {
                guard let self, self.queryRevision == revision else { return }
                self.preparingOrganization = false
            }
        }
    }
    func waitForOrganization() async { await organizationPreparation?.value }
    /// Processes a bounded set and checkpoints every batch. Browsing never
    /// awaits this task, and another run only picks up new/changed groups.
    func organizeGroups(limit: Int = 40, selecting groupIDs: Set<String>? = nil) {
        guard organizeTask == nil, !organization.isRunning, let groups = directory?.nameGroups else { return }
        guard personal.value("preferences.cloudAI", default: false) else {
            inform("Cloud processing is off", "Enable Jev in Organizer to classify shared channel titles."); return
        }
        let candidates = groups.pending(in: organizationAudience)
        let inputs = Array(candidates.filter { groupIDs?.contains($0.id) ?? true }.prefix(max(0, min(limit, 100_000))))
        guard !inputs.isEmpty else { return }
        startOrganization(GroupOrganizationRun(groupIDs: inputs.map(\.id)))
    }
    func resumeOrganization() {
        guard organizeTask == nil, !organization.isRunning, let run = organization.run else { return }
        #if DEBUG
        if demo, ProcessInfo.processInfo.arguments.contains("--demo-organization-progress") { startDemoOrganization(run); return }
        #endif
        startOrganization(run)
    }
    private func startOrganization(_ run: GroupOrganizationRun) {
        guard personal.value("preferences.cloudAI", default: false), intelligence.jevConfigured else {
            inform("Connect Jev", "Enable Jev in AI settings before continuing."); return
        }
        guard !organizationPaths.isEmpty else {
            inform("Choose your categories", "Add the category choices you want in AI settings before organizing."); return
        }
        do { try organization.prepare(run, persist: !demo) }
        catch { inform("Progress could not be saved", safeError(error)); return }
        organization.beginBackgroundWork(start: { [weak self] in self?.performOrganization() }, expired: { [weak self] in
            self?.cancelOrganization(message: "Stopped by iOS or the Live Activity. Completed groups are saved.")
        })
    }
    private func performOrganization() {
        guard organizeTask == nil, organization.isRunning else { return }
        organizeTask = Task {
            defer { organizeTask = nil; rebuild() }
            do {
                let model = try intelligence.jevModel()
                let namer = AppleCloudGroupNamer(enabled: intelligence.pccConfigured)
                while let run = organization.run, !run.isComplete {
                    try Task.checkCancellation()
                    guard personal.value("preferences.cloudAI", default: false) else { throw CancellationError() }
                    await waitForCatalog()
                    guard let groups = directory?.nameGroups else { throw CancellationError() }
                    let ids = Array(run.remainingIDs.prefix(32))
                    let audience = organizationAudience
                    let batch = ids.compactMap { groups.byID[$0] }.filter { group in
                        guard audience.includes(language: group.language, region: group.region) else { return false }
                        let saved: GroupPlacement? = personal.value("taxonomy.placement.\(group.id)", default: nil)
                        return saved?.isReusable(for: group) != true
                    }
                    let pendingIDs = Set(batch.map(\.id))
                    try organization.checkpoint(ids.filter { !pendingIDs.contains($0) }, persist: !demo)
                    if batch.isEmpty { continue }
                    let taxonomy = personal.has("preferences.organizationPaths") ? GroupTaxonomy(paths: organizationPaths) : groups.taxonomy
                    let result = try await GroupOrganizationPipeline.classify(batch, taxonomy: taxonomy, model: model, namer: namer)
                    try Task.checkCancellation()
                    guard personal.value("preferences.cloudAI", default: false) else { throw CancellationError() }
                    await waitForCatalog()
                    var updates: [String: Data?] = [:]
                    var checked: [String] = []
                    for placement in result {
                        guard let current = directory?.nameGroups.byID[placement.id], organizationAudience.includes(language: current.language, region: current.region) else {
                            checked.append(placement.id); continue
                        }
                        // A changed provider context is checked with fresh inputs on the next batch.
                        guard current.fingerprint == placement.fingerprint else { continue }
                        // A manual correction arriving while a request is in flight wins.
                        let key = "taxonomy.placement.\(placement.id)"
                        let existing: GroupPlacement? = personal.value(key, default: nil)
                        checked.append(placement.id)
                        if existing?.isReusable(for: current) == true { continue }
                        updates[key] = try JSONEncoder().encode(placement)
                    }
                    if !updates.isEmpty { try personal.write(updates) }
                    // Decisions are durable before advancing the local run cursor.
                    try organization.checkpoint(checked, persist: !demo)
                }
                try organization.finish(persist: !demo)
            } catch is CancellationError {
                if organization.isRunning { organization.pause() }
            } catch {
                organization.pause("Completed groups are saved. Resume when ready.")
                inform("Organization paused", safeError(error))
            }
        }
    }
    func setGroupPath(_ group: CatalogNameGroup, path: [String]) {
        guard !path.isEmpty, path.count <= 4, path.allSatisfy(GroupNames.validLabel) else {
            inform("Check the category name", "Use up to four short category names, separated by /. Each name can contain letters, numbers, spaces, an apostrophe, an ampersand, or a hyphen."); return
        }
        let canonical = directory?.nameGroups.taxonomy.canonical(path) ?? path
        do {
            var updates: [String: Data?] = ["taxonomy.placement.\(group.id)": try JSONEncoder().encode(GroupPlacement(group: group, path: canonical, confidence: 1, status: .classified, origin: "Your correction", manual: true))]
            if personal.has("preferences.organizationPaths"), !organizationPaths.contains(canonical) {
                updates["preferences.organizationPaths"] = try JSONEncoder().encode(organizationPaths + [canonical])
            }
            try personal.write(updates); rebuild()
        } catch { inform("Correction could not be saved", safeError(error)) }
    }
    func retryGroup(_ group: CatalogNameGroup) { remove("taxonomy.placement.\(group.id)") }
    func cancelOrganization(message: String = "Progress saved. Resume when ready.") {
        organizeTask?.cancel()
        if organization.isRunning { organization.pause(message) }
    }
    func organizationEnteredBackground() {
        if organization.isRunning && !organization.backgroundActive { cancelOrganization() }
    }
    func waitForGroupOrganization() async {
        while organization.isRunning && organizeTask == nil { try? await Task.sleep(for: .milliseconds(50)) }
        await organizeTask?.value
    }
    #if DEBUG
    /// Exercises Apple's actual background execution and Live Activity on a
    /// physical device using labeled sample work, with no cloud model requests.
    private func startDemoOrganization(_ saved: GroupOrganizationRun? = nil) {
        let run = saved ?? GroupOrganizationRun(groupIDs: (0..<40).map { "sample-group-\($0)" })
        try? organization.prepare(run, persist: false)
        organization.beginBackgroundWork(start: { [weak self] in
            guard let self else { return }
            self.organizeTask = Task {
                defer { self.organizeTask = nil }
                do {
                    for id in run.remainingIDs {
                        try await Task.sleep(for: .seconds(3))
                        try self.organization.checkpoint([id], persist: false)
                    }
                    try self.organization.finish(persist: false)
                } catch { if self.organization.isRunning { self.organization.pause() } }
            }
        }, expired: { [weak self] in self?.cancelOrganization() })
    }
    #endif
    func applySuggestions(_ selected: [ChannelSuggestion], includeVariants: Bool) {
        do {
            var changes: [String: Data?] = [:]
            for suggestion in ChannelOrganizer.validate(selected, channels: channels) {
                guard let channel = channelIndex[suggestion.channelID] else { continue }
                let fields = [("category", suggestion.category == .unknown ? "" : suggestion.category.rawValue), ("language", suggestion.language), ("region", suggestion.region)]
                for (field, value) in fields where !value.isEmpty && !flag(channel, "manual.\(field)") {
                    changes[key(channel, field)] = try JSONEncoder().encode(value)
                }
            }
            if includeVariants {
                for candidates in variantGroups {
                    let group = candidates.filter { !personal.value("channel.\($0).manual.variants", default: false) }
                    guard group.count > 1 else { continue }
                    for id in group { changes["channel.\(id).variants"] = try JSONEncoder().encode(group) }
                }
            }
            let mutationID = UUID().uuidString
            let undo = changes.map { UndoChange(key: $0.key, before: personal.raw($0.key), applied: $0.value, appliedMutationID: mutationID) }
            changes["organizer.undo"] = try JSONEncoder().encode(undo)
            try personal.write(changes, mutationID: mutationID); rebuild()
            inform("Lineup updated", "Applied \(undo.count) organization changes. Your manual corrections were preserved. Undo is available in Organizer.")
        } catch { inform("Organization wasn’t saved", error.localizedDescription) }
    }
    func undoOrganization() {
        let changes: [UndoChange] = personal.value("organizer.undo", default: [])
        do {
            personal.reload()
            var updates = PersonalLedger.undo(changes, current: personal.ledger)
            updates.updateValue(nil, forKey: "organizer.undo")
            try personal.write(updates); rebuild()
        } catch { inform("Undo unavailable", error.localizedDescription) }
    }
    func clearHistory() {
        do { try personal.write(Dictionary(uniqueKeysWithValues: personal.keys(prefix: "history.").map { ($0, Optional<Data>.none) })); rebuild() }
        catch { inform("History wasn’t cleared", error.localizedDescription) }
    }
    func removeFromHistory(_ channel: Channel) {
        remove("history.\(channel.id)")
    }
    func inform(_ title: String, _ message: String) { notice = AppNotice(title: title, message: message) }
    func safeError(_ error: Error) -> String {
        if let error = error as? URLError, error.code == .appTransportSecurityRequiresSecureConnection {
            return "This build blocked the provider’s HTTP connection before the login could be checked. Update mySportly, then try again."
        }
        if error is URLError { return "The network request failed. Check your connection and the source address, then try again." }
        if error is DecodingError { return "The source returned data in an unexpected format. Check your provider details." }
        return (error as? LocalizedError)?.errorDescription ?? "The operation couldn’t be completed. Your saved choices were retained."
    }
    func updateWidgetSnapshot() {
        guard let directory else { return }
        widgetTask?.cancel()
        let guide = guideIndex, channelsByID = channelIndex, overrides = personal.snapshotValues(), date = clock, guideMatches = guideMatches
        widgetTask = Task {
            do {
                let snapshot = try await catalogWork {
                    let decoder = JSONDecoder()
                    let rows = try directory.visibleNames.enumerated().map { position, row in
                        if position.isMultiple(of: 256) { try Task.checkCancellation() }
                        let channel = channelsByID[row.id]!
                        let key = "channel.\(row.id)."
                        let guideID = overrides[key + "guideID"].flatMap { try? decoder.decode(String.self, from: $0) } ?? guideMatches[channel.id]?.guideID ?? channel.guideID
                        let offset = overrides[key + "guideOffset"].flatMap { try? decoder.decode(Int.self, from: $0) } ?? 0
                        let title = guide[channel.sourceID.uuidString + "|" + guideID]?.first { $0.isLive(at: date - Double(offset) * 60) }?.title
                        return SharedChannel(id: row.id, name: row.name, program: title)
                    }
                    return SharedLineup(updatedAt: date, channels: rows, favorites: directory.favorites.map(\.id))
                }
                try Task.checkCancellation()
                await WidgetBridge.save(snapshot)
            } catch { /* A newer snapshot superseded this export. */ }
        }
    }
    func updateIntentCatalog() {
        guard let directory, catalogReady else { return }
        intentCatalogTask?.cancel()
        let library = savedLibraryItems, audience = organizationAudience
        intentCatalogTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let snapshot = try await catalogWork {
                    var request = ChannelBrowseRequest(); request.audience = audience; request.excludeInactive = true
                    let saved = Set(library.filter { $0.kind == .channel }.map(\.reference))
                    let preferred = Set(try directory.browse(request).map(\.id)).union(saved)
                    let channels = directory.visibleNames.filter { preferred.contains($0.id) }.map { SharedChannel(id: $0.id, name: $0.name, program: nil) }
                    return IntentCatalog(channels: channels, library: library)
                }
                try Task.checkCancellation()
                try await IntentCatalogRepository.shared.save(snapshot)
                SportlyShortcuts.updateAppShortcutParameters()
            } catch { /* A newer snapshot or system indexing retry will follow. */ }
        }
    }
    func route(_ url: URL) {
        guard url.scheme == "mysportly" else { return }
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let id = values.first { $0.name == "id" }?.value
        switch url.host {
        case "guide": selectedTab = .guide
        case "search": searchRequest = values.first { $0.name == "query" }?.value ?? ""; selectedTab = .search
        case "refresh": selectedTab = .home; Task { await refreshDueSources(force: true) }
        case "library":
            selectedTab = .myStuff
            if let id, let item = savedLibraryItems.first(where: { $0.id == id }) { libraryRoute = item }
            else { inform("Saved item unavailable", "This item is no longer in your Library.") }
        case "save":
            if let id, let channel = channelIndex[id] { saveLibraryItem(bookmark(channel)); selectedTab = .myStuff }
            else { inform("Channel unavailable", "This channel is no longer in the current playlist.") }
        default: break
        }
        if url.host == "play", let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value {
            if let channel = channelIndex[id] { play(channel) }
            else { inform("Channel unavailable", "This channel is no longer in the current lineup. Refresh its source or choose another channel.") }
        }
    }
    var refreshSchedule: RefreshSchedule {
        RefreshSchedule(playlist: RefreshFrequency(rawValue: personal.value("preferences.playlistRefresh", default: RefreshFrequency.daily.rawValue)) ?? .daily,
                        guide: RefreshFrequency(rawValue: personal.value("preferences.guideRefresh", default: RefreshFrequency.sixHours.rawValue)) ?? .sixHours)
    }
    func lastRefresh(_ source: TVSource, kind: SourceRefreshKind) -> Date? {
        kind == .playlist ? catalog.refreshed[source.id] : catalog.guideRefreshed[source.id]
    }
    private func attemptKey(_ source: TVSource, _ kind: SourceRefreshKind) -> String { "refreshAttempt.\(source.id).\(kind.rawValue)" }
    private func lastAttempt(_ source: TVSource, _ kind: SourceRefreshKind) -> Date? { UserDefaults.standard.object(forKey: attemptKey(source, kind)) as? Date }
    private func supportsGuide(_ source: TVSource) -> Bool {
        source.kind == .xtream || catalog.guideURLs[source.id] != nil || ((try? KeychainStore.credentials(source.id))?.guideAddress.isEmpty == false)
    }
    func scheduleSourceRefresh() {
        guard !demo else { return }
        let dates = sources.flatMap { source -> [Date] in
            let playlist = refreshSchedule.next(kind: .playlist, success: catalog.refreshed[source.id], attempt: lastAttempt(source, .playlist))
            let guide = supportsGuide(source) ? refreshSchedule.next(kind: .guide, success: catalog.guideRefreshed[source.id], attempt: lastAttempt(source, .guide)) : nil
            return [playlist, guide].compactMap { $0 }
        }
        backgroundRefresh.schedule(at: dates.min())
    }
    @discardableResult func refreshDueSources(force: Bool = false) async -> Bool {
        guard catalogReady, !demo, !refreshBatchRunning, importTask == nil, !Task.isCancelled else { return false }
        refreshBatchRunning = true
        refreshMessage = nil
        defer { refreshBatchRunning = false; scheduleSourceRefresh() }
        var success = true
        for source in sources {
            guard !Task.isCancelled else { return false }
            let due = force ? SourceRefreshKind.playlist : refreshSchedule.due(
                playlistSuccess: catalog.refreshed[source.id], guideSuccess: catalog.guideRefreshed[source.id],
                playlistAttempt: lastAttempt(source, .playlist), guideAttempt: lastAttempt(source, .guide),
                supportsGuide: supportsGuide(source), at: .now)
            guard let kind = due else { continue }
            UserDefaults.standard.set(Date.now, forKey: attemptKey(source, kind))
            if kind == .playlist { UserDefaults.standard.set(Date.now, forKey: attemptKey(source, .guide)) }
            guard importTask == nil, let secrets = try? KeychainStore.credentials(source.id) else {
                refreshMessage = "Connection details are unavailable for one of your sources."; success = false; continue
            }
            connect(source, secrets: secrets, persistConfiguration: false, kind: kind, quiet: !force)
            let result = await withTaskCancellationHandler {
                await importTask?.value ?? false
            } onCancel: {
                Task { @MainActor in self.cancelImport() }
            }
            success = result && success
        }
        if success && !Task.isCancelled { refreshMessage = "Your sources are up to date." }
        return success && !Task.isCancelled
    }

}
