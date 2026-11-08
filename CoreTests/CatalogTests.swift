import Foundation
import Testing
@testable import SportlyCore

@Suite struct CatalogTests {
    let source = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test func parsesQuotedMetadataAndPreservesVariants() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="news.us" tvg-language="English" group-title="US, News",News HD
        https://example.test/live/1.m3u8?token=one
        #EXTINF:-1 tvg-id="news.us" group-title="News",News SD
        https://example.test/live/2.m3u8
        """
        let result = try M3UParser.parse(text, sourceID: source)
        #expect(result.count == 2)
        #expect(result.first?.group == "US, News")
        #expect(result.first?.guideID == "news.us")
        #expect(Set(result.map(\.id)).count == 2)
    }

    @Test func importIdentitySurvivesQueryTokenRotation() throws {
        let original = "#EXTM3U\n#EXTINF:-1 tvg-id=\"one\",News\nhttps://example.test/1?token=old"
        let first = try M3UParser.parse(original, sourceID: source)
        let second = try M3UParser.parse(original.replacingOccurrences(of: "token=old", with: "token=new"), sourceID: source)
        #expect(first.count == 1)
        #expect(first.first?.id == second.first?.id)
    }

    @Test func invalidPlaylistDoesNotWipeCatalog() throws {
        #expect(throws: CatalogError.invalidPlaylist) { try M3UParser.parse("<html>Sign in</html>", sourceID: source) }
    }

    @Test func providerRenamePreservesChannelIdentity() throws {
        let text = "#EXTM3U\n#EXTINF:-1 tvg-id=\"one\",Old Name\nhttps://example.test/1.m3u8"
        let first = try M3UParser.parse(text, sourceID: source)
        let second = try M3UParser.parse(text.replacingOccurrences(of: "Old Name", with: "New Name"), sourceID: source)
        #expect(first[0].id == second[0].id)
    }
    @Test func queryAddressedFeedsStayDistinct() throws {
        let text = "#EXTM3U\n#EXTINF:-1,One\nhttps://example.test/play?channel=1&token=a\n#EXTINF:-1,Two\nhttps://example.test/play?channel=2&token=a"
        let channels = try M3UParser.parse(text, sourceID: source)
        #expect(channels.count == 2)
        #expect(Set(channels.map(\.id)).count == 2)
    }

    @Test func refreshIsIdempotentAndSourceScoped() {
        var snapshot = CatalogSnapshot()
        let channel = Channel(id: "one", sourceID: source, name: "News")
        let other = Channel(id: "other", sourceID: UUID(), name: "Other")
        snapshot.channels = [other]
        snapshot.replace(sourceID: source, channels: [channel, channel], programs: nil)
        snapshot.replace(sourceID: source, channels: [channel], programs: nil)
        #expect(snapshot.channels.count == 2)
        #expect(snapshot.channels.contains(other))
    }
}
