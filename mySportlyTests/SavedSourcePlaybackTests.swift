import AVKit
import XCTest
@testable import mySportly

/// Explicit, one-use physical-device check. Reads connection details directly
/// from this device's Keychain; never copies them into fixtures or test output.
@MainActor final class SavedSourcePlaybackTests: XCTestCase {
    func testReportedSportsFeedDiagnostics() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "mySportly-reported-playback.enabled")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path), "Requires the one-use reported-playback marker")
        try FileManager.default.removeItem(at: marker)
        do {
            let snapshot = try await CatalogCache().load()
            let candidates = snapshot.channels.filter {
                let name = $0.name.lowercased()
                return name.contains("cowboys") && name.contains("packers")
            }
            print("[ReportedPlayback] matching_feeds=\(candidates.count)")
            for candidate in candidates.prefix(12) { print("[ReportedPlayback] candidate=\(candidate.name)") }
            let channel = try XCTUnwrap(candidates.first { $0.name.lowercased().contains("4k") }, "Reported 4K game must exist in the saved catalog")
            let secrets = try XCTUnwrap(KeychainStore.credentials(channel.sourceID))
            let provider = ProviderClient()
            let authData = try await HTTPClient().data(try provider.endpoint(secrets, file: "player_api.php"), limit: 1024 * 1024)
            let auth = try XCTUnwrap((try JSONSerialization.jsonObject(with: authData) as? [String: Any])?["user_info"] as? [String: Any])
            func integer(_ key: String) -> Int { Int(auth[key] as? String ?? "") ?? (auth[key] as? NSNumber)?.intValue ?? 0 }
            let maximum = max(1, integer("max_connections")), active = integer("active_cons")
            print("[ReportedPlayback] active=\(active) maximum=\(maximum) format=\(secrets.output)")
            try XCTSkipIf(active >= maximum, "Provider is occupied; no stream opened")
            let playback = PlaybackController()
            let layer = AVPlayerLayer(player: playback.player)
            layer.frame = CGRect(x: 0, y: 120, width: 640, height: 360)
            let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            try XCTUnwrap(window).layer.addSublayer(layer)
            defer { playback.stop(); layer.player = nil; layer.removeFromSuperlayer() }
            let start = ContinuousClock.now
            let groups = PlaybackAlternatives.groups(candidates)
            let alternateIDs = groups[channel.id] ?? []
            let alternates = try candidates.filter { $0.id != channel.id && alternateIDs.contains($0.id) }.map {
                PlaybackAlternative(channel: $0, url: try provider.playbackURL($0, secrets: secrets))
            }
            XCTAssertEqual(alternates.count, 1, "Only the exact same source/event/time is eligible")
            playback.play(channel, url: try provider.playbackURL(channel, secrets: secrets), title: nil, preferredLanguage: "en", alternates: alternates)
            let deadline = Date.now + 40
            while (!layer.isReadyForDisplay || !playback.isPlaying || playback.player.currentTime().seconds < 2) && Date.now < deadline && playback.errorMessage == nil { try await Task.sleep(for: .milliseconds(200)) }
            let item = try XCTUnwrap(playback.player.currentItem)
            print("[ReportedPlayback] first_frame=\(layer.isReadyForDisplay) playing=\(playback.isPlaying) size=\(item.presentationSize) status=\(item.status.rawValue) elapsed=\(start.duration(to: .now)) external=\(playback.player.isExternalPlaybackActive)")
            XCTAssertTrue(layer.isReadyForDisplay, "The reported feed must recover actual video through the matching alternative")
            XCTAssertTrue(playback.isPlaying)
            XCTAssertGreaterThan(playback.player.currentTime().seconds, 1)
            XCTAssertFalse(playback.videoUnavailable)
            if playback.channel?.id != channel.id { XCTAssertNotNil(playback.playbackNotice) }
            for track in item.tracks {
                guard let assetTrack = track.assetTrack else { continue }
                let formats = (try? await assetTrack.load(.formatDescriptions)) ?? []
                let codes = formats.map { CMFormatDescriptionGetMediaSubType($0) }
                print("[ReportedPlayback] type=\(assetTrack.mediaType.rawValue) enabled=\(track.isEnabled) codecs=\(codes)")
            }
            let log = await item.errorLog
            for event in log?.events ?? [] { print("[ReportedPlayback] error_domain=\(event.errorDomain) code=\(event.errorStatusCode)") }
        } catch let skip as XCTSkip { throw skip }
        catch { let safe = error as NSError; XCTFail("Reported playback diagnostics failed: domain=\(safe.domain) code=\(safe.code)") }
    }

    func testSavedSourceFirstFrame() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "mySportly-playback-check.enabled")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path), "Requires the one-use playback-check marker")
        try FileManager.default.removeItem(at: marker)
        do {
            let snapshot = try await CatalogCache().load()
            let channels = snapshot.channels
            let candidates = try await catalogWork {
                channels.filter {
                    let text = ($0.name + " " + $0.group).uppercased()
                    return (text.contains("US") || $0.region == "US") && ["ABC", "CBS", "NBC", "FOX"].contains(where: text.contains)
                }
            }
            let channel = try XCTUnwrap(candidates.first, "No suitable US channel in the saved catalog")
            let secrets = try XCTUnwrap(KeychainStore.credentials(channel.sourceID), "No saved Keychain connection")
            let provider = ProviderClient()
            let authURL = try provider.endpoint(secrets, file: "player_api.php")
            let authData = try await HTTPClient().data(authURL, limit: 1024 * 1024)
            let auth = try XCTUnwrap((try JSONSerialization.jsonObject(with: authData) as? [String: Any])?["user_info"] as? [String: Any])
            func integer(_ key: String) -> Int? {
                if let value = auth[key] as? String { return Int(value) }
                return (auth[key] as? NSNumber)?.intValue
            }
            let maximum = integer("max_connections") ?? 1, active = integer("active_cons") ?? 0
            print("[SavedPlayback] active_connections=\(active) maximum=\(maximum)")
            try XCTSkipIf(maximum > 0 && active >= maximum, "Provider connections are currently occupied; no additional stream was opened")

            let playback = PlaybackController()
            let layer = AVPlayerLayer(player: playback.player)
            layer.frame = CGRect(x: 0, y: 120, width: 320, height: 180)
            let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            try XCTUnwrap(window, "A physical-device window is required").layer.addSublayer(layer)
            defer { playback.stop(); layer.player = nil; layer.removeFromSuperlayer() }
            let start = ContinuousClock.now
            playback.play(channel, url: try provider.playbackURL(channel, secrets: secrets), title: "Saved source playback check", preferredLanguage: "en")
            let deadline = Date.now + 40
            while !layer.isReadyForDisplay && Date.now < deadline && playback.errorMessage == nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            print("[SavedPlayback] first_frame=\(layer.isReadyForDisplay) elapsed=\(start.duration(to: .now))")
            XCTAssertTrue(layer.isReadyForDisplay, "The saved provider stream must render actual video")
            XCTAssertNil(playback.errorMessage)
        } catch let skip as XCTSkip { throw skip }
        catch {
            let safe = error as NSError
            XCTFail("Saved source check failed: domain=\(safe.domain) code=\(safe.code)")
        }
    }
}
