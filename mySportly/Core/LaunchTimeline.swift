import Foundation

public enum LaunchPhase: String, CaseIterable, Sendable {
    case processStart, storeCreated, loadStarted, snapshotLoaded, firstInteractive, catalogDecoded, catalogPrepared
}

/// Wall-clock launch milestones, measured from `processStart`. The first mark
/// of a phase wins, so later rebuilds never overwrite launch measurements.
public struct LaunchTimeline: Sendable {
    private var marks: [LaunchPhase: ContinuousClock.Instant] = [:]
    public init() {}

    /// When the kernel started this process, so launch time includes process
    /// creation, dyld and app initialization before any of our code runs.
    public static func processStartDate() -> Date? {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_un.__p_starttime
        guard started.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000)
    }

    /// The continuous-clock instant matching a past wall-clock date.
    public static func instant(for date: Date, now: ContinuousClock.Instant = .now, wallNow: Date = Date()) -> ContinuousClock.Instant {
        now - .milliseconds(Int64((wallNow.timeIntervalSince(date) * 1000).rounded()))
    }

    public mutating func mark(_ phase: LaunchPhase, at instant: ContinuousClock.Instant = .now) {
        if marks[phase] == nil { marks[phase] = instant }
    }

    public func milliseconds(to phase: LaunchPhase) -> Int? {
        guard let start = marks[.processStart], let end = marks[phase] else { return nil }
        let duration = end - start
        return Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Milliseconds from `processStart` to an arbitrary instant (diagnostics).
    public func milliseconds(at instant: ContinuousClock.Instant) -> Int {
        guard let start = marks[.processStart] else { return -1 }
        let duration = instant - start
        return Int(duration.components.seconds * 1000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    public var summary: String {
        LaunchPhase.allCases.compactMap { phase in milliseconds(to: phase).map { "\(phase.rawValue)=\($0)" } }.joined(separator: " ")
    }
}
