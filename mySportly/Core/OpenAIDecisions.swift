import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// OpenAI Decisions API (`docs/product/openai-decisions-api.md`).
public enum Decisions {
    public static let endpoint = URL(string: "https://api.openai.com/v1/decisions")!
    public static let model = "gpt-6-luna"
    public static let maxQuestions = 400
    public static let maxChoices = 255
}

public struct DecisionChoice: Encodable, Hashable, Sendable {
    public var value: String
    public var description: String?
    public init(value: String, description: String? = nil) { self.value = value; self.description = description }
}

/// Instruction parts: plain text, or JSON data that the model treats as data.
public enum DecisionPart: Encodable, Sendable {
    case text(String)
    case json(DecisionJSON)
    private enum Keys: String, CodingKey { case type, text, data }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let text): try container.encode("input_text", forKey: .type); try container.encode(text, forKey: .text)
        case .json(let data): try container.encode("input_json", forKey: .type); try container.encode(data, forKey: .data)
        }
    }
}

/// A small JSON value so request data stays typed and Sendable.
public enum DecisionJSON: Encodable, Hashable, Sendable {
    case string(String), strings([String]), object([String: DecisionJSON])
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .strings(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        }
    }
}

public struct DecisionQuestion: Encodable, Sendable {
    public var type = "choice"
    public var name: String
    public var instructions: [DecisionPart]
    public var choices: [DecisionChoice]
    public init(name: String, instructions: [DecisionPart], choices: [DecisionChoice]) {
        self.name = name; self.instructions = instructions; self.choices = choices
    }
}

public struct DecisionsRequest: Encodable, Sendable {
    public var model = Decisions.model
    public var input: String
    public var questions: [DecisionQuestion]
    public init(input: String, questions: [DecisionQuestion]) { self.input = input; self.questions = questions }
}

/// A validated choice answer. Refused questions have no answer.
public struct DecisionAnswer: Sendable, Equatable {
    public let name: String
    public let choice: String
    public let confidence: Double
    public let probability: Double
}

public enum DecisionsFailure: Error, LocalizedError, Equatable {
    case credentials, quota, unavailable, invalidResponse
    public var errorDescription: String? {
        switch self {
        case .credentials: "OpenAI didn’t accept the API key."
        case .quota: "OpenAI reached the key’s rate or credit limit."
        case .unavailable: "OpenAI is temporarily unavailable."
        case .invalidResponse: "OpenAI returned an answer the app couldn’t use."
        }
    }
}

public struct DecisionsClient: Sendable {
    private let key: String
    public init(key: String) { self.key = key }

    /// Validates every choice answer against its question. Refusals are
    /// omitted; anything malformed rejects the response.
    public static func decode(_ data: Data, for request: DecisionsRequest) throws -> [String: DecisionAnswer] {
        struct Probability: Decodable {
            let value: Flexible?; let probability: Double
        }
        struct Answer: Decodable {
            let type: String; let name: String?; let choice: Flexible?; let confidence: Double?; let probabilities: [Probability]?
        }
        struct Response: Decodable { let answers: [Answer] }
        guard data.count <= 4 * 1024 * 1024, let response = try? JSONDecoder().decode(Response.self, from: data),
              response.answers.count == request.questions.count else { throw DecisionsFailure.invalidResponse }
        var result: [String: DecisionAnswer] = [:]
        for (question, answer) in zip(request.questions, response.answers) {
            guard answer.name == nil || answer.name == question.name else { throw DecisionsFailure.invalidResponse }
            if answer.type == "refusal" { continue }
            let allowed = Set(question.choices.map(\.value))
            guard answer.type == "choice", let choice = answer.choice?.text, allowed.contains(choice),
                  let confidence = answer.confidence, confidence.isFinite, (0...1).contains(confidence),
                  let probabilities = answer.probabilities, !probabilities.isEmpty,
                  probabilities.allSatisfy({ $0.probability.isFinite && (0...1).contains($0.probability) && allowed.contains($0.value?.text ?? "") }),
                  abs(probabilities.reduce(0) { $0 + $1.probability } - 1) <= 0.020001,
                  let selected = probabilities.first(where: { $0.value?.text == choice })?.probability
            else { throw DecisionsFailure.invalidResponse }
            result[question.name] = DecisionAnswer(name: question.name, choice: choice, confidence: confidence, probability: selected)
        }
        return result
    }

    /// Sends questions in requests of at most 400, retrying rate limits briefly.
    public func answers(input: String, questions: [DecisionQuestion], timeout: TimeInterval = 60) async throws -> [String: DecisionAnswer] {
        guard !key.isEmpty else { throw DecisionsFailure.credentials }
        var combined: [String: DecisionAnswer] = [:]
        for start in stride(from: 0, to: questions.count, by: Decisions.maxQuestions) {
            let request = DecisionsRequest(input: input, questions: Array(questions[start..<min(start + Decisions.maxQuestions, questions.count)]))
            combined.merge(try await send(request, timeout: timeout)) { _, newest in newest }
        }
        return combined
    }

    func send(_ body: DecisionsRequest, timeout: TimeInterval) async throws -> [String: DecisionAnswer] {
        let data = try await OpenAIHTTP.post(Decisions.endpoint, key: key, body: JSONEncoder().encode(body), timeout: timeout)
        return try Self.decode(data, for: body)
    }
}

/// One authenticated POST with brief retries on rate limits and server errors.
/// Ephemeral sessions never persist authenticated responses.
enum OpenAIHTTP {
    static func post(_ url: URL, key: String, body: Data, timeout: TimeInterval) async throws -> Data {
        guard !key.isEmpty else { throw DecisionsFailure.credentials }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for attempt in 0...2 {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DecisionsFailure.unavailable }
            if http.statusCode == 200 { return data }
            if http.statusCode == 401 || http.statusCode == 403 { throw DecisionsFailure.credentials }
            if [429, 500, 502, 503].contains(http.statusCode), attempt < 2 {
                let delay = min(10, max(Double(1 << attempt), Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 0))
                try await Task.sleep(for: .seconds(delay)); continue
            }
            if http.statusCode == 429 || http.statusCode == 402 { throw DecisionsFailure.quota }
            throw DecisionsFailure.unavailable
        }
        throw DecisionsFailure.unavailable
    }
}

/// Choice values and probability values may be strings, booleans or integers.
private struct Flexible: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) { text = string }
        else if let bool = try? container.decode(Bool.self) { text = bool ? "true" : "false" }
        else if let number = try? container.decode(Int.self) { text = String(number) }
        else { throw DecisionsFailure.invalidResponse }
    }
}
