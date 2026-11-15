import CryptoKit
import Foundation

/// Saved results of the two costly, deterministic catalog stages: per-channel
/// metadata from `ChannelMetadataResolver` (before personal overrides) and
/// guide matches from `GuideMappingResolver`. Each part is reused only when a
/// fingerprint of exactly the inputs it reads matches; otherwise it is
/// recomputed. Holds no stream URLs, but is stored sealed like the catalog.
public struct PreparedStages: Codable, Hashable, Sendable {
    /// Bump whenever either resolver's rules change, so saved stages recompute.
    public static let rulesVersion = "1"

    public var metadataFingerprint: String
    public var metadata: [String: ChannelMetadata]
    public var guideFingerprint: String
    public var guideMatches: [String: GuideMatch]
    public var ambiguousGuideMatches: Set<String>

    /// Covers every channel field `ChannelMetadataResolver.resolve` reads.
    static func metadataFingerprint(_ channels: [Channel]) -> String {
        var print = Fingerprint("metadata")
        for channel in channels {
            print.add(channel.id); print.add(channel.name); print.add(channel.group); print.add(channel.region); print.add(channel.language)
        }
        return print.finish()
    }

    /// Covers every input `GuideMappingResolver` reads, including the final
    /// region and language after personal overrides.
    static func guideFingerprint(channels: [Channel], metadata: [String: ChannelMetadata], guideIDs: [UUID: [String]], guideChannels: [GuideChannel]) -> String {
        var print = Fingerprint("guide")
        for channel in channels {
            print.add(channel.id); print.add(channel.sourceID.uuidString); print.add(channel.name); print.add(channel.group); print.add(channel.guideID)
            print.add(metadata[channel.id]?.region ?? "\u{0}"); print.add(metadata[channel.id]?.language ?? "\u{0}")
        }
        for source in guideIDs.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            print.add(source.uuidString)
            for id in guideIDs[source] ?? [] { print.add(id) }
        }
        for channel in guideChannels {
            print.add(channel.sourceID.uuidString); print.add(channel.guideID)
            for name in channel.names { print.add(name) }
        }
        return print.finish()
    }

    /// Raw resolver output, first occurrence of a channel ID winning as in
    /// `ChannelDirectory`.
    static func resolveMetadata(_ channels: [Channel]) throws -> [String: ChannelMetadata] {
        var resolver = ChannelMetadataResolver(), metadata: [String: ChannelMetadata] = [:]
        metadata.reserveCapacity(channels.count)
        for (position, channel) in channels.enumerated() where metadata[channel.id] == nil {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            metadata[channel.id] = resolver.resolve(channel)
        }
        return metadata
    }
}

private struct Fingerprint {
    private var hasher = SHA256()
    private static let separator: [UInt8] = [0x1F]

    init(_ stage: String) { add(stage); add(PreparedStages.rulesVersion) }

    mutating func add(_ value: String) {
        var value = value
        value.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
        Self.separator.withUnsafeBytes { hasher.update(bufferPointer: $0) }
    }

    func finish() -> String {
        hasher.finalize().map { String($0, radix: 16).leftPadded() }.joined()
    }
}

private extension String {
    func leftPadded() -> String { count == 1 ? "0" + self : self }
}
