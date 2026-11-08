import Foundation

public enum LaunchPhase: String, CaseIterable, Sendable {
    case processStart, snapshotLoaded, firstInteractive, catalogDecoded, catalogPrepared
}

/// Wall-clock launch milestones, measured from `processStart`. The first mark
/// of a phase wins, so later rebuilds never overwrite launch measurements.
public struct LaunchTimeline: Sendable {
    private var marks: [LaunchPhase: ContinuousClock.Instant] = [:]
    public init() {}

    public mutating func mark(_ phase: LaunchPhase, at instant: ContinuousClock.Instant = .now) {
        if marks[phase] == nil { marks[phase] = instant }
    }

    public func milliseconds(to phase: LaunchPhase) -> Int? {
        guard let start = marks[.processStart], let end = marks[phase] else { return nil }
        let duration = end - start
        return Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    public var summary: String {
        LaunchPhase.allCases.compactMap { phase in milliseconds(to: phase).map { "\(phase.rawValue)=\($0)" } }.joined(separator: " ")
    }
}
