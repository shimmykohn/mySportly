import Foundation
import Observation
import BackgroundTasks
import UIKit

@MainActor @Observable final class OrganizationProgress {
    enum Phase { case idle, starting, running, paused }
    private(set) var run: GroupOrganizationRun?
    private(set) var phase = Phase.idle
    private(set) var backgroundActive = false
    private(set) var detail = ""
    @ObservationIgnored private let file = URL.applicationSupportDirectory.appending(path: "organization-run.json")
    @ObservationIgnored private var backgroundTask: BGContinuedProcessingTask?
    @ObservationIgnored private var requestID: String?
    @ObservationIgnored private var launchFallback: Task<Void, Never>?

    var isRunning: Bool { phase == .starting || phase == .running }
    var completed: Int { run?.completed ?? 0 }
    var total: Int { run?.total ?? 0 }
    var countLabel: String { "\(completed.formatted()) of \(total.formatted()) groups complete" }

    func restore() async {
        let file = file
        let restored = try? await catalogWork {
            // A full queue plus its completed-ID checkpoint can contain each
            // identifier twice at the supported 100,000-group ceiling.
            guard let data = try? Data(contentsOf: file), data.count <= 20_000_000,
                  let run = try? JSONDecoder().decode(GroupOrganizationRun.self, from: data),
                  run.total <= 100_000, !run.isComplete else { return Optional<GroupOrganizationRun>.none }
            return run
        }
        if let restored { run = restored; phase = .paused; detail = "Saved progress. Resume when ready." }
    }
    func prepare(_ value: GroupOrganizationRun, persist: Bool = true) throws {
        if persist { try save(value) }
        run = value; phase = .starting; detail = "Preparing Jev…"
    }
    func checkpoint(_ ids: [String], persist: Bool = true) throws {
        guard var next = run else { return }
        next.checkpoint(ids)
        if persist { try save(next) }
        run = next
        updateActivity()
    }
    private func save(_ value: GroupOrganizationRun) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var location = file; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
    }

    /// Continued processing supplies Apple's own Live Activity and permits CPU
    /// and network work after leaving the app. No custom activity or GPU needed.
    func beginBackgroundWork(start: @escaping @MainActor () -> Void, expired: @escaping @MainActor () -> Void) {
        let id = "app.iska.mysportly.organize.\(UUID().uuidString)"
        requestID = id
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self, self.requestID == id, self.isRunning, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false); return
                }
                self.launchFallback?.cancel(); self.launchFallback = nil
                self.backgroundTask = task; self.backgroundActive = true
                task.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.requestID == id else { return }
                        expired()
                    }
                }
                self.phase = .running; self.detail = "You can leave the app. Progress is saved."
                self.updateActivity(); start()
            }
        }
        let foreground = { [weak self] in
            guard let self, self.requestID == id, self.isRunning else { return }
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
            self.requestID = nil; self.backgroundActive = false
            self.phase = .running; self.detail = "Keep the app open. You can pause and resume safely."
            start()
        }
        guard registered, UIApplication.shared.applicationState == .active else { foreground(); return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Organizing your lineup", subtitle: countLabel)
        request.strategy = .fail
        launchFallback = Task {
            do {
                // iOS 27 reports asynchronous scheduling errors through this API.
                try await Task.detached { try await BGTaskScheduler.shared.submitTaskRequest(request) }.value
                guard self.requestID == id, self.backgroundTask == nil else { return }
                try await Task.sleep(for: .seconds(5))
                foreground()
            } catch is CancellationError { }
            catch { foreground() }
        }
    }
    private func updateActivity() {
        backgroundTask?.progress.totalUnitCount = Int64(max(1, total))
        backgroundTask?.progress.completedUnitCount = Int64(completed)
        backgroundTask?.updateTitle("Organizing your lineup", subtitle: countLabel)
    }
    func pause(_ message: String = "Progress saved. Resume when ready.") {
        finishBackground(success: false)
        phase = run == nil ? .idle : .paused; detail = message
    }
    func finish(persist: Bool = true) throws {
        if persist, FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        finishBackground(success: true)
        run = nil; phase = .idle; detail = ""
    }
    private func finishBackground(success: Bool) {
        launchFallback?.cancel(); launchFallback = nil
        if let task = backgroundTask { task.expirationHandler = nil; task.setTaskCompleted(success: success) }
        if let requestID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestID) }
        backgroundTask = nil; requestID = nil; backgroundActive = false
    }
}
