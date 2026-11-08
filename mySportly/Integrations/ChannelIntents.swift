import AppIntents
import CoreSpotlight

struct ChannelEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "TV Channel"
    static var defaultQuery = ChannelEntityQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", image: .init(systemName: "tv")) }
}
struct ChannelEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ChannelEntity] {
        let wanted = Set(identifiers)
        return await IntentCatalogRepository.shared.read().channels.filter { wanted.contains($0.id) }.map { .init(id: $0.id, name: $0.name) }
    }
    func entities(matching string: String) async throws -> [ChannelEntity] {
        let channels = await IntentCatalogRepository.shared.read().channels
        return channels.filter { $0.name.localizedStandardContains(string) }.prefix(40).map { .init(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [ChannelEntity] {
        let snapshot = await IntentCatalogRepository.shared.read()
        let saved = Set(snapshot.library.filter { $0.kind == .channel }.map(\.reference))
        let channels = snapshot.channels.filter { saved.contains($0.id) }
        return (channels.isEmpty ? snapshot.channels : channels).prefix(12).map { .init(id: $0.id, name: $0.name) }
    }
}
struct PlayChannelIntent: AppIntent {
    static var title: LocalizedStringResource = "Play a Channel"
    static var description = IntentDescription("Play a channel from your preferred lineup or Library.")
    static var supportedModes: IntentModes { .foreground }
    @Parameter(title: "Channel") var channel: ChannelEntity
    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$channel)") }
    @MainActor func perform() async throws -> some IntentResult {
        AppRouteInbox.queue(WidgetBridge.playURL(channel.id)); return .result()
    }
}

@AppIntent(schema: .system.searchInApp)
struct SearchTVIntent {
    static var title: LocalizedStringResource = "Search TV"
    static var supportedModes: IntentModes { .foreground }
    var criteria: StringSearchCriteria
    @MainActor func perform() async throws -> some IntentResult {
        AppRouteInbox.queue(AppRouteInbox.url("search", name: "query", value: criteria.term)); return .result()
    }
}

struct LibraryEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Saved TV Item"
    static var defaultQuery = LibraryEntityQuery()
    var id: String
    var name: String
    var kind: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(kind)", image: .init(systemName: "square.stack")) }
    var searchableAttributes: CSSearchableItemAttributeSet {
        let result = CSSearchableItemAttributeSet(contentType: .content)
        result.title = name; result.contentDescription = "\(kind) in your mySportly Library"
        return result
    }
    init(_ item: LibraryBookmark) { id = item.id; name = item.name; kind = item.kind.rawValue }
}
struct LibraryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [LibraryEntity] {
        let ids = Set(identifiers)
        return await IntentCatalogRepository.shared.read().library.filter { ids.contains($0.id) }.map(LibraryEntity.init)
    }
    func entities(matching string: String) async throws -> [LibraryEntity] {
        await IntentCatalogRepository.shared.read().library.filter { $0.name.localizedStandardContains(string) }.map(LibraryEntity.init)
    }
    func suggestedEntities() async throws -> [LibraryEntity] { await IntentCatalogRepository.shared.read().library.prefix(12).map(LibraryEntity.init) }
}
@AppIntent(schema: .system.open)
struct OpenSavedItemIntent {
    static var title: LocalizedStringResource = "Open Saved Item"
    static var supportedModes: IntentModes { .foreground }
    var target: LibraryEntity
    @MainActor func perform() async throws -> some IntentResult {
        AppRouteInbox.queue(AppRouteInbox.url("library", name: "id", value: target.id)); return .result()
    }
}
struct SaveChannelIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Channel to Library"
    static var supportedModes: IntentModes { .foreground }
    @Parameter(title: "Channel") var channel: ChannelEntity
    static var parameterSummary: some ParameterSummary { Summary("Save \(\.$channel) to Library") }
    @MainActor func perform() async throws -> some IntentResult {
        AppRouteInbox.queue(AppRouteInbox.url("save", name: "id", value: channel.id)); return .result()
    }
}
struct RefreshSourcesIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Playlist and Guide"
    static var description = IntentDescription("Open mySportly and refresh your sources. Your saved organization is reused.")
    static var supportedModes: IntentModes { .foreground }
    @MainActor func perform() async throws -> some IntentResult {
        AppRouteInbox.queue(URL(string: "mysportly://refresh")!); return .result()
    }
}
struct OpenGuideIntent: AppIntent {
    static var title: LocalizedStringResource = "Open TV Guide"
    static var supportedModes: IntentModes { .foreground }
    @MainActor func perform() async throws -> some IntentResult { AppRouteInbox.queue(URL(string: "mysportly://guide")!); return .result() }
}
struct SportlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayChannelIntent(), phrases: ["Play a channel in \(.applicationName)", "Watch \(\.$channel) in \(.applicationName)"], shortTitle: "Play Channel", systemImageName: "play.tv")
        AppShortcut(intent: SearchTVIntent(), phrases: ["Search TV in \(.applicationName)"], shortTitle: "Search TV", systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenSavedItemIntent(), phrases: ["Open a saved item in \(.applicationName)", "Open \(\.$target) in \(.applicationName)"], shortTitle: "Open Saved Item", systemImageName: "square.stack")
        AppShortcut(intent: SaveChannelIntent(), phrases: ["Save a channel in \(.applicationName)"], shortTitle: "Save Channel", systemImageName: "plus")
        AppShortcut(intent: RefreshSourcesIntent(), phrases: ["Refresh my playlist in \(.applicationName)"], shortTitle: "Refresh Sources", systemImageName: "arrow.clockwise")
        AppShortcut(intent: OpenGuideIntent(), phrases: ["Open the guide in \(.applicationName)"], shortTitle: "TV Guide", systemImageName: "list.bullet.rectangle")
    }
}
