import Foundation

/// Encodes saved catalog files as the 4-byte magic `SPC1` followed by JSON.
/// Data without the magic is legacy JSON from earlier builds.
///
/// Format choice (2026-11-08, `CatalogCodecTests.benchmarkFormats`, release
/// build on Mac, 57,033 channels / 220,500 listings): JSON decoded in 1.24 s
/// (75 MB), binary property list in 2.20 s (31 MB). JSON is kept; the header
/// leaves room for a different format later without guessing.
public enum CatalogCodec {
    static let magic = Data("SPC1".utf8)

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        magic + (try JSONEncoder().encode(value))
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let body = data.starts(with: magic) ? data.dropFirst(magic.count) : data[...]
        return try JSONDecoder().decode(type, from: Data(body))
    }
}
