import Foundation
import Testing
@testable import mySportly

@MainActor @Suite(.serialized) struct AppStateTests {
    @Test func followsMigrateOnceAndOldListsNeverResurrectRemovedTeams() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        let revision = store.queryRevision
        store.set("preferences.teams", ["Knicks", "New York Knicks"])
        store.set("preferences.leagues", ["NFL"])
        store.runFollowMigration()
        let knicks = SportsLibraryItem(name: "Knicks", kind: .team)
        let cowboys = SportsLibraryItem(name: "Cowboys", kind: .team)
        let nfl = SportsLibraryItem(name: "NFL", kind: .league)
        #expect(store.followedTeams.filter { $0.name == "New York Knicks" }.count == 1, "Aliases migrate to one follow")
        #expect(store.addedLeagues == [nfl])
        #expect(!store.isFollowing(cowboys), "Adding a league does not follow its teams")
        let before = store.sportsLibrary
        store.follow(SportsLibraryItem(name: " --- ", kind: .team))
        #expect(store.sportsLibrary == before, "Names without letters or numbers are ignored")
        store.follow(cowboys)
        #expect(store.isFollowing(cowboys))
        store.unfollow(knicks)
        store.personal.reload()
        #expect(!store.isFollowing(knicks), "Old follow arrays must not resurrect a removed team")
        store.follow(knicks)
        #expect(store.isFollowing(knicks))
        #expect(store.notice == nil)
        await store.waitForCatalog()
        #expect(store.queryRevision == revision, "Following must not rebuild the channel catalog")
    }
    @Test func removingOneRecentPreservesTheChannelFavoritesAndOtherHistory() async throws {
        let store = AppStore(inMemory: true); await store.loadDemo()
        let first = store.channels[0], second = store.channels[1]
        store.set("history.\(first.id)", Date.now)
        store.set("history.\(second.id)", Date.now)
        store.toggle(first, "favorite"); await store.waitForCatalog()
        let revision = store.queryRevision
        store.removeFromHistory(first); await store.waitForCatalog()
        #expect(store.recent.map(\.id) == [second.id])
        #expect(store.channelIndex[first.id] != nil)
        #expect(store.flag(first, "favorite"))
        #expect(store.queryRevision == revision)
        store.personal.reload()
        #expect(!store.personal.has("history.\(first.id)"))
        #expect(!store.recommendationPreferences.watched.contains(first.id))
    }
    @Test func preferredLineupUsesSavedChoicesWithoutRebuildingTheCatalog() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        store.set("preferences.languages", ["en"])
        store.set("preferences.regions", ["US"])
        let revision = store.queryRevision, directory = try #require(store.directory)
        var request = ChannelBrowseRequest(); request.audience = store.audience
        #expect(store.lineupScope == .preferred)
        #expect(try directory.browse(request).count == 4)
        store.set("preferences.lineupScope", LineupScope.all.rawValue)
        request.audience = store.audience
        #expect(try directory.browse(request).count == 7)
        #expect(store.organizationAudience.scope == .preferred)
        #expect(!store.organizationAudience.includes(language: "en", region: "GB"))
        #expect(!store.organizationAudience.includes(language: "es", region: "US"))
        #expect(store.organizationAudience.includes(language: "en", region: "US"))
        await store.waitForCatalog()
        #expect(store.queryRevision == revision)
    }
    @Test func appearanceAndStartTabDoNotRebuildTheCatalog() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        let revision = store.queryRevision
        store.set("preferences.appearance", "Dark")
        store.set("preferences.startTab", "Search")
        store.set("group.fixture", ChannelGroup(name: "Fixture", channelIDs: []))
        await store.waitForCatalog()
        #expect(store.queryRevision == revision)
        #expect(!store.preparingCatalog)
        store.edit(try #require(store.channels.first), fields: ["name": "Renamed", "category": "News"])
        await store.waitForCatalog()
        #expect(store.queryRevision == revision + 1)
    }
    @Test func queryIndexPublishesOnlyTheLatestLineupAndPersonalEdits() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        let channel = try #require(store.channels.first)
        let hidden = try #require(store.channels.last)
        store.edit(channel, field: "name", value: "Superseded Name")
        store.edit(channel, field: "name", value: "Current Name")
        store.toggle(channel, "favorite")
        store.toggle(hidden, "hidden")
        await store.waitForCatalog()
        let index = try #require(store.queryIndex)
        let matches = try index.search(.init(keywords: ["Current Name"], start: .now, end: .now + 1, favoritesOnly: true))
        #expect(matches.map(\.id) == [channel.id])
        #expect(index.channelCount == store.lineup.count)
        #expect(!store.lineup.contains { $0.id == hidden.id })
        #expect(store.favorites.contains { $0.id == channel.id })
        #expect(try index.search(.init(keywords: ["Superseded"], start: .now, end: .now + 1)).isEmpty)
    }

    @Test func restorationWaitsForTheSavedCatalogToFinishLoading() async throws {
        let store = AppStore(inMemory: true)
        let source = TVSource(name: "Startup restoration check", kind: .xtream)
        try store.personal.set("source.\(source.id)", source)
        // An invalid, local-only fixture fails immediately if restoration starts.
        // It must never contact a server or overwrite the user's saved catalog.
        try KeychainStore.save(SourceSecrets(), sourceID: source.id, sync: false)
        defer { try? KeychainStore.remove("source.\(source.id)") }
        await store.restoreMissingSources()
        #expect(store.notice == nil, "The saved catalog is still loading; do not start another import.")
        #expect(store.importingSource == nil)

        store.loading = false
        store.catalogReady = true
        store.notice = nil
        await store.restoreMissingSources()
        #expect(store.notice?.title == "Couldn’t connect", "A genuinely missing source must still be restored after loading.")
    }

    @Test func transportPolicyFailureIsExplainedWithoutExposingTheURL() {
        let store = AppStore(inMemory: true)
        let error = URLError(.appTransportSecurityRequiresSecureConnection, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "http://example.invalid/player_api.php?password=private-test-value")!])
        let message = store.safeError(error)
        #expect(message.contains("blocked"))
        #expect(message.contains("before the login"))
        #expect(!message.contains("private-test-value"))
        #expect(!message.contains("example.invalid"))
    }

    @Test func unknownDownloadSizesStayIndeterminateAndLateUpdatesCannotReplaceSaving() {
        let unknown = TransferProgress(received: 12_000_000, expected: -1)
        #expect(unknown.fraction == nil)
        #expect(unknown.description.contains("downloaded"))
        #expect(TransferProgress(received: 25, expected: 100).fraction == 0.25)
        #expect(TransferProgress(received: 101, expected: 100).fraction == 1)

        let progress = SourceImportProgress(sourceName: "Test source")
        progress.receive(ImportUpdate(step: .guide, activity: "Downloading…", transfer: unknown, channelCount: 12))
        progress.beginSaving(ProviderImport(channels: [], programs: nil, guideWarning: "Unavailable"))
        progress.receive(ImportUpdate(step: .guide, activity: "Late callback", transfer: unknown))
        #expect(progress.update.step == .saving)
        #expect(progress.update.transfer == nil)
        #expect(progress.update.guide == .unavailable)
    }

    @Test func relevantGuidePrioritizesPreferencesWithoutHidingOtherChannels() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        store.set("preferences.languages", ["en"])
        store.set("preferences.regions", ["US"])
        let unknown = try #require(store.channels.first { $0.language.isEmpty })
        var request = ChannelBrowseRequest(); request.ranked = true; request.collapseVariants = true
        let directory = try #require(store.directory)
        let preferences = store.recommendationPreferences
        let rankedRequest = request
        let ranked = try await catalogWork { try directory.browse(rankedRequest, preferences: preferences) }
        let first = try #require(ranked.first)
        #expect(store.language(first) == "en")
        #expect(store.region(first) == "US")
        #expect(Set(ranked.map(\.id)) == Set(store.lineup.map(\.id)))
        store.toggle(unknown, "favorite")
        await store.waitForCatalog()
        let updated = try #require(store.directory)
        let updatedRanking = try await catalogWork { try updated.browse(rankedRequest, preferences: preferences) }
        #expect(updatedRanking.first?.id == unknown.id)
    }

    @Test func manualCorrectionSurvivesUndoEvenWhenItMatchesTheSuggestion() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        let channel = try #require(store.channels.first)
        let suggestion = ChannelSuggestion(channelID: channel.id, category: .sports, language: "en", region: "US", confidence: 1, reason: "Fixture", origin: "Test", fingerprint: ChannelOrganizer.fingerprint(channel))
        store.applySuggestions([suggestion], includeVariants: false)
        store.edit(channel, field: "category", value: "Sports")
        store.undoOrganization()
        #expect(store.category(channel) == "Sports")
        #expect(store.flag(channel, "manual.category"))
        #expect(!store.canUndo)
    }

    @Test func explicitVariantSeparationSurvivesAnotherOrganizerRun() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        let group = try #require(ChannelOrganizer.variantGroups(store.channels).first)
        let channel = try #require(store.channelIndex[group[0]])
        store.prepareOrganization()
        await store.waitForOrganization()
        store.applySuggestions([], includeVariants: true)
        #expect(store.variants(of: channel).count > 1)
        store.splitVariants(of: channel)
        store.applySuggestions([], includeVariants: true)
        #expect(store.variants(of: channel).map(\.id) == [channel.id])
        #expect(store.flag(channel, "manual.variants"))
    }

    @Test func liveProgramAdvancesWithTheAppClock() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        let channel = try #require(store.channels.first { !store.programs(for: $0).isEmpty })
        let first = try #require(store.programs(for: channel).first)
        store.clock = first.start
        #expect(store.now(on: channel)?.id == first.id)
        store.clock = first.end
        #expect(store.now(on: channel)?.id != first.id)
        #expect(store.now(on: channel)?.isLive(at: store.clock) == true)
    }

    @Test func sourceTombstoneRemovesItsCachedChannelsFromTheLineup() async throws {
        let store = AppStore(inMemory: true)
        await store.loadDemo()
        let source = SampleCatalog.source
        try store.personal.set("source.\(source.id)", source)
        store.demo = false; store.rebuild()
        await store.waitForCatalog()
        #expect(!store.channels.isEmpty)
        try store.personal.remove("source.\(source.id)")
        store.personal.reload(); store.rebuild()
        await store.waitForCatalog()
        #expect(store.channels.isEmpty)
        #expect(store.channelIndex.isEmpty)
    }
}
