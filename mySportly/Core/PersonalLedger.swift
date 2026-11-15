import Foundation

public struct LedgerValue: Equatable, Sendable {
    public var payload: Data?; public var mutationID: String; public var modifiedAt: Date
    public init(payload: Data?, mutationID: String, modifiedAt: Date) { self.payload = payload; self.mutationID = mutationID; self.modifiedAt = modifiedAt }
}
public struct LedgerRecord: Sendable {
    public var key: String; public var value: LedgerValue
    public init(key: String, value: LedgerValue) { self.key = key; self.value = value }
}
public struct UndoChange: Codable, Sendable { public var key: String; public var before: Data?; public var applied: Data?; public var appliedMutationID: String }
public enum PersonalLedger {
    public static func resolve(_ records: some Sequence<LedgerRecord>) -> [String: LedgerValue] {
        var latest: [String: LedgerValue] = [:]
        for record in records {
            if let existing = latest[record.key],
               existing.modifiedAt > record.value.modifiedAt ||
               (existing.modifiedAt == record.value.modifiedAt && existing.mutationID > record.value.mutationID) { continue }
            latest[record.key] = record.value
        }
        return latest
    }
    public static func undo(_ changes: [UndoChange], current: [String: LedgerValue]) -> [String: Data?] {
        var updates: [String: Data?] = [:]
        for change in changes where current[change.key]?.mutationID == change.appliedMutationID {
            updates.updateValue(change.before, forKey: change.key)
        }
        return updates
    }
}
public enum ImportPolicy {
    public static func canCommit(expectedVersion: String?, currentVersion: String?) -> Bool { expectedVersion == currentVersion }
}
public enum OrganizationBatchRunner {
    public static func run<T: Sendable>(_ batches: [T], allowed: @Sendable () async -> Bool, evaluate: @Sendable (T) async throws -> Void) async throws {
        for batch in batches {
            try Task.checkCancellation()
            guard await allowed() else { return }
            try await evaluate(batch)
        }
    }
}
