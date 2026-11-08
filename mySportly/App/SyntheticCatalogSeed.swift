#if DEBUG
import Foundation

/// Debug-only `--seed-synthetic-catalog`: writes a full-sized fake catalog
/// (57,033 channels, 220,500 listings) so launch timing can be measured where
/// no provider is connected, such as the iOS Simulator. Streams use Apple's
/// public HLS sample. Runs once; later launches read the saved catalog.
enum SyntheticCatalogSeed {
    static let sourceID = UUID(uuidString: "5EED5EED-0000-4000-8000-000000000001")!
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--seed-synthetic-catalog") }

    static func snapshot(now: Date = .now) -> CatalogSnapshot {
        let stream = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")
        let regions = ["US", "UK", "CA", "ES", "FR", "DE"], groups = ["Sports", "News", "Movies", "Kids", "Entertainment"]
        var snapshot = CatalogSnapshot()
        snapshot.channels = (0..<57_033).map { index in
            Channel(id: "seed.\(index)", sourceID: sourceID, name: "\(regions[index % 6])| Channel \(index / 3) \(["HD", "FHD", "4K"][index % 3])",
                    group: "\(regions[index % 6]) | \(groups[index % 5])", guideID: "channel\(index / 3).\(regions[index % 6].lowercased())",
                    streamURL: stream, language: "en", region: regions[index % 6])
        }
        let start = Calendar.current.startOfDay(for: now)
        snapshot.programs = (0..<220_500).map { position in
            let slot = position / 3500
            return GuideProgram(id: "seed.p\(position)", sourceID: sourceID, guideID: "channel\(position % 3500).\(regions[position % 6].lowercased())",
                                title: slot.isMultiple(of: 3) ? "NBA Basketball: Knicks at Celtics" : "Evening News",
                                start: start + Double(slot) * 1800, end: start + Double(slot + 1) * 1800)
        }
        snapshot.refreshed[sourceID] = now
        snapshot.guideRefreshed[sourceID] = now
        return snapshot
    }

    static var source: TVSource { TVSource(id: sourceID, name: "Synthetic catalog", kind: .m3u, refreshedAt: .now) }
}
#endif
