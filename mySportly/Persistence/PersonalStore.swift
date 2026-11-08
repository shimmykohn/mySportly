import Foundation
import SwiftData
import CloudKit
import CoreData
import Observation
#if SWIFT_PACKAGE
import SportlyCore
#endif

/// Immutable per-field events avoid whole-profile overwrites when two devices edit offline.
/// Tombstones remain in the private store so a late device cannot resurrect a deletion.
@Model final class PersonalEntry {
    var mutationID: String = UUID().uuidString
    var key: String = ""
    var payload: Data?
    var modifiedAt: Date = Date.now
    var deleted: Bool = false
    init(key: String, payload: Data?, deleted: Bool = false) {
        self.key = key; self.payload = payload; self.deleted = deleted
    }
}

@MainActor @Observable final class PersonalStore {
    private(set) var revision = 0
    private(set) var catalogRevision = 0
    private(set) var storageError: String?
    private(set) var cloudStatus = "Checking iCloud…"
    private(set) var cloudConfigured = false
    private(set) var isSyncing = false
    @ObservationIgnored private var cloudEvents = Set<UUID>()
    @ObservationIgnored private var cloudStatusChecks = 0
    private var cloudFailure: String?
    private var lastCloudActivity: Date?
    private(set) var cloudRequested: Bool
    private let launchedWithCloud: Bool
    private let defaults: UserDefaults
    private var container: ModelContainer?
    private var values: [String: Data] = [:]
    private(set) var ledger: [String: LedgerValue] = [:]
    static let cloudIdentifier = "iCloud.app.iska.mysportly"

