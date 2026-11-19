import Foundation
import Synchronization

struct ProviderImport: Sendable {
    var channels: [Channel]
    var programs: [GuideProgram]?
    var connectionLimit: Int?
    var guideWarning: String?
    var guideChannels: [GuideChannel] = []
    var guideURL: URL?
}

struct HTTPClient: Sendable {
    static func url(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw CatalogError.invalidURL }
        return url
    }
    func data(_ url: URL, limit: Int = 64 * 1024 * 1024, progress: (@Sendable (TransferProgress) -> Void)? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue("mySportly/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw CatalogError.rejected }
        if response.expectedContentLength > Int64(limit) { throw CatalogError.tooLarge }
        let reporter = TransferReporter(progress)
        reporter.send(received: 0, expected: response.expectedContentLength, force: true)
        var data = Data(); data.reserveCapacity(min(max(Int(response.expectedContentLength), 0), limit))
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw CatalogError.tooLarge }
            if data.count.isMultiple(of: 65536) {
                try Task.checkCancellation()
                reporter.send(received: Int64(data.count), expected: response.expectedContentLength)
            }
        }
        reporter.send(received: Int64(data.count), expected: response.expectedContentLength, force: true)
        return data
    }

    /// The caller owns the downloaded file and must remove it after parsing.
    func download(_ url: URL, limit: Int, progress: (@Sendable (TransferProgress) -> Void)? = nil) async throws -> URL {
        let download = FileDownload(limit: limit, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("mySportly/1.0", forHTTPHeaderField: "User-Agent")
        let (file, response) = try await download.start(session: session, request: request)
        do {
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw CatalogError.rejected }
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= limit else { throw CatalogError.tooLarge }
            download.reporter.send(received: Int64(size), expected: response.expectedContentLength, force: true)
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}

/// At most five updates per second, plus the initial/final byte counts.
private final class TransferReporter: Sendable {
    private let callback: (@Sendable (TransferProgress) -> Void)?
    private let lastReport = Mutex<ContinuousClock.Instant?>(nil)
    init(_ callback: (@Sendable (TransferProgress) -> Void)?) { self.callback = callback }
    func send(received: Int64, expected: Int64, force: Bool = false) {
        guard let callback else { return }
        let shouldSend = lastReport.withLock { previous in
            let now = ContinuousClock().now
            if !force, let previous, previous.duration(to: now) < .milliseconds(200) { return false }
            previous = now
            return true
        }
        if shouldSend { callback(TransferProgress(received: received, expected: expected)) }
    }
}

/// A delegate-backed task provides progress while the file is downloading.
/// The async convenience download API did not deliver these callbacks on-device.
private final class FileDownload: NSObject, URLSessionDownloadDelegate {
    private struct State {
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        var task: URLSessionDownloadTask?
        var completed = false
    }
    private let limit: Int64
    private let state = Mutex(State())
    let reporter: TransferReporter
    init(limit: Int, progress: (@Sendable (TransferProgress) -> Void)?) {
        self.limit = Int64(limit)
        reporter = TransferReporter(progress)
    }

    func start(session: URLSession, request: URLRequest) async throws -> (URL, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request)
                let shouldStart = state.withLock { state in
                    guard !state.completed else { return false }
                    state.continuation = continuation; state.task = task
                    return true
                }
                if shouldStart { task.resume() }
                else { task.cancel(); continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: { self.cancel() }
    }

    private func cancel() {
        let pending = state.withLock { state -> (URLSessionDownloadTask?, CheckedContinuation<(URL, URLResponse), Error>?) in
            guard !state.completed else { return (nil, nil) }
            state.completed = true
            let pending = (state.task, state.continuation)
            state.task = nil; state.continuation = nil
            return pending
        }
        pending.0?.cancel()
        pending.1?.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<(URL, URLResponse), Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<(URL, URLResponse), Error>? in
            guard !state.completed else { return nil }
            state.completed = true
            let continuation = state.continuation
            state.continuation = nil; state.task = nil
            return continuation
        }
        if let continuation { continuation.resume(with: result) }
        else if case .success(let (file, _)) = result { try? FileManager.default.removeItem(at: file) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit {
            finish(.failure(CatalogError.tooLarge))
            downloadTask.cancel()
            return
        }
        reporter.send(received: totalBytesWritten, expected: totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !state.withLock({ $0.completed }) else { return }
        guard let response = downloadTask.response else { finish(.failure(CatalogError.rejected)); return }
        let file = FileManager.default.temporaryDirectory.appending(path: "mySportly-guide-\(UUID().uuidString).xml")
        do {
            // URLSession removes its temporary file when this callback returns.
            try FileManager.default.moveItem(at: location, to: file)
            finish(.success((file, response)))
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}

actor ProviderClient {
    private let http = HTTPClient()
    func importSource(_ source: TVSource, secrets: SourceSecrets, playlist: String? = nil, progress: @escaping @Sendable (ImportUpdate) -> Void = { _ in }) async throws -> ProviderImport {
        progress(ImportUpdate(step: .connection, activity: "Checking your connection…"))
        if source.kind == .xtream { return try await xtream(source, secrets: secrets, progress: progress) }
        let text: String
        if let playlist { text = playlist } else {
            progress(ImportUpdate(step: .channels, activity: "Downloading your playlist…"))
            text = String(decoding: try await http.data(HTTPClient.url(secrets.address)) {
                progress(ImportUpdate(step: .channels, activity: "Downloading your playlist…", transfer: $0))
            }, as: UTF8.self)
        }
        progress(ImportUpdate(step: .channels, activity: "Reading your channels…"))
        let channels = try M3UParser.parse(text, sourceID: source.id)
        let guideURL = secrets.guideAddress.isEmpty ? M3UParser.guideURL(text) : try HTTPClient.url(secrets.guideAddress)
        var result = ProviderImport(channels: channels)
        if let guideURL {
            result.guideURL = guideURL
            do {
                let guide = try await guide(guideURL, sourceID: source.id, channelCount: channels.count, progress: progress)
                result.programs = guide.programs; result.guideChannels = guide.channels
            }
            catch is CancellationError { throw CancellationError() }
            catch { result.guideWarning = "Channels imported. The guide could not be refreshed; any saved guide remains available." }
        }
        return result
    }

    private func xtream(_ source: TVSource, secrets: SourceSecrets, progress: @escaping @Sendable (ImportUpdate) -> Void) async throws -> ProviderImport {
        let authURL = try endpoint(secrets, file: "player_api.php")
        let auth = try JSONDecoder().decode(XtreamAccount.self, from: await http.data(authURL, limit: 1024 * 1024))
        guard auth.user_info?.auth?.int == 1, auth.user_info?.status?.lowercased() == "active" else { throw CatalogError.rejected }
        progress(ImportUpdate(step: .channels, activity: "Downloading channels and categories…"))
        async let categoriesData = http.data(endpoint(secrets, file: "player_api.php", action: "get_live_categories"))
        async let streamsData = http.data(endpoint(secrets, file: "player_api.php", action: "get_live_streams")) {
            progress(ImportUpdate(step: .channels, activity: "Downloading channels…", transfer: $0))
        }
        let categories = (try? JSONDecoder().decode([XtreamCategory].self, from: await categoriesData)) ?? []
        let groups = Dictionary(categories.map { ($0.category_id.string, $0.category_name) }, uniquingKeysWith: { a, _ in a })
        let streamData = try await streamsData
        progress(ImportUpdate(step: .channels, activity: "Reading your channels…"))
        let streams = try JSONDecoder().decode([XtreamStream].self, from: streamData)
        var seen = Set<String>()
        let channels = streams.compactMap { stream -> Channel? in
            let providerID = stream.stream_id.string
            let id = StableID.channel(source: source.id, provider: providerID)
            guard seen.insert(id).inserted else { return nil }
            return Channel(id: id, sourceID: source.id, providerID: providerID, name: stream.name, group: groups[stream.category_id?.string ?? ""] ?? "",
                           guideID: stream.epg_channel_id ?? "", logo: stream.stream_icon.flatMap(URL.init(string:)),
                           language: LocalePreferences.languageCode(stream.language?.string ?? ""), region: LocalePreferences.regionCode(stream.country?.string ?? ""),
                           archiveDays: stream.tv_archive?.int == 1 ? (stream.tv_archive_duration?.int ?? 0) : 0,
                           quality: ChannelOrganizer.quality(stream.name))
        }
        guard !channels.isEmpty else { throw CatalogError.noChannels }
        var result = ProviderImport(channels: channels, connectionLimit: auth.user_info?.max_connections?.int)
        do {
            let guideURL = secrets.guideAddress.isEmpty ? try endpoint(secrets, file: "xmltv.php") : try HTTPClient.url(secrets.guideAddress)
            result.guideURL = guideURL
            let guide = try await guide(guideURL, sourceID: source.id, channelCount: channels.count, progress: progress)
            result.programs = guide.programs; result.guideChannels = guide.channels
        } catch is CancellationError { throw CancellationError() }
        catch { result.guideWarning = "Channels imported. The provider guide is unavailable; a saved guide is retained." }
        return result
    }

    func refreshGuide(_ source: TVSource, secrets: SourceSecrets, savedURL: URL?, channelCount: Int, progress: @escaping @Sendable (ImportUpdate) -> Void) async throws -> TVGuide {
        let url: URL
        if !secrets.guideAddress.isEmpty { url = try HTTPClient.url(secrets.guideAddress) }
        else if source.kind == .xtream { url = try endpoint(secrets, file: "xmltv.php") }
        else if let savedURL { url = savedURL }
        else { throw CatalogError.invalidGuide }
        return try await guide(url, sourceID: source.id, channelCount: channelCount, progress: progress)
    }

    private func guide(_ url: URL, sourceID: UUID, channelCount: Int, progress: @escaping @Sendable (ImportUpdate) -> Void) async throws -> TVGuide {
        progress(ImportUpdate(step: .guide, activity: "Downloading your TV guide…", channelCount: channelCount))
        let file = try await http.download(url, limit: XMLTVParser.maximumFileSize) {
            progress(ImportUpdate(step: .guide, activity: "Downloading your TV guide…", transfer: $0, channelCount: channelCount))
        }
        defer { try? FileManager.default.removeItem(at: file) }
        progress(ImportUpdate(step: .guide, activity: "Reading guide listings…", channelCount: channelCount))
        return try XMLTVParser.document(fileAt: file, sourceID: sourceID)
    }

    // MARK: Movies and shows

    /// Both catalogs at once. A panel without VOD returns empty lists, not an error.
    func vodCatalog(_ source: TVSource, secrets: SourceSecrets) async throws -> VODCatalog {
        func fetch(_ action: String) async throws -> Data {
            try await http.data(endpoint(secrets, file: "player_api.php", action: action), limit: 192 * 1024 * 1024)
        }
        async let movieCategories = fetch("get_vod_categories")
        async let movies = fetch("get_vod_streams")
        async let seriesCategories = fetch("get_series_categories")
        async let series = fetch("get_series")
        var catalog = VODCatalog(sourceID: source.id, fetched: .now)
        let movieData = try await movies, seriesData = try await series
        catalog.movieCategories = XtreamVOD.categories((try? await movieCategories) ?? Data())
        catalog.seriesCategories = XtreamVOD.categories((try? await seriesCategories) ?? Data())
        catalog.movies = XtreamVOD.movies(movieData, sourceID: source.id)
        catalog.series = XtreamVOD.series(seriesData, sourceID: source.id)
        return catalog
    }
    func movieDetail(_ movie: Movie, secrets: SourceSecrets) async throws -> MovieDetail {
        var url = URLComponents(url: try endpoint(secrets, file: "player_api.php", action: "get_vod_info"), resolvingAgainstBaseURL: false)!
        url.queryItems?.append(URLQueryItem(name: "vod_id", value: movie.providerID))
        guard let url = url.url else { throw CatalogError.invalidURL }
        return XtreamVOD.movieDetail(try await http.data(url, limit: 8 * 1024 * 1024))
    }
    func seriesDetail(_ series: Series, secrets: SourceSecrets) async throws -> SeriesDetail {
        var url = URLComponents(url: try endpoint(secrets, file: "player_api.php", action: "get_series_info"), resolvingAgainstBaseURL: false)!
        url.queryItems?.append(URLQueryItem(name: "series_id", value: series.providerID))
        guard let url = url.url else { throw CatalogError.invalidURL }
        return XtreamVOD.seriesDetail(try await http.data(url, limit: 16 * 1024 * 1024), series: series)
    }
    nonisolated func vodURL(kind: VODKind, providerID: String, container: String, secrets: SourceSecrets) throws -> URL {
        XtreamVOD.playbackURL(root: try streamRoot(secrets), path: kind == .movie ? "movie" : "series", username: secrets.username,
                              password: secrets.password, providerID: providerID, container: container)
    }

    nonisolated func endpoint(_ secrets: SourceSecrets, file: String, action: String? = nil) throws -> URL {
        let base = try HTTPClient.url(secrets.address)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        let path = components.path.hasSuffix(".php") ? (components.path as NSString).deletingLastPathComponent : components.path
        components.path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "/\(file)" : "/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(file)"
        components.queryItems = [URLQueryItem(name: "username", value: secrets.username), URLQueryItem(name: "password", value: secrets.password)]
        if let action { components.queryItems?.append(URLQueryItem(name: "action", value: action)) }
        guard let url = components.url else { throw CatalogError.invalidURL }
        return url
    }

    /// The server root streams hang off, without `player_api.php` or a query.
    nonisolated func streamRoot(_ secrets: SourceSecrets) throws -> URL {
        var base = try HTTPClient.url(secrets.address)
        if base.pathExtension == "php" { base.deleteLastPathComponent() }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.query = nil; components.fragment = nil
        guard let root = components.url else { throw CatalogError.invalidURL }
        return root
    }
    nonisolated func playbackURL(_ channel: Channel, secrets: SourceSecrets) throws -> URL {
        if let direct = channel.streamURL { return direct }
        return try streamRoot(secrets).appending(path: "live").appending(component: secrets.username).appending(component: secrets.password).appending(component: "\(channel.providerID).\(secrets.output)")
    }
}

private struct FlexibleScalar: Decodable {
    let string: String
    var int: Int? { Int(string) }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { string = text }
        else if let number = try? container.decode(Int.self) { string = String(number) }
        else { string = "" }
    }
}
private struct XtreamAccount: Decodable {
    var user_info: UserInfo?
    struct UserInfo: Decodable { var auth: FlexibleScalar?; var status: String?; var max_connections: FlexibleScalar? }
}
private struct XtreamCategory: Decodable { var category_id: FlexibleScalar; var category_name: String }
private struct XtreamStream: Decodable {
    var stream_id: FlexibleScalar; var name: String; var category_id: FlexibleScalar?
    var epg_channel_id: String?; var stream_icon: String?; var tv_archive: FlexibleScalar?; var tv_archive_duration: FlexibleScalar?
    var language: FlexibleScalar?; var country: FlexibleScalar?
}
