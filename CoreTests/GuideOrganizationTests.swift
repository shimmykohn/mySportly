import Foundation
import Testing
@testable import SportlyCore

@Suite struct GuideOrganizationTests {
    let source = UUID()
    @Test func guideOffsetsRepresentAbsoluteTimeAcrossDST() throws {
        let early = try #require(XMLTVParser.date("20261101013000 -0400"))
        let late = try #require(XMLTVParser.date("20261101013000 -0500"))
        #expect(late.timeIntervalSince(early) == 3600)
    }
    @Test func guideParsesEntitiesAndOvernightPrograms() throws {
        let xml = """
        <tv><programme channel="sports.us" start="20261018233000 +0000" stop="20261019013000 +0000"><title lang="en">A &amp; B</title><desc>Final</desc><category>Sports</category></programme></tv>
        """
        let programs = try XMLTVParser.parse(Data(xml.utf8), sourceID: source)
        #expect(programs.count == 1)
        #expect(programs.first?.title == "A & B")
        #expect(programs.first?.isSports == true)
        #expect(programs.first?.end.timeIntervalSince(programs.first!.start) == 7200)
    }
    @Test func fileGuideImportsProgramsBeyondTheOldMemoryLimit() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "guide-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("<tv>".utf8).write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let padding = Data(("<!--" + String(repeating: " ", count: 1024 * 1024) + "-->").utf8)
        for _ in 0..<65 { try handle.write(contentsOf: padding) }
        try handle.write(contentsOf: Data("<programme channel=\"news\" start=\"20261018120000 +0000\" stop=\"20261018130000 +0000\"><title>Beyond 64 MB</title></programme></tv>".utf8))
        let programs = try XMLTVParser.parse(fileAt: file, sourceID: source)
        #expect(programs.count == 1)
        #expect(programs.first?.title == "Beyond 64 MB")
    }
    @Test func fileGuideRejectsFilesAboveTheDownloadLimit() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "guide-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(XMLTVParser.maximumFileSize + 1))
        #expect(throws: CatalogError.tooLarge) { try XMLTVParser.parse(fileAt: file, sourceID: source) }
    }
    @Test func variantGroupingKeepsRegionalAndDelayedFeedsSeparate() {
        let channels = [
            Channel(id: "hd", sourceID: source, name: "News East HD", guideID: "news", language: "en", region: "US"),
            Channel(id: "sd", sourceID: source, name: "News East SD", guideID: "news", language: "en", region: "US"),
            Channel(id: "west", sourceID: source, name: "News West HD", guideID: "news", language: "en", region: "US"),
            Channel(id: "delay", sourceID: source, name: "News East +1 HD", guideID: "news", language: "en", region: "US"),
            Channel(id: "spanish", sourceID: source, name: "News East HD", guideID: "news", language: "es", region: "US")
        ]
        let groups = ChannelOrganizer.variantGroups(channels)
        #expect(groups.count == 1)
        #expect(Set(groups.first ?? []) == ["hd", "sd"])
    }
    @Test func unknownModelIDsAndInvalidConfidenceAreRejected() {
        let channel = Channel(id: "real", sourceID: source, name: "News")
        let suggestions = [
            ChannelSuggestion(channelID: "injected", category: .sports, confidence: 1),
            ChannelSuggestion(channelID: "real", category: .news, confidence: .nan),
            ChannelSuggestion(channelID: "real", category: .news, confidence: 0.9)
        ]
        let result = ChannelOrganizer.validate(suggestions, channels: [channel])
        #expect(result.count == 1)
        #expect(result.first?.channelID == "real")
    }
    @Test func hlsRetainsSequenceAndResolvesRelativeSegments() throws {
        let text = "#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:48\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nfirst.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:3.5,\nsecond.ts\n#EXT-X-ENDLIST"
        let playlist = try HLSPlaylist.parse(text, baseURL: URL(string: "https://example.test/live/index.m3u8")!)
        #expect(playlist.segments.count == 2)
        #expect(playlist.segments.first?.sequence == 48)
        #expect(playlist.segments.first?.url.absoluteString == "https://example.test/live/first.ts")
        #expect(playlist.segments.last?.discontinuity == true)
        #expect(playlist.ended)
    }
    @Test func recordingRejectsEncryptedHLSInsteadOfSavingBrokenFiles() throws {
        #expect(throws: CatalogError.self) {
            try HLSPlaylist.parse("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"secret.key\"\n#EXTINF:4,\na.ts", baseURL: URL(string: "https://example.test/live.m3u8")!)
        }
    }
    @Test func recordingRejectsInvalidDurationsAndSeparateAudio() throws {
        let base = URL(string: "https://example.test/live.m3u8")!
        #expect(throws: CatalogError.self) { try HLSPlaylist.parse("#EXTM3U\n#EXTINF:-4,\na.ts", baseURL: base) }
        #expect(throws: CatalogError.self) { try HLSPlaylist.parse("#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",URI=\"audio.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=10000,AUDIO=\"audio\"\nvideo.m3u8", baseURL: base) }
    }
}
