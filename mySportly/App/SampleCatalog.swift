import Foundation

enum SampleCatalog {
    static let sourceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let source = TVSource(id: sourceID, name: "Sample Catalog", kind: .m3u, host: "Apple HLS sample", connectionLimit: 4)
    static func snapshot() -> CatalogSnapshot {
        var result = CatalogSnapshot()
        let sampleURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8")!
        let rows = [("Sample News HD", "News", "news", "en", "US"), ("Sample News SD", "News", "news", "en", "US"), ("Sample Sports", "Sports", "sports", "en", "US"), ("Sample Movies", "Movies", "movies", "en", "US"), ("Sample Noticias", "News", "noticias", "es", "US"), ("Sample Nature", "Documentary", "nature", "en", "GB"), ("Mystery Channel", "Provider Group 7", "mystery", "", "")]
        result.channels = rows.enumerated().map { index, row in Channel(id: "sample.\(index)", sourceID: sourceID, name: row.0, group: row.1, guideID: row.2, streamURL: sampleURL, language: row.3, region: row.4, quality: ChannelOrganizer.quality(row.0)) }
        let hour = Calendar.current.dateInterval(of: .hour, for: .now)!.start
        for (index, row) in rows.enumerated() where index != 1 {
            for offset in -2..<24 {
                let title = row.2 == "sports" ? "Sample Basketball · Team A vs Team B" : "Sample \(row.1) Program \(offset + 3)"
                result.programs.append(GuideProgram(id: "sample.program.\(index).\(offset)", sourceID: sourceID, guideID: row.2, title: title, summary: "This is an illustrative guide entry for exploring mySportly. Playback opens Apple’s public test stream, not this program.", start: hour.addingTimeInterval(Double(offset * 3600)), end: hour.addingTimeInterval(Double((offset + 1) * 3600)), categories: [row.1], language: row.3))
            }
        }
        result.refreshed[sourceID] = .now
        result.guideRefreshed[sourceID] = .now
        return result
    }
}
