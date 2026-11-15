import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Display-name cleanup with the Responses API and a strict JSON schema.
/// Every proposal is validated against its original by `NameCleaning`.
public struct NameCleanupClient: Sendable {
    public static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    public static let model = "gpt-5-nano"
    public static let batchSize = 100
    private let key: String
    public init(key: String) { self.key = key }

    static let instructions = """
    You tidy TV channel names from an IPTV provider for display. For each input name, return the channel's name as a viewer would say it: \
    drop provider codes, separators, symbols and quality or region tags; fix ALL CAPS to the brand's usual casing. \
    Use only words that appear in the input name; never add, translate or guess words, and keep channel numbers. \
    If a name is already clean, return it unchanged.
    """

    public static func request(_ names: [String]) throws -> Data {
        let item: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["raw", "clean"],
                                   "properties": ["raw": ["type": "string"], "clean": ["type": "string"]]]
        let schema: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["names"],
                                     "properties": ["names": ["type": "array", "items": item]]]
        let body: [String: Any] = [
            "model": model,
            "reasoning": ["effort": "low"],
            "store": false,
            "input": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": String(decoding: try JSONSerialization.data(withJSONObject: ["names": names]), as: UTF8.self)],
            ],
            "text": ["format": ["type": "json_schema", "name": "channel_names", "strict": true, "schema": schema]],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Validated names keyed by the original. Unknown or rejected entries are
    /// left out; a refusal yields nothing.
    public static func decode(_ data: Data, for names: [String]) throws -> [String: String] {
        struct Content: Decodable { let type: String; let text: String? }
        struct Item: Decodable { let type: String; let content: [Content]? }
        struct Response: Decodable { let output: [Item] }
        struct Entry: Decodable { let raw: String; let clean: String }
        struct Payload: Decodable { let names: [Entry] }
        guard data.count <= 4 * 1024 * 1024, let response = try? JSONDecoder().decode(Response.self, from: data) else { throw DecisionsFailure.invalidResponse }
        let contents = response.output.filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if contents.contains(where: { $0.type == "refusal" }) { return [:] }
        guard let text = contents.first(where: { $0.type == "output_text" })?.text,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)) else { throw DecisionsFailure.invalidResponse }
        let asked = Set(names)
        var result: [String: String] = [:]
        for entry in payload.names where asked.contains(entry.raw) {
            if let clean = NameCleaning.validate(raw: entry.raw, proposed: entry.clean) { result[entry.raw] = clean }
        }
        return result
    }

    public func clean(_ names: [String], timeout: TimeInterval = 60) async throws -> [String: String] {
        var result: [String: String] = [:]
        for start in stride(from: 0, to: names.count, by: Self.batchSize) {
            let batch = Array(names[start..<min(start + Self.batchSize, names.count)])
            let data = try await OpenAIHTTP.post(Self.endpoint, key: key, body: Self.request(batch), timeout: timeout)
            result.merge(try Self.decode(data, for: batch)) { _, new in new }
        }
        return result
    }
}
