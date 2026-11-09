import Foundation
import Observation

/// The user's OpenAI key (Keychain, this device only) and AI status. Without a
/// key every feature works with local rules.
@MainActor @Observable final class OpenAIService {
    static let account = "openai-api-key"
    private(set) var configured = false
    private(set) var lastProblem: String?
    /// Set after an authentication or quota failure; cleared by a new key or the next foreground.
    private(set) var blocked = false

    init() { refresh() }

    func refresh() { configured = key() != nil }

    func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20, key.count < 512, !key.contains(where: \.isWhitespace) else { throw KeyError.format }
        try KeychainStore.write(Data(key.utf8), account: Self.account)
        lastProblem = nil; blocked = false
        refresh()
    }

    func remove() throws {
        try KeychainStore.remove(Self.account)
        lastProblem = nil; blocked = false
        refresh()
    }

    func groupModel() -> OpenAIGroupModel? {
        guard !blocked, let key = key() else { return nil }
        return OpenAIGroupModel(key: key)
    }

    /// Interprets a search the local matcher couldn't. Nil on any failure or timeout.
    func interpret(_ query: String, teams: [String], leagues: [String], languages: [String]) async -> SearchIntent? {
        guard !blocked, let key = key() else { return nil }
        let questions = SearchFallback.questions(query: String(query.prefix(200)), teams: teams, leagues: leagues, languages: languages)
        do {
            let answers = try await DecisionsClient(key: key).answers(input: SearchFallback.input, questions: questions, timeout: 4)
            return SearchFallback.intent(from: answers)
        } catch {
            report(error)
            return nil
        }
    }

    func report(_ error: Error) {
        if error is CancellationError { return }
        lastProblem = (error as? LocalizedError)?.errorDescription ?? "OpenAI couldn’t finish. It will try again later."
        switch error {
        case GroupDecisionFailure.credentials, GroupDecisionFailure.quota, DecisionsFailure.credentials, DecisionsFailure.quota: blocked = true
        default: break
        }
    }
    func succeeded() { lastProblem = nil }
    func foregrounded() { if lastProblem != nil, configured { blocked = false } }

    private func key() -> String? {
        guard let data = try? KeychainStore.read(Self.account), let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    enum KeyError: LocalizedError {
        case format
        var errorDescription: String? { "That doesn’t look like an OpenAI API key. Keys start with “sk-”." }
    }
}
