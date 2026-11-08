import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum XMLTVParser {
    public static let maximumFileSize = 256 * 1024 * 1024

    public static func parse(_ data: Data, sourceID: UUID) throws -> [GuideProgram] {
        try document(data, sourceID: sourceID).programs
    }
    public static func document(_ data: Data, sourceID: UUID) throws -> TVGuide {
        guard data.count <= 64 * 1024 * 1024 else { throw CatalogError.tooLarge }
        return try parse(XMLParser(data: data), sourceID: sourceID)
    }

    /// Large provider guides are read incrementally from disk instead of keeping
    /// the complete XML document in memory alongside the decoded programs.
    public static func parse(fileAt url: URL, sourceID: UUID) throws -> [GuideProgram] {
        try document(fileAt: url, sourceID: sourceID).programs
    }
    public static func document(fileAt url: URL, sourceID: UUID) throws -> TVGuide {
        guard url.isFileURL else { throw CatalogError.invalidGuide }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CatalogError.invalidGuide }
        guard (values.fileSize ?? 0) <= maximumFileSize else { throw CatalogError.tooLarge }
        guard let stream = InputStream(url: url) else { throw CatalogError.invalidGuide }
        return try parse(XMLParser(stream: stream), sourceID: sourceID)
    }

    private static func parse(_ parser: XMLParser, sourceID: UUID) throws -> TVGuide {
        try Task.checkCancellation()
        let delegate = GuideDelegate(sourceID: sourceID)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let succeeded = parser.parse()
        try Task.checkCancellation()
        if delegate.exceededLimit { throw CatalogError.tooLarge }
        guard succeeded, delegate.hasRoot else { throw CatalogError.invalidGuide }
        return TVGuide(channels: delegate.channels, programs: delegate.programs)
    }

    public static func date(_ text: String) -> Date? {
        date(text, using: dateFormatter())
    }
    fileprivate static func date(_ text: String, using formatter: DateFormatter) -> Date? {
        let pieces = text.split(whereSeparator: \.isWhitespace)
        guard let stamp = pieces.first, stamp.count == 14 else { return nil }
        return formatter.date(from: String(stamp) + " " + (pieces.count > 1 ? String(pieces[1]) : "+0000"))
    }
    fileprivate static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        formatter.isLenient = false
        return formatter
    }
}

private final class GuideDelegate: NSObject, XMLParserDelegate {
    let sourceID: UUID
    var programs: [GuideProgram] = []
    var hasRoot = false
    var current: GuideProgram?
    var channels: [GuideChannel] = []
    var channel: GuideChannel?
    var buffer = ""
    var seen = Set<String>()
    var exceededLimit = false
    private let dateFormatter = XMLTVParser.dateFormatter()
    init(sourceID: UUID) { self.sourceID = sourceID }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if Task.isCancelled { parser.abortParsing(); return }
        buffer = ""
        if elementName == "tv" { hasRoot = true }
        if elementName == "channel", let id = attributeDict["id"], !id.isEmpty {
            channel = GuideChannel(sourceID: sourceID, guideID: id, names: [])
        }
        if elementName == "programme" {
            current = nil
            guard let guideID = attributeDict["channel"], let startText = attributeDict["start"], let endText = attributeDict["stop"],
                  let start = XMLTVParser.date(startText, using: dateFormatter), let end = XMLTVParser.date(endText, using: dateFormatter), end > start else { return }
            current = GuideProgram(id: StableID.channel(source: sourceID, provider: guideID + "|" + String(start.timeIntervalSince1970)), sourceID: sourceID, guideID: guideID, title: "", start: start, end: end)
        }
        if elementName == "title", current?.language.isEmpty == true { current?.language = attributeDict["lang"] ?? "" }
        if elementName == "icon", let src = attributeDict["src"] { current?.image = URL(string: src) }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if Task.isCancelled { parser.abortParsing(); return }
        guard current != nil || channel != nil else { return }
        guard buffer.utf8.count + string.utf8.count <= 1024 * 1024 else { exceededLimit = true; parser.abortParsing(); return }
        buffer += string
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "display-name": if !value.isEmpty, (channel?.names.count ?? 0) < 32 { channel?.names.append(value) }
        case "channel":
            if let channel {
                guard channels.count < 100_000 else { exceededLimit = true; parser.abortParsing(); return }
                channels.append(channel)
            }
            channel = nil
        case "title": if current?.title.isEmpty == true { current?.title = value }
        case "desc": if current?.summary.isEmpty == true { current?.summary = value }
        case "category": if !value.isEmpty { current?.categories.append(value) }
        case "programme":
            if let current, !current.title.isEmpty, seen.insert(current.id).inserted {
                guard programs.count < 500_000 else { exceededLimit = true; parser.abortParsing(); return }
                programs.append(current)
            }
            current = nil
        default: break
        }
        buffer = ""
    }
}
