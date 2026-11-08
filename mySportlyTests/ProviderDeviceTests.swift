import XCTest
@testable import mySportly

/// Opt-in real-provider check. Credentials are supplied through a one-use file
/// in the app's temporary directory, never source code or test arguments.
@MainActor final class ProviderDeviceTests: XCTestCase {
    func testUserProvidedSourceCanImport() async throws {
        let input = FileManager.default.temporaryDirectory.appending(path: "mySportly-provider-check.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "No one-use provider test input was supplied.")
        defer { try? FileManager.default.removeItem(at: input) }
        let secrets = try JSONDecoder().decode(SourceSecrets.self, from: Data(contentsOf: input))
        try FileManager.default.removeItem(at: input)
        let source = TVSource(name: "Provider integration check", kind: .xtream)
        do {
            let result = try await ProviderClient().importSource(source, secrets: secrets)
            XCTAssertFalse(result.channels.isEmpty, "An authenticated provider import must return channels.")
            print("[ProviderCheck] channels=\(result.channels.count) programs=\(result.programs?.count ?? 0) guideWarning=\(result.guideWarning != nil)")
        } catch {
            // Raw network errors may include credential-bearing URLs.
            let failure = error as NSError
            XCTFail("Provider import failed: \(failure.domain) code \(failure.code)")
        }
    }
}
