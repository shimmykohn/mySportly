import SwiftUI
import ImageIO
import CryptoKit

/// Public artwork is a disposable, bounded cache; it never enters iCloud.
actor SportsLogoCache {
    static let shared = SportsLogoCache()
    private let directory: URL
    private let session: URLSession
    private var images: [String: CGImage] = [:]
    private var inFlight: [String: Task<CGImage?, Never>] = [:]
    private var failures: [String: Date] = [:]
    private var lastTrim = Date.distantPast
    init(directory: URL = URL.cachesDirectory.appending(path: "SportsLogos", directoryHint: .isDirectory), session: URLSession = .shared) {
        self.directory = directory; self.session = session
    }
    func image(url: URL, pixels: Int) async -> CGImage? {
        guard url.scheme == "https", url.host == "media.api-sports.io" else { return nil }
        let size = min(256, max(32, pixels))
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "\(hash)-\(size)"
        if let image = images[key] { return image }
        if let task = inFlight[key] { return await task.value }
        if let failed = failures[key], Date.now.timeIntervalSince(failed) < 300 { return nil }
        let directory = directory, session = session
        let task = Task.detached(priority: .utility) { () -> CGImage? in
            let file = directory.appending(path: hash)
            let cached = try? Data(contentsOf: file)
            var data = cached
            if data == nil {
                do {
                    var request = URLRequest(url: url); request.timeoutInterval = 15
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          http.mimeType?.hasPrefix("image/") == true else { return nil }
                    var downloaded = Data()
                    for try await byte in bytes { downloaded.append(byte); if downloaded.count > 2_000_000 { return nil } }
                    data = downloaded
                } catch { return nil }
            }
            guard let data, data.count <= 2_000_000,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if cached == nil { try? data.write(to: file, options: .atomic) }
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
            return image
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { if images.count >= 200 { images.removeAll(keepingCapacity: true) }; images[key] = result }
        else { if failures.count >= 256 { failures.removeAll(keepingCapacity: true) }; failures[key] = .now }
        trimIfNeeded()
        return result
    }
    private var colors: [URL: RGB?] = [:]
    /// The logo's dominant team color, from the same cached artwork.
    func color(url: URL) async -> RGB? {
        if let known = colors[url] { return known }
        guard let image = await image(url: url, pixels: 32) else { return nil }
        let width = 32, height = 32
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        let color = drawn ? TeamColor.dominant(rgba: bytes, width: width, height: height) : nil
        if colors.count >= 400 { colors.removeAll(keepingCapacity: true) }
        colors[url] = color
        return color
    }
    private func trimIfNeeded() {
        guard Date.now.timeIntervalSince(lastTrim) > 60 else { return }; lastTrim = .now
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where total > 32_000_000 { try? FileManager.default.removeItem(at: entry.0); total -= entry.1 }
    }
}

struct SportsLogo: View {
    let url: URL?
    var size: CGFloat = 36
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?
    private var request: String { "\(url?.absoluteString ?? "")-\(Int(size * scale))" }
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: scale).resizable().scaledToFit() }
            else { Image(systemName: "sportscourt").foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size).accessibilityHidden(true)
        .task(id: request) {
            image = nil
            guard let url else { return }
            let loaded = await SportsLogoCache.shared.image(url: url, pixels: Int(size * scale))
            guard !Task.isCancelled else { return }; image = loaded
        }
    }
}
