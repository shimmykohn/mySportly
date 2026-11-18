import Foundation

/// Tokens an OpenAI request used, read from its `usage`, and what that cost.
public struct TokenUsage: Codable, Equatable, Sendable {
    public var input = 0
    /// Part of `input` served from the prompt cache, billed at a tenth.
    public var cached = 0
    /// Includes reasoning tokens.
    public var output = 0
    public var requests = 0
    public init(input: Int = 0, cached: Int = 0, output: Int = 0, requests: Int = 0) {
        self.input = input; self.cached = cached; self.output = output; self.requests = requests
    }

    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, cached: a.cached + b.cached, output: a.output + b.output, requests: a.requests + b.requests)
    }
    public static func += (a: inout TokenUsage, b: TokenUsage) { a = a + b }

    /// US dollars at GPT-6 Luna's Standard rates per million tokens: $0.10
    /// input, $0.01 cached input, $0.50 output. An estimate; OpenAI's bill is
    /// the record.
    public var dollars: Double {
        let fresh = max(0, input - cached)
        return (Double(fresh) * 0.10 + Double(cached) * 0.01 + Double(output) * 0.50) / 1_000_000
    }

    /// The `usage` of a Responses or Decisions API body; empty when absent.
    public static func parse(_ data: Data) -> TokenUsage {
        struct Details: Decodable { let cached_tokens: Int? }
        struct Usage: Decodable { let input_tokens: Int?; let output_tokens: Int?; let input_tokens_details: Details? }
        struct Body: Decodable { let usage: Usage? }
        guard let usage = (try? JSONDecoder().decode(Body.self, from: data))?.usage else { return TokenUsage(requests: 1) }
        return TokenUsage(input: usage.input_tokens ?? 0, cached: usage.input_tokens_details?.cached_tokens ?? 0,
                          output: usage.output_tokens ?? 0, requests: 1)
    }
}

extension Double {
    /// "$0.42", or "< $0.01" for less than a cent.
    public var dollarText: String {
        self > 0 && self < 0.01 ? "< $0.01" : formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
