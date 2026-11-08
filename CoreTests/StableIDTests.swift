import CryptoKit
import Foundation
import Testing
@testable import SportlyCore

struct StableIDTests {
    /// IDs are persisted in iCloud and the local cache, so the encoding must
    /// stay byte-for-byte identical to the original `%02x` formatting.
    @Test func hashMatchesOriginalHexFormatting() {
        for text in ["", "a", "US| ESPN 2 FHD", "Café ⚽︎ 東京", String(repeating: "x", count: 5000)] {
            let original = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            #expect(StableID.hash(text) == original)
        }
    }

    @Test func knownValue() {
        #expect(StableID.hash("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
