import BackgroundTasks
import UIKit

@MainActor final class SourceRefreshCoordinator {
    nonisolated static let identifier = "app.iska.mysportly.source-refresh"
    private(set) var registered = false
    private var scheduling: Task<Void, Never>?
    private var requestedDate: Date?
    private var revision = 0

    func register(store: AppStore) {
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { [weak store] task in
            MainActor.assumeIsolated {
                guard let store else { task.setTaskCompleted(success: false); return }
                let work = Task { @MainActor in
                    await store.load()
                    while store.loading && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
                    let success = await store.refreshDueSources()
                    task.setTaskCompleted(success: success && !Task.isCancelled)
                }
                task.expirationHandler = { work.cancel() }
            }
        }
    }

    func schedule(at date: Date?) {
        guard registered else { return }
        requestedDate = date; revision += 1
        guard scheduling == nil else { return }
        scheduling = Task {
            defer { scheduling = nil }
            repeat {
                let current = revision, date = requestedDate
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
                if let date {
                    let request = BGProcessingTaskRequest(identifier: Self.identifier)
                    request.requiresNetworkConnectivity = true
                    request.requiresExternalPower = false
                    request.earliestBeginDate = max(date, .now.addingTimeInterval(60))
                    try? await BGTaskScheduler.shared.submitTaskRequest(request)
                }
                if current == revision { return }
            } while !Task.isCancelled
        }
    }
}
