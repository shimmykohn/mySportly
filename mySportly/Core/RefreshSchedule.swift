import Foundation

public enum RefreshFrequency: String, Codable, CaseIterable, Sendable {
    case off = "Off", sixHours = "Every 6 Hours", twelveHours = "Every 12 Hours", daily = "Daily", weekly = "Weekly"
    public var interval: TimeInterval? {
        switch self { case .off: nil; case .sixHours: 21_600; case .twelveHours: 43_200; case .daily: 86_400; case .weekly: 604_800 }
    }
}

public enum SourceRefreshKind: String, Codable, Sendable { case playlist, guide }

/// Successful refresh times belong to this device's catalog. Attempt times are
/// separate, so a failed refresh never makes stale data appear up to date.
public struct RefreshSchedule: Sendable, Equatable {
    public var playlist: RefreshFrequency
    public var guide: RefreshFrequency
    public init(playlist: RefreshFrequency = .daily, guide: RefreshFrequency = .sixHours) { self.playlist = playlist; self.guide = guide }
    public func next(kind: SourceRefreshKind, success: Date?, attempt: Date?) -> Date? {
        guard let interval = (kind == .playlist ? playlist : guide).interval else { return nil }
        let due = success?.addingTimeInterval(interval) ?? .distantPast
        return max(due, attempt?.addingTimeInterval(3600) ?? .distantPast)
    }
    public func due(playlistSuccess: Date?, guideSuccess: Date?, playlistAttempt: Date?, guideAttempt: Date?, supportsGuide: Bool, at date: Date) -> SourceRefreshKind? {
        if let next = next(kind: .playlist, success: playlistSuccess, attempt: playlistAttempt), next <= date { return .playlist }
        if supportsGuide, let next = next(kind: .guide, success: guideSuccess, attempt: guideAttempt), next <= date { return .guide }
        return nil
    }
}
