import Foundation
import Observation

/// A movie or episode saved on this device, with what's needed to show and
/// play it offline. Device-only: never synced, never backed up.
struct DownloadRecord: Codable, Identifiable, Hashable {
    enum State: String, Codable { case downloading, finished, failed }
    var item: WatchProgress
    var state: State
    var received: Int64 = 0
    var expected: Int64 = 0
    var problem: String?
    var added = Date.now
    var hasArtwork = false
    var id: String { item.itemID }

    var fileName: String {
        let ext = item.container.lowercased().filter { $0.isLetter || $0.isNumber }
        return StableID.hash(item.itemID) + "." + (ext.isEmpty ? "mp4" : ext)
    }
    var artworkName: String { StableID.hash(item.itemID) + ".art" }
    var fraction: Double { expected > 0 ? min(1, Double(received) / Double(expected)) : 0 }
    var artwork: URL? { hasArtwork ? Downloads.folder.appending(path: artworkName) : item.artwork }
}

/// Movie and episode files, fetched by the system in the background so they
/// keep going when the app is closed. The provider's address for a file is
/// handed to the system and never stored or logged here; one download runs
/// at a time, since providers count it as a connection.
@MainActor @Observable final class Downloads {
    static let shared = Downloads()
    nonisolated static let sessionID = "app.iska.mysportly.downloads"
    nonisolated static let folder = URL.applicationSupportDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    nonisolated private static let index = folder.appending(path: "index.json")

    private(set) var records: [String: DownloadRecord] = [:]
    /// The system's callback after it wakes the app for finished downloads.
    @ObservationIgnored private var backgroundCompletion: (() -> Void)?
    @ObservationIgnored private var eventsDelivered = false
    @ObservationIgnored private var lastProgress: [String: Date] = [:]
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionID)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration, delegate: DownloadDelegate(), delegateQueue: nil)
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = Self.folder; try? folder.setResourceValues(values)
        if let data = try? Data(contentsOf: Self.index), let saved = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        // Files left by a download cancelled just as it finished.
        let keep = Set(records.values.flatMap { [$0.fileName, $0.artworkName] } + ["index.json"])
        for name in (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: Self.folder.appending(path: name))
        }
        // Downloads the system lost while the app was away are marked failed.
        session.getAllTasks { tasks in
            let running = Set(tasks.compactMap { Downloads.parse($0.taskDescription)?.id })
            Task { @MainActor in Downloads.shared.markStopped(except: running) }
        }
    }

    // MARK: Reading

    /// The saved file, once it's complete.
    func file(for itemID: String) -> URL? {
        guard let record = records[itemID], record.state == .finished else { return nil }
        let url = Self.folder.appending(path: record.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    /// Newest first.
    func list(_ kind: VODKind) -> [DownloadRecord] {
        records.values.filter { $0.item.kind == kind }.sorted { $0.added > $1.added }
    }

    // MARK: Changing

    func start(_ item: WatchProgress, url: URL) {
        guard records[item.itemID]?.state != .downloading else { return }
        var saved = item
        saved.position = 0; saved.watched = false
        let record = DownloadRecord(item: saved, state: .downloading)
        records[item.itemID] = record
        save()
        let task = session.downloadTask(with: url)
        task.taskDescription = item.itemID + "\u{1F}" + record.fileName
        task.resume()
        fetchArtwork(record)
    }

    func cancel(_ itemID: String) {
        session.getAllTasks { tasks in
            for task in tasks where Downloads.parse(task.taskDescription)?.id == itemID { task.cancel() }
        }
        remove(itemID)
    }

    func remove(_ itemID: String) {
        guard let record = records.removeValue(forKey: itemID) else { return }
        try? FileManager.default.removeItem(at: Self.folder.appending(path: record.fileName))
        try? FileManager.default.removeItem(at: Self.folder.appending(path: record.artworkName))
        save()
    }

    // MARK: From the system

    func progress(_ itemID: String, received: Int64, expected: Int64) {
        guard var record = records[itemID], record.state == .downloading else { return }
        // A few updates a second is plenty for a progress bar.
        if let last = lastProgress[itemID], Date.now.timeIntervalSince(last) < 0.5 { return }
        lastProgress[itemID] = .now
        record.received = received; record.expected = max(expected, 0)
        records[itemID] = record
    }

    func finished(_ itemID: String, size: Int64) {
        guard var record = records[itemID] else { return }
        record.state = .finished; record.problem = nil
        record.received = size; record.expected = size
        records[itemID] = record
        lastProgress[itemID] = nil
        save()
    }

    func failed(_ itemID: String, problem: String) {
        guard var record = records[itemID], record.state != .finished else { return }
        record.state = .failed; record.problem = problem
        records[itemID] = record
        lastProgress[itemID] = nil
        save()
    }

    /// The session is made at launch, so its events can finish before the
    /// system hands over this callback; then it's called straight away.
    func handleBackgroundEvents(_ completion: @escaping () -> Void) {
        if eventsDelivered { eventsDelivered = false; completion() } else { backgroundCompletion = completion }
    }

    func finishBackgroundEvents() {
        if let completion = backgroundCompletion { backgroundCompletion = nil; completion() } else { eventsDelivered = true }
    }

    private func markStopped(except running: Set<String>) {
        for (id, record) in records where record.state == .downloading && !running.contains(id) {
            failed(id, problem: "The download stopped. Try again.")
        }
    }

    private func fetchArtwork(_ record: DownloadRecord) {
        guard let url = record.item.artwork, url.scheme?.hasPrefix("http") == true else { return }
        let destination = Self.folder.appending(path: record.artworkName), id = record.id
        Task {
            guard let loaded = try? await URLSession.shared.data(from: url),
                  (loaded.1 as? HTTPURLResponse)?.statusCode == 200, loaded.0.count < 8 * 1024 * 1024,
                  (try? loaded.0.write(to: destination)) != nil, records[id] != nil else { return }
            records[id]?.hasArtwork = true
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(records.values)) else { return }
        try? data.write(to: Self.index, options: .atomic)
    }

    /// Task descriptions hold the item ID and the file name it saves to.
    nonisolated static func parse(_ description: String?) -> (id: String, file: String)? {
        guard let parts = description?.components(separatedBy: "\u{1F}"), parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}

/// Runs on the session's own queue. The finished file has to be moved before
/// this returns; everything else is handed to the main actor.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let task = Downloads.parse(downloadTask.taskDescription) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            let problem = PlaybackFailure(httpStatus: status).message
            Task { @MainActor in Downloads.shared.failed(task.id, problem: problem) }
            return
        }
        let destination = Downloads.folder.appending(path: task.file)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            let size = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            Task { @MainActor in Downloads.shared.finished(task.id, size: size) }
        } catch {
            Task { @MainActor in Downloads.shared.failed(task.id, problem: "The download couldn’t be saved. Check the free space on this iPhone.") }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let task = Downloads.parse(downloadTask.taskDescription) else { return }
        Task { @MainActor in Downloads.shared.progress(task.id, received: totalBytesWritten, expected: totalBytesExpectedToWrite) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let parsed = Downloads.parse(task.taskDescription) else { return }
        let code = (error as NSError).code
        if code == NSURLErrorCancelled { return }
        let problem = code == NSURLErrorCannotWriteToFile || code == NSURLErrorCannotCreateFile
            ? "There isn’t enough free space on this iPhone."
            : "The download stopped. Check your connection and try again."
        Task { @MainActor in Downloads.shared.failed(parsed.id, problem: problem) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in Downloads.shared.finishBackgroundEvents() }
    }
}
