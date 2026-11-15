import AVFoundation
import CloudKit
import Synchronization
import XCTest
@testable import mySportly

/// Real services on physical hardware. Uses only Apple's public sample media and
/// an isolated temporary recording; no provider credentials or paid AI calls.
@MainActor final class DeviceIntegrationTests: XCTestCase {
    func testPermanentHTTPFailureShowsCauseWithoutRepeatedReconnects() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "missing-stream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = LocalFileServer(directory: directory)
        defer { server.stop() }
        let url = try await server.start()
        let playback = PlaybackController()
        defer { playback.stop() }
        let channel = Channel(id: "missing-stream", sourceID: UUID(), name: "Missing test stream")
        playback.play(channel, url: url, title: nil, preferredLanguage: "en")
        let item = try XCTUnwrap(playback.player.currentItem)
        try await waitUntil(timeout: 6) { playback.errorMessage != nil }
        XCTAssertTrue(playback.errorMessage?.contains("HTTP 404") == true)
        XCTAssertFalse(playback.isLoading)
        XCTAssertFalse(playback.isPlaying)
        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(playback.player.currentItem === item, "A permanent rejection must not trigger another connection.")
        playback.retry()
        XCTAssertFalse(playback.player.currentItem === item, "An explicit Try Again still makes a new attempt.")
    }

    func testGuideDownloadCanBeCancelledBeforeItStarts() async throws {
        let task = Task { try await HTTPClient().download(URL(string: "http://127.0.0.1:9/guide.xml")!, limit: 1024) }
        task.cancel()
        do {
            let file = try await task.value
            try? FileManager.default.removeItem(at: file)
            XCTFail("A cancelled download must not start or return a file.")
        } catch is CancellationError { }
        catch let error as URLError where error.code == .cancelled { }
    }

    func testPlainHTTPPlaylistCanBeFetched() async throws {
        let channel = try XCTUnwrap(SampleCatalog.snapshot().channels.first)
        var components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(channel.streamURL), resolvingAgainstBaseURL: false))
        components.scheme = "http"
        let data = try await HTTPClient().data(try XCTUnwrap(components.url), limit: 1024 * 1024)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("#EXTM3U"))
    }

    func testGuideDownloadUsesAFileAndEnforcesItsSizeLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mySportly-guide-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let xml = Data("<tv><programme channel=\"test\" start=\"20261018120000 +0000\" stop=\"20261018130000 +0000\"><title>Download check</title></programme></tv>".utf8)
        try xml.write(to: directory.appending(path: "index.m3u8"))
        let server = LocalFileServer(directory: directory)
        defer { server.stop() }
        let url = try await server.start()
        let downloadUpdates = Mutex<[TransferProgress]>([])
        let file = try await HTTPClient().download(url, limit: 1024) { update in downloadUpdates.withLock { $0.append(update) } }
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertGreaterThan(downloadUpdates.withLock { $0.count }, 1, "The delegate must report bytes during the transfer, before the final file check.")
        XCTAssertEqual(downloadUpdates.withLock { $0.last?.received }, Int64(xml.count))
        XCTAssertEqual(downloadUpdates.withLock { $0.last?.fraction }, 1)
        let dataUpdates = Mutex<[TransferProgress]>([])
        let data = try await HTTPClient().data(url, limit: 1024) { update in dataUpdates.withLock { $0.append(update) } }
        XCTAssertEqual(data, xml)
        XCTAssertEqual(dataUpdates.withLock { $0.last?.received }, Int64(xml.count))
        XCTAssertEqual(dataUpdates.withLock { $0.last?.fraction }, 1)
        let programs = try XMLTVParser.parse(fileAt: file, sourceID: UUID())
        XCTAssertEqual(programs.first?.title, "Download check")
        do {
            let oversized = try await HTTPClient().download(url, limit: 8)
            try? FileManager.default.removeItem(at: oversized)
            XCTFail("A guide download above its limit must fail.")
        } catch CatalogError.tooLarge { }
    }

    func testPublicHLSSampleActuallyPlays() async throws {
        let channel = try XCTUnwrap(SampleCatalog.snapshot().channels.first)
        let playback = PlaybackController()
        defer { playback.stop() }
        let start = ContinuousClock.now
        playback.play(channel, url: try XCTUnwrap(channel.streamURL), title: "Public HLS integration check", preferredLanguage: "en")
        XCTAssertNotNil(playback.player.currentItem, "Asset loading must begin before audio activation completes")
        try await waitUntil(timeout: 35) { playback.isPlaying && playback.player.currentTime().seconds > 1 }
        print("[PlaybackPerformance] public_sample_playing_seconds=\(start.duration(to: .now))")
        XCTAssertEqual(playback.player.currentItem?.status, .readyToPlay)
        XCTAssertGreaterThan(playback.player.currentItem?.presentationSize.width ?? 0, 0)
        XCTAssertNil(playback.errorMessage)
    }

    func testPauseDuringPreparationDoesNotAutoplayAndResumeUsesTheSameItem() async throws {
        let channel = try XCTUnwrap(SampleCatalog.snapshot().channels.first)
        let playback = PlaybackController()
        defer { playback.stop() }
        playback.play(channel, url: try XCTUnwrap(channel.streamURL), title: "Pause during preparation", preferredLanguage: "en")
        let item = try XCTUnwrap(playback.player.currentItem)
        playback.pause()
        try await waitUntil(timeout: 30) { item.status == .readyToPlay }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.player.rate, 0)
        playback.resume()
        try await waitUntil(timeout: 30) { playback.isPlaying && playback.player.currentTime().seconds > 0.5 }
        XCTAssertTrue(playback.player.currentItem === item)
        NotificationCenter.default.post(name: AVPlayerItem.playbackStalledNotification, object: item)
        try await Task.sleep(for: .seconds(3))
        XCTAssertTrue(playback.player.currentItem === item, "A transient stall must preserve the buffered item")
        playback.stop()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(playback.player.currentItem)
        XCTAssertFalse(playback.isPlaying)
    }

    func testPrivateCloudContainerCanBeReached() async throws {
        let container = CKContainer(identifier: PersonalStore.cloudIdentifier)
        let status = try await container.accountStatus()
        try XCTSkipUnless(status == .available, "The device must be signed into iCloud for this integration check.")
        _ = try await container.privateCloudDatabase.allRecordZones()
    }

    private func waitUntil(timeout: TimeInterval, condition: @MainActor () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else {
                XCTFail("The device integration did not reach the expected state within \(Int(timeout)) seconds.")
                throw IntegrationFailure.timedOut
            }
            try await Task.sleep(for: .milliseconds(200))
        }
    }
    private enum IntegrationFailure: Error { case timedOut }
}
