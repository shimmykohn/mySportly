import Foundation

/// Device-local work queue. Completed decisions themselves live in the private
/// synced personal store; this queue contains only opaque group identifiers.
public struct GroupOrganizationRun: Codable, Equatable, Sendable {
    public var id: UUID
    public let groupIDs: [String]
    public private(set) var completedIDs: Set<String>
    public init(groupIDs: [String]) {
        id = UUID()
        var seen = Set<String>()
        self.groupIDs = groupIDs.filter { seen.insert($0).inserted }
        completedIDs = []
    }
    public var total: Int { groupIDs.count }
    public var completed: Int { completedIDs.count }
    public var remainingIDs: [String] { groupIDs.filter { !completedIDs.contains($0) } }
    public var isComplete: Bool { completed == total }
    public mutating func checkpoint(_ ids: [String]) {
        completedIDs.formUnion(Set(ids).intersection(groupIDs))
    }
}
