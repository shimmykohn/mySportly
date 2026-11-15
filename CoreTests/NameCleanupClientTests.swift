import Foundation
import Testing
@testable import SportlyCore

struct NameCleanupClientTests {
    private func response(_ text: String, type: String = "output_text") -> Data {
        let body: [String: Any] = ["output": [
            ["type": "reasoning", "summary": []],
            ["type": "message", "content": [["type": type, type == "refusal" ? "refusal" : "text": text]]],
        ]]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    @Test func requestUsesAStrictSchemaAndTheNanoModel() throws {
        let body = try JSONSerialization.jsonObject(with: NameCleanupClient.request(["FOX SPORTS 1"])) as! [String: Any]
        #expect(body["model"] as? String == "gpt-5-nano")
        #expect(body["store"] as? Bool == false)
        let format = (body["text"] as! [String: Any])["format"] as! [String: Any]
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
    }

    @Test func keepsOnlyValidatedAnswersToAskedNames() throws {
        let text = #"{"names":[{"raw":"FOX SPORTS 1","clean":"Fox Sports 1"},{"raw":"beIN ★ Sports","clean":"beIN Sports Max"},{"raw":"Other","clean":"Other"}]}"#
        let result = try NameCleanupClient.decode(response(text), for: ["FOX SPORTS 1", "beIN ★ Sports"])
        #expect(result == ["FOX SPORTS 1": "Fox Sports 1"])
    }

    @Test func refusalChangesNothingAndGarbageIsRejected() throws {
        #expect(try NameCleanupClient.decode(response("no", type: "refusal"), for: ["A B"]).isEmpty)
        #expect(throws: DecisionsFailure.invalidResponse) { try NameCleanupClient.decode(response("not json"), for: ["A"]) }
    }
}
