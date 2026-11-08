#if DEBUG
import Foundation
import UIKit
import BackgroundTasks

/// Opt-in physical-device acceptance using the app's one live store. A one-use
/// request is delivered outside the app bundle. Reports exclude playback URLs,
/// source credentials, API keys and viewing history. Release builds omit this.
@MainActor enum DevelopmentGroupAudit {
    private struct Request: Decodable {
        let id: String
        let action: String
        var scope: String?
        var limit: Int?
        var groupIDs: [String]?
        var allowCloud: Bool?
        var expectedVersions: [String: String]?
        var groupID: String?
        var path: [String]?
    }
    private struct Saved: Codable {
        let placement: GroupPlacement
        let version: String?
    }
    private struct Row: Encodable {
        let id: String
        let name: String
        let fingerprint: String
        let feeds: Int
        let region: String
        let language: String
        let titles: [String]
        let providerGroups: [String]
        let path: [String]
        let applied: Bool
    }
    private struct Report: Encodable {
        let id: String
        let action: String
        let phase: String
        let date: Date
        let channels: Int
        let totalGroups: Int
        let preferredGroups: Int
        let pendingAll: Int
        let pendingPreferred: Int
        let cloudConfigured: Bool
        let cloudStatus: String
        let jevConfigured: Bool
        let organizationBackgroundActive: Bool
        let organizationCompleted: Int
        let organizationTotal: Int
        let organizationPaused: Bool
        let notice: String?
        let progress: String?
        let sourceRefreshes: [String: Date]
        let guideRefreshes: [String: Date]
        let scheduledRefresh: Date?
        let guidePrograms: Int
        let matchingExpectedVersions: Int
        let expectedVersions: Int
        let saved: [String: Saved]
        let groups: [Row]
    }

    private static let requestURL = URL.documentsDirectory.appending(path: ".group-audit-request.json")
    private static let reportURL = URL.documentsDirectory.appending(path: "group-audit-report.json")
    private static let all = ChannelAudience(scope: .all, languages: [], regions: [])

