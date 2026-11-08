import Foundation
import Observation
import UIKit

struct RecordingItem: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var sourceID: UUID
    var channelName: String
    var title: String
    var startedAt = Date.now
    var duration: Double = 0
    var bytes: Int64 = 0
    var status = "Recording"
    var detail = ""
}

@MainActor @Observable final class RecordingController {
    static let directory = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    private(set) var items: [RecordingItem] = []
    private(set) var activeID: UUID?
    private(set) var sourceID: UUID?
    var errorMessage: String?
    private var task: Task<Void, Never>?
    private var stopReason: String?
    private let worker = RecordingWorker()
    var active: RecordingItem? { items.first { $0.id == activeID } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    func reload() async {
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            var directory = Self.directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
            let file = Self.directory.appending(path: "index.json")
            if FileManager.default.fileExists(atPath: file.path) { items = try JSONDecoder().decode([RecordingItem].self, from: Data(contentsOf: file)) }
            for index in items.indices where items[index].status == "Recording" && items[index].id != activeID {
                items[index].status = "Interrupted"; items[index].detail = "The app stopped while this recording was active. Saved segments are retained."
            }
            try save()
        } catch { errorMessage = "The recording library could not be read. Existing files were retained." }
    }
    func start(channel: Channel, url: URL, title: String) async {
        guard task == nil else { return }
        let item = RecordingItem(sourceID: channel.sourceID, channelName: channel.name, title: title)
        items.insert(item, at: 0); activeID = item.id; sourceID = channel.sourceID; stopReason = nil; errorMessage = nil
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task {
            defer { activeID = nil; sourceID = nil; task = nil; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                try save()
                try await worker.record(url: url, directory: Self.directory.appending(path: item.id.uuidString)) { [self] duration, bytes in
                    await updateProgress(item.id, duration: duration, bytes: bytes)
                }
                finish(item.id, status: "Saved", detail: "")
            } catch is CancellationError {
                finish(item.id, status: stopReason == nil ? "Saved" : "Interrupted", detail: stopReason ?? "")
            } catch {
                let detail = (error as? LocalizedError)?.errorDescription ?? "The stream stopped. Saved segments are retained."
                finish(item.id, status: "Partial", detail: detail); errorMessage = detail
            }
        }
    }
    func stop(reason: String? = nil) async {
        guard let task else { return }
        stopReason = reason; task.cancel(); await task.value
    }
    func delete(_ item: RecordingItem) throws {
        guard item.id != activeID else { return }
        let path = Self.directory.appending(path: item.id.uuidString)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        items.removeAll { $0.id == item.id }; try save()
    }
    private func finish(_ id: UUID, status: String, detail: String) {
        if let index = items.firstIndex(where: { $0.id == id }) { items[index].status = status; items[index].detail = detail }
        do { try save() } catch { errorMessage = "Recording files were retained, but the library could not be saved." }
    }
    private func updateProgress(_ id: UUID, duration: Double, bytes: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].duration = duration; items[index].bytes = bytes
        do { try save() } catch { errorMessage = "Recording metadata could not be saved." }
    }
    private func save() throws { try JSONEncoder().encode(items).write(to: Self.directory.appending(path: "index.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
}

actor RecordingWorker {
    private let http = HTTPClient()
    func record(url: URL, directory: URL, progress: @escaping @Sendable (Double, Int64) async -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var mediaURL = url
        var playlist = try await fetch(mediaURL)
        for _ in 0..<3 where !playlist.variants.isEmpty {
            mediaURL = playlist.variants[0]; playlist = try await fetch(mediaURL)
        }
        guard !playlist.segments.isEmpty else { throw CatalogError.unsupportedRecording("Recording currently requires an unencrypted HLS media stream. This address did not provide supported segments.") }
        var seen = Set<Int>()
        var saved: [(HLSSegment, String, String?)] = []
        var maps: [URL: String] = [:]
        var bytes: Int64 = 0
        var duration: Double = 0
        var emptyPolls = 0
        while true {
            try Task.checkCancellation()
            var added = false
            for segment in playlist.segments where !seen.contains(segment.sequence) {
                try Task.checkCancellation()
                let resources = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                guard (resources.volumeAvailableCapacityForImportantUsage ?? 0) > 100 * 1024 * 1024 else { throw CatalogError.unsupportedRecording("Recording stopped because the device has less than 100 MB of free space.") }
                if let last = saved.last?.0.sequence, segment.sequence > last + 1 {
                    throw CatalogError.unsupportedRecording("The network fell behind the live stream. A partial recording was saved.")
                }
                var mapName: String?
                if let initialization = segment.initialization {
                    if let existing = maps[initialization] { mapName = existing }
                    else {
                        let name = "init-\(maps.count).mp4"
                        let data = try await http.data(initialization, limit: 32 * 1024 * 1024)
                        try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                        bytes += Int64(data.count); maps[initialization] = name; mapName = name
                    }
                }
                let ext = segment.initialization == nil ? "ts" : "m4s"
                let name = "segment-\(saved.count).\(ext)"
                let data = try await http.data(segment.url, limit: 32 * 1024 * 1024)
                try data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                saved.append((segment, name, mapName)); seen.insert(segment.sequence)
                duration += segment.duration; bytes += Int64(data.count); added = true
                let target = Int(ceil(saved.map { $0.0.duration }.max() ?? 6))
                var manifest = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-TARGETDURATION:\(target)\n#EXT-X-MEDIA-SEQUENCE:0\n"
                var previousMap: String?
                for (segment, file, map) in saved {
                    if segment.discontinuity { manifest += "#EXT-X-DISCONTINUITY\n" }
                    if let map, map != previousMap { manifest += "#EXT-X-MAP:URI=\"\(map)\"\n"; previousMap = map }
                    manifest += "#EXTINF:\(segment.duration),\n\(file)\n"
                }
                manifest += "#EXT-X-ENDLIST\n"
                try Data(manifest.utf8).write(to: directory.appending(path: "index.m3u8"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                await progress(duration, bytes)
            }
            if playlist.ended { return }
            emptyPolls = added ? 0 : emptyPolls + 1
            guard emptyPolls < 10 else { throw CatalogError.unsupportedRecording("The provider stopped publishing new segments. Saved video is retained.") }
            try await Task.sleep(for: .seconds(max(1, min(playlist.targetDuration / 2, 8))))
            playlist = try await fetch(mediaURL)
        }
    }
    private func fetch(_ url: URL) async throws -> HLSPlaylist {
        try HLSPlaylist.parse(String(decoding: await http.data(url, limit: 2 * 1024 * 1024), as: UTF8.self), baseURL: url)
    }
}
