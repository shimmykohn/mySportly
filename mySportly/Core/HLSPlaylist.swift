import Foundation

public struct HLSSegment: Sendable, Equatable {
    public var sequence: Int
    public var url: URL
    public var duration: Double
    public var initialization: URL?
    public var discontinuity: Bool
}
public struct HLSPlaylist: Sendable {
    public var segments: [HLSSegment] = []
    public var variants: [URL] = []
    public var targetDuration: Double = 6
    public var ended: Bool = false
    public static func parse(_ text: String, baseURL: URL) throws -> HLSPlaylist {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw CatalogError.invalidPlaylist }
        var playlist = HLSPlaylist()
        var sequence = 0
        var duration: Double?
        var initialization: URL?
        var discontinuity = false
        var nextVariant = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-KEY:"), M3UParser.attributes(line)["method"] != "NONE" {
                throw CatalogError.unsupportedRecording("Recording is unavailable for encrypted or protected HLS streams.")
            }
            if line.hasPrefix("#EXT-X-BYTERANGE:") || line.contains("BYTERANGE=") {
                throw CatalogError.unsupportedRecording("This stream uses byte-range segments, which this recorder does not support.")
            }
            if line.hasPrefix("#EXT-X-MEDIA:"), M3UParser.attributes(line)["type"] == "AUDIO", M3UParser.attributes(line)["uri"] != nil {
                throw CatalogError.unsupportedRecording("This HLS stream keeps audio in a separate playlist. Recording currently supports streams with combined audio and video.")
            }
            if line.hasPrefix("#EXT-X-SKIP:") { throw CatalogError.unsupportedRecording("Recording does not support delta-update HLS playlists.") }
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") { sequence = Int(line.dropFirst(22)) ?? 0 }
            else if line.hasPrefix("#EXT-X-TARGETDURATION:") { playlist.targetDuration = Double(line.dropFirst(22)) ?? 6 }
            else if line.hasPrefix("#EXT-X-STREAM-INF:") { nextVariant = true }
            else if line.hasPrefix("#EXTINF:") {
                guard let value = line.dropFirst(8).split(separator: ",").first, let length = Double(value), length.isFinite, length > 0 else { throw CatalogError.invalidPlaylist }
                duration = length
            }
            else if line.hasPrefix("#EXT-X-MAP:") {
                let attributes = M3UParser.attributes(line)
                initialization = attributes["uri"].flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            } else if line == "#EXT-X-DISCONTINUITY" { discontinuity = true }
            else if line == "#EXT-X-ENDLIST" { playlist.ended = true }
            else if !line.hasPrefix("#"), let url = URL(string: line, relativeTo: baseURL)?.absoluteURL, ["https", "http"].contains(url.scheme ?? "") {
                if nextVariant { playlist.variants.append(url); nextVariant = false }
                else if let length = duration, length.isFinite, length > 0 {
                    playlist.segments.append(HLSSegment(sequence: sequence, url: url, duration: length, initialization: initialization, discontinuity: discontinuity))
                    sequence += 1; duration = nil; discontinuity = false
                }
            }
        }
        return playlist
    }
}