    static func runIfRequested(store: AppStore) async {
        guard !store.demo, FileManager.default.fileExists(atPath: requestURL.path),
              let data = try? Data(contentsOf: requestURL), data.count < 10_000_000,
              let request = try? JSONDecoder().decode(Request.self, from: data),
              ["inspect", "organize", "prepare", "resume", "refresh", "refresh-guide", "observe", "correct"].contains(request.action)
        else { return }
        try? FileManager.default.removeItem(at: requestURL)
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdle }
        do {
            try await write(store, request: request, phase: "started", details: false)
            switch request.action {
            case "prepare":
                let groups = store.directory?.nameGroups.pending(in: store.organizationAudience) ?? []
                let ids = Array(groups.prefix(request.limit ?? 40).map(\.id))
                if !ids.isEmpty {
                    try store.organization.prepare(GroupOrganizationRun(groupIDs: ids))
                    store.organization.pause()
                }
            case "resume":
                guard request.allowCloud == true else { throw AuditFailure.cloudNotAuthorized }
                store.resumeOrganization()
                await store.waitForGroupOrganization(); await store.waitForCatalog()
            case "organize":
                guard request.allowCloud == true else { throw AuditFailure.cloudNotAuthorized }
                if !store.personal.value("preferences.cloudAI", default: false) {
                    try store.personal.set("preferences.cloudAI", true)
                }
                let monitor = Task {
                    while !Task.isCancelled {
                        try? await write(store, request: request, phase: "organizing", details: false)
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    }
                }
                store.organizeGroups(limit: request.limit ?? 40, selecting: request.groupIDs.map(Set.init))
                await store.waitForGroupOrganization()
                monitor.cancel(); await monitor.value
                await store.waitForCatalog()
            case "refresh", "refresh-guide":
                for source in store.sources {
                    store.refresh(source, kind: request.action == "refresh-guide" ? .guide : .playlist)
                    while store.importingSource != nil {
                        try await Task.sleep(for: .seconds(2))
                        try await write(store, request: request, phase: "refreshing", details: false)
                    }
                    await store.waitForCatalog()
                    if store.notice != nil { break }
                }
            case "observe":
                for _ in 0..<24 {
                    await store.personal.refreshCloudStatus()
                    let expected = request.expectedVersions ?? [:]
                    if expected.allSatisfy({ store.personal.version("taxonomy.placement.\($0.key)") == $0.value }) { break }
                    try await write(store, request: request, phase: "waiting-for-icloud", details: false)
                    try await Task.sleep(for: .seconds(5))
                }
                store.rebuild(); await store.waitForCatalog()
            case "correct":
                guard let id = request.groupID, let group = store.directory?.nameGroups.byID[id], let path = request.path,
                      !path.isEmpty, path.count <= 4, path.allSatisfy(GroupNames.validLabel) else { throw AuditFailure.invalidCorrection }
                store.setGroupPath(group, path: path)
                await store.waitForCatalog()
            default: break
            }
            store.scheduleSourceRefresh()
            try await Task.sleep(for: .seconds(2))
            try await write(store, request: request, phase: "complete", details: true)
        } catch {
            store.inform("Playlist check paused", store.safeError(error))
            try? await write(store, request: request, phase: "failed", details: true)
        }
    }

    private static func write(_ store: AppStore, request: Request, phase: String, details: Bool) async throws {
        guard let index = store.directory?.nameGroups else { return }
        let placements = CatalogGroupIndex.savedPlacements(store.personal.snapshotValues())
        let expected = request.expectedVersions ?? [:]
        let scheduled: Date? = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests.first { $0.identifier == SourceRefreshCoordinator.identifier }?.earliestBeginDate)
            }
        }
        let saved = placements.mapValues { Saved(placement: $0, version: store.personal.version("taxonomy.placement.\($0.id)")) }
        let rows = details ? index.groups.map { group in
            Row(id: group.id, name: group.name, fingerprint: group.fingerprint, feeds: group.channelIDs.count,
                region: group.region, language: group.language, titles: Array(group.titles.prefix(4)),
                providerGroups: Array(group.providerGroups.prefix(4)), path: index.paths[group.id] ?? [],
                applied: placements[group.id]?.applies(to: group) == true)
        } : []
        let report = Report(id: request.id, action: request.action, phase: phase, date: .now,
            channels: store.channels.count, totalGroups: index.groups.count,
            preferredGroups: index.groups.filter { store.organizationAudience.includes(language: $0.language, region: $0.region) }.count,
            pendingAll: index.pending(in: all).count, pendingPreferred: index.pending(in: store.organizationAudience).count,
            cloudConfigured: store.personal.cloudConfigured, cloudStatus: store.personal.cloudStatus,
            jevConfigured: store.intelligence.jevConfigured,
            organizationBackgroundActive: store.organization.backgroundActive,
            organizationCompleted: store.organization.completed, organizationTotal: store.organization.total,
            organizationPaused: store.organization.phase == .paused,
            notice: store.notice?.message, progress: store.organizerProgress,
            sourceRefreshes: Dictionary(uniqueKeysWithValues: store.catalog.refreshed.map { ($0.key.uuidString, $0.value) }),
            guideRefreshes: Dictionary(uniqueKeysWithValues: store.catalog.guideRefreshed.map { ($0.key.uuidString, $0.value) }),
            scheduledRefresh: scheduled, guidePrograms: store.catalog.programs.count,
            matchingExpectedVersions: expected.filter { store.personal.version("taxonomy.placement.\($0.key)") == $0.value }.count,
            expectedVersions: expected.count, saved: saved, groups: rows)
        let destination = reportURL
        try await catalogWork {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(report).write(to: destination, options: [.atomic, .completeFileProtection])
        }
    }
    private enum AuditFailure: Error { case cloudNotAuthorized, invalidCorrection }
}
#endif
