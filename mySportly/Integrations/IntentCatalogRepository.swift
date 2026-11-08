import Foundation
import CoreSpotlight
import AppIntents

struct IntentCatalog: Codable, Sendable, Equatable {
    var channels: [SharedChannel] = []
    var library: [LibraryBookmark] = []
}

/// A local, credential-free catalog for the system. Parsing and filtering stay
/// off the main actor; Spotlight receives saved items, not the whole playlist.
actor IntentCatalogRepository {
    static let shared = IntentCatalogRepository()
    private var cached = IntentCatalog()
    private var modified: Date?
    private var indexed: [LibraryBookmark]?
    private var file: URL? { WidgetBridge.directory?.appending(path: "siri-catalog.json") }
    func read() -> IntentCatalog {
        guard let file, let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return IntentCatalog() }
        if date == modified { return cached }
        guard let data = try? Data(contentsOf: file), data.count < 32_000_000, let snapshot = try? JSONDecoder().decode(IntentCatalog.self, from: data) else { return IntentCatalog() }
        modified = date; cached = snapshot; return snapshot
    }
    func save(_ snapshot: IntentCatalog) async throws {
        guard let file else { return }
        if snapshot == cached, indexed == snapshot.library, FileManager.default.fileExists(atPath: file.path) { return }
        try Task.checkCancellation()
        try JSONEncoder().encode(snapshot).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        cached = snapshot; modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard indexed != snapshot.library else { return }
        let index = CSSearchableIndex(name: "mySportly.Library")
        let old = indexed ?? []
        let ids = Set(snapshot.library.map(\.id))
        // A full replacement of this small, dedicated index removes entries
        // deleted on other devices or during a previous app session.
        if indexed == nil { try await index.deleteAllSearchableItems() }
        else { try await index.deleteAppEntities(identifiedBy: old.filter { !ids.contains($0.id) }.map(\.id), ofType: LibraryEntity.self) }
        for start in stride(from: 0, to: snapshot.library.count, by: 200) {
            try Task.checkCancellation()
            try await index.indexAppEntities(snapshot.library[start..<min(start + 200, snapshot.library.count)].map(LibraryEntity.init))
        }
        indexed = snapshot.library
    }
}
