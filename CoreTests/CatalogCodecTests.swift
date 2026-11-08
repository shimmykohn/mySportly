import Foundation
import Testing
@testable import SportlyCore

struct CatalogCodecTests {
    let source = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func sample() -> CatalogSnapshot {
        var snapshot = CatalogSnapshot()
        snapshot.channels = (0..<3).map { Channel(id: "c\($0)", sourceID: source, name: "Channel \($0)", guideID: "g\($0)") }
        snapshot.programs = (0..<5).map { GuideProgram(id: "p\($0)", sourceID: source, guideID: "g\($0 % 3)", title: "Show \($0)", start: now + Double($0) * 1800, end: now + Double($0 + 1) * 1800) }
        snapshot.guideRefreshed = [source: now]
        return snapshot
    }

    @Test func roundTripsSnapshot() throws {
        let decoded = try CatalogCodec.decode(CatalogSnapshot.self, from: CatalogCodec.encode(sample()))
        #expect(decoded.channels.map(\.id) == ["c0", "c1", "c2"])
        #expect(decoded.programs.map(\.id) == ["p0", "p1", "p2", "p3", "p4"])
        #expect(decoded.guideRefreshed == [source: now])
    }

    @Test func decodesLegacyJSON() throws {
        let decoded = try CatalogCodec.decode(CatalogSnapshot.self, from: JSONEncoder().encode(sample()))
        #expect(decoded.channels.count == 3)
        #expect(decoded.programs.count == 5)
    }

    @Test func encodedDataHasMagic() throws {
        #expect(try CatalogCodec.encode(sample()).prefix(4) == Data("SPC1".utf8))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPORTLY_BENCHMARK"] == "1"), .timeLimit(.minutes(3))) func benchmarkFormats() throws {
        var snapshot = CatalogSnapshot()
        snapshot.channels = (0..<57_033).map { Channel(id: "\($0)", sourceID: source, providerID: "\($0)", name: "US| Channel \($0) FHD", group: "US | Sports", guideID: "guide\($0 % 3500)", logo: URL(string: "https://example.com/logo/\($0).png"), streamURL: URL(string: "https://example.com/live/user/pass/\($0).m3u8"), language: "en", region: "US") }
        snapshot.programs = (0..<220_500).map { position in
            let slot = position / 3500
            return GuideProgram(id: "p\(position)", sourceID: source, guideID: "guide\(position % 3500)", title: slot.isMultiple(of: 3) ? "Basketball Finals" : "Evening News", summary: "A description of the program that runs a sentence or so.", start: now + Double(slot) * 1800, end: now + Double(slot + 1) * 1800, categories: ["Sports"])
        }
        let json = try JSONEncoder().encode(snapshot)
        let plistEncoder = PropertyListEncoder(); plistEncoder.outputFormat = .binary
        let plist = try plistEncoder.encode(snapshot)
        let jsonStart = ContinuousClock.now
        _ = try JSONDecoder().decode(CatalogSnapshot.self, from: json)
        let jsonTime = ContinuousClock.now - jsonStart
        let plistStart = ContinuousClock.now
        _ = try PropertyListDecoder().decode(CatalogSnapshot.self, from: plist)
        let plistTime = ContinuousClock.now - plistStart
        print("[CatalogCodec] json_decode=\(jsonTime) plist_decode=\(plistTime) json_bytes=\(json.count) plist_bytes=\(plist.count)")
    }
}
