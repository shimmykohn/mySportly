import Foundation
import Observation

/// The user's TMDB API Read Access Token (Keychain, this device only) and the
/// movie and show details it fetches. Without a token nothing is asked of
/// TMDB, and pages show the provider's own details.
@MainActor @Observable final class TMDBService {
    static let account = "tmdb-read-access-token"
    private(set) var configured = false
    private(set) var lastProblem: String?
    /// Set when TMDB refuses the token; cleared by a new one.
    @ObservationIgnored private var blocked = false
    /// Bumped when the token changes: answers to requests made with an old
    /// one aren't saved, and its refusal doesn't block the new one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let cache = TMDBCache()

    init() { refresh() }

    func refresh() { configured = token() != nil }

    func save(_ value: String) throws {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if TMDBToken.isAPIKey(token) { throw TokenError.apiKey }
        guard TMDBToken.isReadAccessToken(token) else { throw TokenError.format }
        try KeychainStore.write(Data(token.utf8), account: Self.account, thisDeviceOnly: true)
        lastProblem = nil; blocked = false; generation += 1
        refresh()
    }

    /// Also forgets everything fetched with it.
    func remove() throws {
        try KeychainStore.remove(Self.account)
        lastProblem = nil; blocked = false; generation += 1
        refresh()
        Task { await cache.removeAll() }
    }

    /// What this device saved for a library title, without asking TMDB.
    func saved(_ key: String, kind: TMDBKind) async -> TMDBTitle? {
        guard configured, let id = await cache.match(key)?.tmdbID else { return nil }
        return await cache.title(kind, id)
    }

    /// A library title's details: by the provider's TMDB id, else the match
    /// saved before (unless this lookup knows more), else (when `searching`)
    /// by IMDb id or a search by title and year. Saved copies stand in while
    /// fresh, and while TMDB can't be reached.
    func title(for lookup: TMDBLookup, searching: Bool = true) async -> TMDBTitle? {
        guard configured else { return nil }
        let client = makeClient()
        if let id = lookup.tmdbID, let title = await details(lookup.kind, id: id, client: client) {
            await remember(TMDBMatchRecord(tmdbID: id, saved: .now, evidence: lookup.evidence), for: lookup.key, client: client)
            return title
        }
        let saved = await cache.match(lookup.key)
        if let saved, saved.answers(lookup, at: .now) || !searching || client == nil {
            guard let id = saved.tmdbID else { return nil }
            return await details(lookup.kind, id: id, client: client)
        }
        guard searching, let client else { return nil }
        do {
            let id = try await match(lookup, client: client)
            await remember(TMDBMatchRecord(tmdbID: id, saved: .now, evidence: lookup.evidence), for: lookup.key, client: client)
            guard let id else { return nil }
            return await details(lookup.kind, id: id, client: client)
        } catch {
            report(error, from: client)
            guard let id = saved?.tmdbID else { return nil }
            return await details(lookup.kind, id: id, client: client)
        }
    }

    /// A movie collection, for its other parts.
    func collection(_ id: Int) async -> TMDBCollection? {
        guard configured else { return nil }
        let saved = await cache.collection(id)
        if let saved, saved.isFresh(at: .now) { return saved }
        guard let client = makeClient() else { return saved }
        do {
            guard let collection = TMDBDecode.collection(try await client.get(TMDBEndpoint.collection(id)), fetched: .now) else { return saved }
            if isCurrent(client) { await cache.save(collection) }
            return collection
        } catch {
            report(error, from: client)
            return saved
        }
    }

    /// TMDB ids matched before, by item ID: for finding TMDB's titles in the library.
    func knownMatches() async -> [String: Int] {
        configured ? await cache.knownMatches() : [:]
    }

    /// The IMDb id when the provider sent one; else a search by title, then,
    /// for titles a broad search buries, within TMDB's own year filter: still
    /// within a year for movies (the filter counts any release), any
    /// episode's year for shows.
    private func match(_ lookup: TMDBLookup, client: TMDBClient) async throws -> Int? {
        if let imdb = lookup.imdbID, let data = try? await client.get(TMDBEndpoint.find(imdbID: imdb)),
           let id = TMDBDecode.find(data, kind: lookup.kind) { return id }
        let title = lookup.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let results = TMDBDecode.search(try await client.get(TMDBEndpoint.search(lookup.kind, title: title)))
        if let best = TMDBMatch.best(results, title: title, year: lookup.year) { return best.id }
        guard let year = lookup.year else { return nil }
        let narrowed = TMDBDecode.search(try await client.get(TMDBEndpoint.search(lookup.kind, title: title, year: year)))
        return TMDBMatch.best(narrowed, title: title, year: lookup.kind == .movie ? year : nil)?.id
    }

