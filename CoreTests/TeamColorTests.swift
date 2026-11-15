import Testing
@testable import SportlyCore

struct TeamColorTests {
    /// A width×height RGBA image filled column by column from `fills`
    /// (fraction of columns, RGBA).
    func image(_ fills: [(Double, [UInt8])], width: Int = 20, height: Int = 20) -> [UInt8] {
        var columns: [[UInt8]] = []
        for (fraction, color) in fills { columns += Array(repeating: color, count: Int((Double(width) * fraction).rounded())) }
        var bytes: [UInt8] = []
        for _ in 0..<height { for x in 0..<width { bytes += columns[min(x, columns.count - 1)] } }
        return bytes
    }

    @Test func solidRedIsRed() throws {
        let color = try #require(TeamColor.dominant(rgba: image([(1, [200, 20, 30, 255])]), width: 20, height: 20))
        #expect(color.red > 0.7 && color.green < 0.15 && color.blue < 0.2)
    }

    @Test func transparentPixelsAreIgnored() throws {
        let color = try #require(TeamColor.dominant(rgba: image([(0.8, [0, 200, 0, 0]), (0.2, [20, 40, 200, 255])]), width: 20, height: 20))
        #expect(color.blue > 0.7 && color.green < 0.2)
    }

    @Test func grayscaleLogoHasNoColor() {
        #expect(TeamColor.dominant(rgba: image([(0.5, [128, 128, 128, 255]), (0.25, [255, 255, 255, 255]), (0.25, [10, 10, 10, 255])]), width: 20, height: 20) == nil)
    }

    @Test func majorityHueWins() throws {
        let color = try #require(TeamColor.dominant(rgba: image([(0.7, [20, 60, 200, 255]), (0.3, [240, 120, 20, 255])]), width: 20, height: 20))
        #expect(color.blue > color.red)
    }

    @Test func tooFewColoredPixelsGiveNoColor() {
        var bytes = image([(1, [255, 255, 255, 255])])
        bytes.replaceSubrange(0..<4, with: [200, 0, 0, 255])
        #expect(TeamColor.dominant(rgba: bytes, width: 20, height: 20) == nil)
    }
}