    init(inMemory: Bool = false, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let requested = defaults.object(forKey: "personalCloudSync") as? Bool ?? true
        cloudRequested = requested; launchedWithCloud = requested
        let schema = Schema([PersonalEntry.self])
        let cloudEnabled = !inMemory && cloudRequested && Bundle.main.object(forInfoDictionaryKey: "SportlyCloudEnabled") as? Bool == true
        let configuration = ModelConfiguration("Personal", schema: schema, isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudEnabled ? .private(Self.cloudIdentifier) : .none)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            cloudConfigured = cloudEnabled
        } catch {
            // Same store name keeps local personal data when a cloud capability cannot initialize.
            do {
                container = try ModelContainer(for: schema, configurations: [ModelConfiguration("Personal", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)])
                cloudStatus = "Using local storage. iCloud could not be initialized."
            } catch { storageError = "Personal storage could not be opened. Changes cannot be saved." }
        }
        reload()
        if !cloudEnabled { cloudStatus = cloudRequested ? "Local storage. iCloud is unavailable in this session." : "Personal choices are stored on this device." }
    }

    @discardableResult func reload() -> Bool {
        guard let container else { return false }
        do {
            let records = try ModelContext(container).fetch(FetchDescriptor<PersonalEntry>())
            let resolved = PersonalLedger.resolve(records.map { LedgerRecord(key: $0.key, value: LedgerValue(payload: $0.deleted ? nil : $0.payload, mutationID: $0.mutationID, modifiedAt: $0.modifiedAt)) })
            guard resolved != ledger else { return false }
            let changedKeys = Set(ledger.keys).union(resolved.keys).filter { ledger[$0] != resolved[$0] }
            if changedKeys.contains(where: Self.affectsCatalog) { catalogRevision += 1 }
            ledger = resolved
            values = ledger.compactMapValues(\.payload)
            revision += 1
            return true
        } catch { storageError = "Personal data could not be read. Your existing store has been retained."; return false }
    }

    func value<T: Decodable>(_ key: String, default fallback: T) -> T {
        _ = revision
        guard let data = values[key], let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
    func has(_ key: String) -> Bool { _ = revision; return values[key] != nil }
    func keys(prefix: String) -> [String] { _ = revision; return values.keys.filter { $0.hasPrefix(prefix) } }
    func raw(_ key: String) -> Data? { _ = revision; return values[key] }
    func snapshotValues() -> [String: Data] { values }
    func version(_ key: String) -> String? { _ = revision; return ledger[key]?.mutationID }
    var syncChangeNeedsRelaunch: Bool { launchedWithCloud != cloudRequested }
    func requestCloudSync(_ enabled: Bool) {
        cloudRequested = enabled
        defaults.set(enabled, forKey: "personalCloudSync")
    }
    func set<T: Encodable>(_ key: String, _ value: T) throws { try write([key: try JSONEncoder().encode(value)]) }
    func remove(_ key: String) throws { try write([key: nil]) }
    func write(_ updates: [String: Data?], mutationID: String = UUID().uuidString) throws {
        guard let container else { throw StorageFailure.unavailable }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        // Advance from the most recent known event, including after a local clock adjustment.
        let timestamp = max(Date.now, (ledger.values.map(\.modifiedAt).max() ?? .distantPast).addingTimeInterval(0.000001))
        for (key, payload) in updates {
            let entry = PersonalEntry(key: key, payload: payload, deleted: payload == nil)
            entry.mutationID = mutationID; entry.modifiedAt = timestamp
            context.insert(entry)
        }
        try context.save()
        for (key, payload) in updates {
            ledger[key] = LedgerValue(payload: payload, mutationID: mutationID, modifiedAt: timestamp)
            if let payload { values[key] = payload } else { values.removeValue(forKey: key) }
        }
        revision += 1
        if updates.keys.contains(where: Self.affectsCatalog) { catalogRevision += 1 }
    }
    private static func affectsCatalog(_ key: String) -> Bool { key.hasPrefix("channel.") || key.hasPrefix("source.") || key.hasPrefix("taxonomy.") }
    func refreshCloudStatus() async {
        guard cloudConfigured else { return }
        cloudStatusChecks += 1; updateSyncActivity()
        defer { cloudStatusChecks -= 1; updateSyncActivity() }
        do {
            switch try await CKContainer(identifier: Self.cloudIdentifier).accountStatus() {
            case .available: cloudStatus = cloudFailure ?? lastCloudActivity.map { "Last iCloud activity: \($0.formatted(date: .abbreviated, time: .shortened))." } ?? "iCloud account available. Waiting for the first sync."
            case .noAccount: cloudStatus = "Sign in to iCloud in device Settings. Local changes are saved."
            case .restricted: cloudStatus = "iCloud is restricted on this device. Local changes are saved."
            case .temporarilyUnavailable: cloudStatus = "iCloud is temporarily unavailable. Local changes are saved."
            case .couldNotDetermine: cloudStatus = "iCloud status could not be determined."
            @unknown default: cloudStatus = "iCloud status is unavailable."
            }
        } catch { cloudStatus = "iCloud connection unavailable. Local changes are saved." }
        reload()
    }
    func handleCloudEvent(_ event: NSPersistentCloudKitContainer.Event) {
        guard cloudConfigured else { return }
        if event.endDate == nil { cloudEvents.insert(event.identifier) }
        else { cloudEvents.remove(event.identifier) }
        updateSyncActivity()
        guard event.endDate != nil else { return }
        if event.error != nil {
            cloudFailure = "iCloud could not finish syncing. Your changes are saved on this device."
            cloudStatus = cloudFailure!
        } else if event.succeeded {
            cloudFailure = nil
            if event.type == .import || event.type == .export {
                lastCloudActivity = event.endDate
                cloudStatus = "Last iCloud activity: \(event.endDate!.formatted(date: .abbreviated, time: .shortened))."
            } else { cloudStatus = "iCloud connection ready. Waiting for data to sync." }
        }
    }
    private func updateSyncActivity() { isSyncing = cloudStatusChecks > 0 || !cloudEvents.isEmpty }
    enum StorageFailure: Error, LocalizedError {
        case unavailable
        var errorDescription: String? { "Personal storage is unavailable. No changes were saved." }
    }
}
