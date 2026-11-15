import Foundation
import CryptoKit

public enum StableID {
    public static func hash(_ text: String) -> String {
        // Lowercase hex without String(format:), which dominated catalog preparation.
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []; bytes.reserveCapacity(64)
        for byte in SHA256.hash(data: Data(text.utf8)) { bytes.append(digits[Int(byte >> 4)]); bytes.append(digits[Int(byte & 0x0f)]) }
        return String(decoding: bytes, as: UTF8.self)
    }
    public static func channel(source: UUID, provider: String) -> String { source.uuidString + ":" + hash(provider) }
}

public enum M3UParser {
    public static func attributes(_ line: String) -> [String: String] {
        let pattern = #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = line as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            for index in 2...4 where match.range(at: index).location != NSNotFound {
                result[key] = ns.substring(with: match.range(at: index))
            }
        }
        return result
    }

    public static func parse(_ text: String, sourceID: UUID) throws -> [Channel] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        guard clean.hasPrefix("#EXTM3U") else { throw CatalogError.invalidPlaylist }
        var metadata: [String: String] = [:]
        var title = ""
        var group = ""
        var channels: [Channel] = []
        var seen = Set<String>()
        for raw in clean.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                metadata = attributes(line)
                var quote: Character?
                var separator: String.Index?
                for index in line.indices {
                    let character = line[index]
                    if character == "\"" || character == "'" {
                        if quote == character { quote = nil } else if quote == nil { quote = character }
                    } else if character == "," && quote == nil { separator = index; break }
                }
                title = separator.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
                group = metadata["group-title"] ?? ""
            } else if line.hasPrefix("#EXTGRP:") {
                group = String(line.dropFirst(8))
            } else if !line.hasPrefix("#"), !line.isEmpty {
                defer { metadata = [:]; title = ""; group = "" }
                guard let url = URL(string: line), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { continue }
                let name = title.isEmpty ? (metadata["tvg-name"] ?? "Channel \(channels.count + 1)") : title
                var address = URLComponents(url: url, resolvingAgainstBaseURL: false)
                // Keep feed selectors such as ?channel= and ?id=. Only rotating credentials
                // are excluded from identity; dropping the entire query merges distinct feeds.
                let credentials: Set<String> = ["token", "access_token", "auth", "authorization", "signature", "sig", "expires", "expiry", "username", "password", "api_key", "apikey"]
                let identityQuery = address?.queryItems?.filter { !credentials.contains($0.name.lowercased()) }
                    .sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name }
                address?.queryItems = identityQuery?.isEmpty == true ? nil : identityQuery
                address?.fragment = nil; address?.user = nil; address?.password = nil
                let provider = [metadata["tvg-id"] ?? "", address?.string ?? url.path].joined(separator: "|")
                let id = StableID.channel(source: sourceID, provider: provider)
                guard seen.insert(id).inserted else { continue }
                channels.append(Channel(id: id, sourceID: sourceID, providerID: provider, name: name, group: group,
                                        guideID: metadata["tvg-id"] ?? "", logo: metadata["tvg-logo"].flatMap(URL.init(string:)),
                                        streamURL: url, language: LocalePreferences.languageCode(metadata["tvg-language"] ?? ""),
                                        region: metadata["tvg-country"] ?? "", quality: ChannelOrganizer.quality(name)))
            }
        }
        guard !channels.isEmpty else { throw CatalogError.noChannels }
        return channels
    }

    public static func guideURL(_ text: String) -> URL? {
        let header = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let attributes = attributes(header)
        return (attributes["url-tvg"] ?? attributes["x-tvg-url"]).flatMap { URL(string: $0.components(separatedBy: ",")[0]) }
    }
}

public enum LocalePreferences {
    private static let languageCodes = Set(Locale.LanguageCode.isoLanguageCodes.map(\.identifier))
    private static let regionCodes = Set(Locale.Region.isoRegions.map(\.identifier))
    private static let languageNames = ["english": "en", "eng": "en", "spanish": "es", "spa": "es", "french": "fr", "fra": "fr", "fre": "fr", "hebrew": "he", "heb": "he", "arabic": "ar", "ara": "ar", "portuguese": "pt", "por": "pt", "german": "de", "deu": "de", "ger": "de", "italian": "it", "ita": "it", "hindi": "hi", "hin": "hi", "russian": "ru", "rus": "ru", "chinese": "zh", "zho": "zh", "japanese": "ja", "jpn": "ja", "korean": "ko", "kor": "ko"]
    private static let regionAliases = ["USA": "US", "UNITED STATES": "US", "UNITED STATES OF AMERICA": "US", "UK": "GB", "UNITED KINGDOM": "GB", "CANADA": "CA", "AUSTRALIA": "AU"]
    public static func languageCode(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let code = languageNames[normalized] { return code }
        let base = normalized.replacingOccurrences(of: "_", with: "-").components(separatedBy: "-")[0]
        return languageCodes.contains(base) ? base : ""
    }
    public static func regionCode(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return regionAliases[value] ?? (regionCodes.contains(value) && value.count == 2 ? value : "")
    }
    public static var suggestedLanguages: [String] {
        var seen = Set<String>()
        let codes = Locale.preferredLanguages.map(languageCode).filter { !$0.isEmpty && seen.insert($0).inserted }
        return codes.isEmpty ? ["en"] : codes
    }
}
