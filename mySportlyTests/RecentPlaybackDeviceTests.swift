import AVKit
import XCTest
@testable import mySportly

/// Opt-in diagnostics for the user's last three playback attempts. Reads the
/// existing device Keychain; the report contains no addresses or credentials.
@MainActor final class RecentPlaybackDeviceTests: XCTestCase {
    func testRecentFeedsOnDevice() async throws {
        let marker = URL.documentsDirectory.appending(path: ".recent-playback-check.enabled")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path), "Requires an explicit one-use recent playback marker")
        try FileManager.default.removeItem(at: marker)
        let reportURL = URL.documentsDirectory.appending(path: "recent-playback-report.json")
        var report: [String: Any] = ["phase": "starting"]
        func save() throws { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        try save()
        do {
            let snapshot = try await CatalogCache().load()
            let personal = try XCTUnwrap(AppStore.runningForDeviceChecks?.personal)
            let index = Dictionary(snapshot.channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let recent = personal.keys(prefix: "history.").sorted {
                personal.value($0, default: Date.distantPast) > personal.value($1, default: Date.distantPast)
            }.prefix(3).compactMap { index[String($0.dropFirst(8))] }
            XCTAssertEqual(recent.count, 3)
            let provider = ProviderClient()
            var results: [[String: Any]] = []
            report["phase"] = "testing"; report["channels"] = snapshot.channels.count; try save()
            for channel in recent {
                let secrets = try XCTUnwrap(KeychainStore.credentials(channel.sourceID))
                let authURL = try provider.endpoint(secrets, file: "player_api.php")
                var request = URLRequest(url: authURL); request.timeoutInterval = 20
                let (data, response) = try await URLSession.shared.data(for: request)
                let info = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["user_info"] as? [String: Any] ?? [:]
                func integer(_ key: String) -> Int { Int(info[key] as? String ?? "") ?? (info[key] as? NSNumber)?.intValue ?? 0 }
                let active = integer("active_cons"), maximum = max(1, integer("max_connections"))
                var result: [String: Any] = ["channel": channel.name, "channelID": channel.id,
                    "authHTTP": (response as? HTTPURLResponse)?.statusCode ?? 0,
                    "authorized": integer("auth"), "accountStatus": info["status"] as? String ?? "unknown",
                    "activeConnections": active, "maximumConnections": maximum, "format": secrets.output]
                if active >= maximum {
                    result["result"] = "connection-limit"; results.append(result); report["feeds"] = results; try save(); break
                }
                let playback = PlaybackController()
                let layer = AVPlayerLayer(player: playback.player)
                layer.frame = CGRect(x: 0, y: 100, width: 640, height: 360)
                let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
                try XCTUnwrap(window).layer.addSublayer(layer)
                let begin = ContinuousClock.now
                playback.play(channel, url: try provider.playbackURL(channel, secrets: secrets), title: nil, preferredLanguage: "en")
                let deadline = Date.now + 35
                while Date.now < deadline && playback.errorMessage == nil {
                    if layer.isReadyForDisplay && playback.isPlaying && playback.player.currentTime().seconds > 1 { break }
                    try await Task.sleep(for: .milliseconds(200))
                }
                result["seconds"] = Double(begin.duration(to: .now).components.seconds)
                result["videoReady"] = layer.isReadyForDisplay; result["playing"] = playback.isPlaying
                result["loading"] = playback.isLoading; result["playerStatus"] = playback.player.status.rawValue
                result["timeControlStatus"] = playback.player.timeControlStatus.rawValue
                result["waitReason"] = playback.player.reasonForWaitingToPlay?.rawValue ?? "none"
                result["appError"] = playback.errorMessage ?? "none"
                if let item = playback.player.currentItem {
                    result["itemStatus"] = item.status.rawValue
                    result["width"] = item.presentationSize.width; result["height"] = item.presentationSize.height
                    let time = playback.player.currentTime().seconds
                    result["mediaTime"] = time.isFinite ? time : -1
                    if let error = item.error as NSError? { result["errorDomain"] = error.domain; result["errorCode"] = error.code
                        result["errorDetails"] = Self.redacted(error.description, secrets: secrets)
                        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { result["underlyingDomain"] = underlying.domain; result["underlyingCode"] = underlying.code }
                    }
                    let log = await item.errorLog
                    result["errors"] = (log?.events ?? []).map { ["domain": $0.errorDomain, "code": $0.errorStatusCode] as [String: Any] }
                }
                playback.stop(); layer.player = nil; layer.removeFromSuperlayer()
                results.append(result); report["feeds"] = results; try save()
                try await Task.sleep(for: .seconds(3))
            }
            report["phase"] = "complete"; try save()
            let videos = results.filter { $0["videoReady"] as? Bool == true }.count
            print("RECENT_PLAYBACK_CHECK feeds=\(results.count) videos=\(videos)")
        } catch {
            let safe = error as NSError
            report["phase"] = "failed"; report["errorDomain"] = safe.domain; report["errorCode"] = safe.code; try? save()
            XCTFail("Recent playback check failed: domain=\(safe.domain) code=\(safe.code)")
        }
    }

    func testReportedFeedTransport() async throws {
        let marker = URL.documentsDirectory.appending(path: ".playback-transport-check.enabled")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path), "Requires an explicit transport-check marker")
        try FileManager.default.removeItem(at: marker)
        let reportURL = URL.documentsDirectory.appending(path: "playback-transport-report.json")
        var report: [String: Any] = ["phase": "starting"]
        func save() throws { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        try save()
        do {
            let snapshot = try await CatalogCache().load()
            let personal = try XCTUnwrap(AppStore.runningForDeviceChecks?.personal)
            let key = try XCTUnwrap(personal.keys(prefix: "history.").max {
                personal.value($0, default: Date.distantPast) < personal.value($1, default: Date.distantPast)
            })
            let channel = try XCTUnwrap(snapshot.channels.first { $0.id == String(key.dropFirst(8)) })
            let secrets = try XCTUnwrap(KeychainStore.credentials(channel.sourceID))
            let provider = ProviderClient()
            let url = try provider.playbackURL(channel, secrets: secrets)
            report["channel"] = channel.name; report["phase"] = "fetching"; try save()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var authRequest = URLRequest(url: try provider.endpoint(secrets, file: "player_api.php"))
            authRequest.setValue("mySportly/1.0", forHTTPHeaderField: "User-Agent")
            let (authData, _) = try await session.data(for: authRequest)
            let info = ((try? JSONSerialization.jsonObject(with: authData)) as? [String: Any])?["user_info"] as? [String: Any] ?? [:]
            report["allowedFormats"] = info["allowed_output_formats"] as? [String] ?? []
            let active = Int(info["active_cons"] as? String ?? "") ?? (info["active_cons"] as? NSNumber)?.intValue ?? 0
            let maximum = Int(info["max_connections"] as? String ?? "") ?? (info["max_connections"] as? NSNumber)?.intValue ?? 1
            report["activeConnections"] = active; report["maximumConnections"] = maximum
            guard active < max(1, maximum) else { report["phase"] = "connection-limit"; try save(); return }
            var request = URLRequest(url: url); request.setValue("mySportly/1.0", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count >= 65_536 { break } }
            report["http"] = (response as? HTTPURLResponse)?.statusCode ?? 0
            report["contentType"] = response.mimeType ?? "none"; report["bytes"] = data.count
            report["redirected"] = response.url != url
            report["scheme"] = response.url?.scheme ?? "none"
            let text = String(decoding: data, as: UTF8.self)
            report["isHLS"] = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
            report["tags"] = Array(Set(text.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("#EXT") }.map { String($0.prefix { $0 != ":" }) })).sorted()
            if !text.hasPrefix("#EXTM3U") { report["responsePreview"] = Self.redacted(String(text.prefix(300)), secrets: secrets) }
            report["phase"] = "player"; try save()
            session.invalidateAndCancel()
            try await Task.sleep(for: .seconds(3))
            let playback = PlaybackController()
            defer { playback.stop() }
            playback.play(channel, url: url, title: nil, preferredLanguage: "en")
            let deadline = Date.now + 20
            while Date.now < deadline && playback.player.currentItem?.status != .failed && !playback.isPlaying { try await Task.sleep(for: .milliseconds(100)) }
            if let error = playback.player.currentItem?.error as NSError? {
                report["playerError"] = Self.redacted(error.description, secrets: secrets)
            }
            report["playing"] = playback.isPlaying; report["phase"] = "complete"; try save()
        } catch {
            let safe = error as NSError
            report["phase"] = "failed"; report["errorDomain"] = safe.domain; report["errorCode"] = safe.code; try? save()
            XCTFail("Transport check failed: domain=\(safe.domain) code=\(safe.code)")
        }
    }

    private static func redacted(_ text: String, secrets: SourceSecrets) -> String {
        var value = text
        for secret in [secrets.username, secrets.password, secrets.address] where !secret.isEmpty {
            value = value.replacingOccurrences(of: secret, with: "[redacted]")
        }
        return value.replacingOccurrences(of: #"https?://[^\s<>\"]+"#, with: "[address]", options: .regularExpression)
    }
}
