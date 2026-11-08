import Foundation

public struct RGB: Codable, Hashable, Sendable {
    public var red: Double, green: Double, blue: Double
    public init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
}

/// A team's color, taken from its logo because the bundled sports reference
/// has none. Picks the most prominent saturated hue and ignores transparent,
/// gray, near-black and near-white pixels.
public enum TeamColor {
    public static func dominant(rgba: [UInt8], width: Int, height: Int) -> RGB? {
        let pixels = width * height
        guard pixels > 0, rgba.count >= pixels * 4 else { return nil }
        var weight = [Double](repeating: 0, count: 12)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 12)
        var counts = [Int](repeating: 0, count: 12)
        var qualifying = 0
        for index in 0..<pixels {
            let offset = index * 4
            guard rgba[offset + 3] >= 128 else { continue }
            let r = Double(rgba[offset]) / 255, g = Double(rgba[offset + 1]) / 255, b = Double(rgba[offset + 2]) / 255
            let maximum = max(r, g, b), minimum = min(r, g, b)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            guard saturation >= 0.2, maximum >= 0.12, maximum <= 0.95 || saturation >= 0.5 else { continue }
            let delta = maximum - minimum
            var hue: Double
            if maximum == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maximum == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
            let bin = min(11, Int(hue / 30))
            weight[bin] += saturation
            sums[bin].0 += r; sums[bin].1 += g; sums[bin].2 += b
            counts[bin] += 1
            qualifying += 1
        }
        guard Double(qualifying) >= Double(pixels) * 0.02,
              let best = weight.indices.max(by: { weight[$0] < weight[$1] }), counts[best] > 0 else { return nil }
        let count = Double(counts[best])
        return RGB(red: sums[best].0 / count, green: sums[best].1 / count, blue: sums[best].2 / count)
    }
}
