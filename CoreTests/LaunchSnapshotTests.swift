import Foundation
import Testing
@testable import SportlyCore

struct LaunchSnapshotTests {
    let source = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func prepared() throws -> PreparedCatalog {
        let channels = (0..<400).map { Channel(id: "c\(String(format: "%03d", $0))", sourceID: source, name: "Channel \(String(format: "%03d", $0))", guideID: "g\($0)", language: "en", region: "US") }
        var programs: [GuideProgram] = []
        for index in 0..<400 {
            programs.append(GuideProgram(id: "ended\(index)", sourceID: source, guideID: "g\(index)", title: "Ended", start: now - 7200, end: now - 60))
            programs.append(GuideProgram(id: "live\(index)", sourceID: source, guideID: "g\(index)", title: "Live", start: now - 600, end: now + 1200))
            programs.append(GuideProgram(id: "late\(index)", sourceID: source, guideID: "g\(index)", title: "Late", start: now + 30 * 3600, end: now + 31 * 3600))
        }
        let encoder = JSONEncoder()
        var overrides: [String: Data] = [:]
        for id in ["c390", "c391", "c392"] { overrides["channel.\(id).favorite"] = try encoder.encode(true) }
        return try PreparedCatalog(channels: channels, programs: programs, activeSources: [source], overrides: overrides)
    }

    @Test func favoritesComeFirstAndLimitHolds() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], now: now)
        #expect(snapshot.channels.count == LaunchSnapshot.channelLimit)
        #expect(snapshot.favoriteIDs == ["c390", "c391", "c392"])
        #expect(Array(snapshot.channels.prefix(3).map(\.id)) == snapshot.favoriteIDs)
        #expect(Set(snapshot.channels.map(\.id)).count == snapshot.channels.count)
    }

    @Test func recentsFollowFavorites() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: ["c350", "c390", "missing"], now: now)
        #expect(snapshot.channels[3].id == "c350")
        #expect(snapshot.lineupIDs.allSatisfy { id in snapshot.channels.contains { $0.id == id } })
    }

    @Test func guideOnlyCoversSnapshotChannelsWithinWindow() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], now: now)
        let keys = Set(snapshot.channels.map { $0.sourceID.uuidString + "|" + $0.guideID })
        #expect(Set(snapshot.guide.keys).isSubset(of: keys))
        let all = snapshot.guide.values.flatMap { $0 }
        #expect(!all.isEmpty)
        #expect(all.allSatisfy { $0.end > now && $0.start < now + LaunchSnapshot.window })
    }

    @Test func manualGuideMappingIsIncluded() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], manualGuideIDs: ["c390": "g5"], now: now)
        #expect(snapshot.guide[source.uuidString + "|g5"]?.map(\.id) == ["live5"])
    }

    @Test func activeDropsRemovedSourcesAndEndedListings() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: [], now: now)
        let removed = snapshot.active(sources: [], now: now)
        #expect(removed.channels.isEmpty && removed.lineupIDs.isEmpty && removed.favoriteIDs.isEmpty && removed.guide.isEmpty)
        let later = snapshot.active(sources: [source], now: now + 25 * 3600)
        #expect(later.channels.count == snapshot.channels.count)
        #expect(later.guide.isEmpty)
    }

    @Test func roundTripsThroughCatalogCodec() throws {
        let snapshot = LaunchSnapshot(prepared: try prepared(), recentIDs: ["c350"], now: now)
        let decoded = try CatalogCodec.decode(LaunchSnapshot.self, from: CatalogCodec.encode(snapshot))
        #expect(decoded.channels == snapshot.channels)
        #expect(decoded.guide == snapshot.guide)
        #expect(decoded.lineupIDs == snapshot.lineupIDs)
    }
}