    private func details(_ kind: TMDBKind, id: Int, client: TMDBClient?) async -> TMDBTitle? {
        let saved = await cache.title(kind, id)
        if let saved, saved.isFresh(at: .now) { return saved }
        guard let client else { return saved }
        do {
            let data = try await client.get(TMDBEndpoint.details(kind, id: id)), fetched = Date.now
            // Popular titles list hundreds of images; decode them off the main actor.
            let decoded = await Task.detached(priority: .userInitiated) { TMDBDecode.title(data, kind: kind, fetched: fetched) }.value
            guard let title = decoded else { return saved }
            if isCurrent(client) { await cache.save(title) }
            return title
        } catch {
            report(error, from: client)
            return saved
        }
    }

    private func remember(_ record: TMDBMatchRecord, for key: String, client: TMDBClient?) async {
        guard isCurrent(client) else { return }
        await cache.saveMatch(record, for: key)
    }

    private func makeClient() -> TMDBClient? {
        guard !blocked, let token = token() else { return nil }
        return TMDBClient(token: token, generation: generation)
    }

    /// Whether `client` was made with the current token.
    private func isCurrent(_ client: TMDBClient?) -> Bool { client?.generation == generation }

    /// Only a refused token is worth telling the user about; being offline isn't.
    private func report(_ error: Error, from client: TMDBClient) {
        guard isCurrent(client), let failure = error as? TMDBFailure, failure == .credentials else { return }
        blocked = true
        lastProblem = failure.errorDescription
    }

    private func token() -> String? {
        guard let data = try? KeychainStore.read(Self.account), let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    enum TokenError: LocalizedError {
        case format, apiKey
        var errorDescription: String? {
            switch self {
            case .format: "That doesn’t look like a TMDB API Read Access Token. It’s the long one that starts with “eyJ”."
            case .apiKey: "That’s the shorter API Key. Paste the API Read Access Token instead: the long one that starts with “eyJ”."
            }
        }
    }
}

/// GETs from TMDB with the token in the Authorization header, never in the
/// URL. Ephemeral: nothing authenticated is cached or stored by the system.
struct TMDBClient: Sendable {
    let token: String
    /// `TMDBService`'s token generation when this was made.
    let generation: Int
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 0...1 {
            try Task.checkCancellation()
            let (data, response) = try await Self.session.data(for: request)
            let http = response as? HTTPURLResponse
            if http?.statusCode == 200 { return data }
            // TMDB asks clients to respect a 429: wait as long as it says, briefly, once.
            if http?.statusCode == 429, attempt == 0 {
                try await Task.sleep(for: .seconds(min(5, max(1, Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1))))
                continue
            }
            throw TMDBFailure(status: http?.statusCode ?? 0)
        }
        throw TMDBFailure.busy
    }
}

/// TMDB answers on this device only: in Caches, so never backed up or
/// synced, and nothing older than `TMDBCachePolicy.retention`.
actor TMDBCache {
    private let directory = URL.cachesDirectory.appending(path: "TMDB", directoryHint: .isDirectory)
    private var matches: [String: TMDBMatchRecord]?

    func match(_ key: String) -> TMDBMatchRecord? { loadedMatches()[key] }

    func saveMatch(_ record: TMDBMatchRecord, for key: String) {
        var all = loadedMatches()
        if let current = all[key], current.tmdbID == record.tmdbID, current.evidence >= record.evidence, current.isFresh(at: record.saved) { return }
        all[key] = record
        matches = all
        write(all, to: "matches.json")
    }

    func knownMatches() -> [String: Int] { loadedMatches().compactMapValues(\.tmdbID) }

    func title(_ kind: TMDBKind, _ id: Int) -> TMDBTitle? { read(TMDBTitle.self, from: "\(kind.rawValue)-\(id).json") }
    func save(_ title: TMDBTitle) { write(title, to: "\(title.kind.rawValue)-\(title.id).json") }
    func collection(_ id: Int) -> TMDBCollection? { read(TMDBCollection.self, from: "collection-\(id).json") }
    func save(_ collection: TMDBCollection) { write(collection, to: "collection-\(collection.id).json") }

    func removeAll() {
        matches = [:]
        try? FileManager.default.removeItem(at: directory)
    }

    /// Read once per launch, when files past the retention are removed too.
    private func loadedMatches() -> [String: TMDBMatchRecord] {
        if let matches { return matches }
        let now = Date.now
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if !TMDBCachePolicy.isFresh(modified, maxAge: TMDBCachePolicy.retention, at: now) { try? FileManager.default.removeItem(at: file) }
        }
        let loaded = (read([String: TMDBMatchRecord].self, from: "matches.json") ?? [:])
            .filter { TMDBCachePolicy.isFresh($0.value.saved, maxAge: TMDBCachePolicy.retention, at: now) }
        matches = loaded
        return loaded
    }

    private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
