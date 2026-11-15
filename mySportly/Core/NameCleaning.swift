import Foundation

/// Display names only. Playback, guide matching and feed merging always use
/// the provider's raw name.
public enum NameCleaning {
    private static let prefix = try! NSRegularExpression(pattern: #"^\s*[\[(|]?\s*([A-Za-z]{2,4})\s*(?:[\])|:]|\s[-–]\s)\s*"#)
    private static let markers = try! NSRegularExpression(
        pattern: #"(?i)(?<![\p{L}\p{N}])(4K|8K|UHD|FHD|HD|SD|HEVC|H\.?265|H\.?264|\d{2,3}\s?FPS|RAW|BACKUP|VIP|MULTI\s?AUDIO|\(B\)|\[B\])(?![\p{L}\p{N}])"#)
    private static let emptyBrackets = try! NSRegularExpression(pattern: #"[\[(]\s*[\])]"#)
    private static let edges = CharacterSet(charactersIn: " |:-–—•·*_").union(.whitespacesAndNewlines)
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " &'.+!-()"))
    /// Region and language codes that providers put in front of a name.
    static let regionCodes: Set<String> = {
        var codes = Set(Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 && $0.allSatisfy(\.isLetter) })
        codes.formUnion(["UK", "USA", "EN", "LAT", "LATAM", "ARAB", "EXYU", "AFR", "ASIA", "EU", "INT", "CAR"])
        return codes
    }()

    /// Rules only. Returns the original (trimmed) name when cleaning would
    /// leave nothing.
    public static func local(_ raw: String) -> String {
        var text = raw.precomposedStringWithCompatibilityMapping
        // Repeated prefixes such as "|US| UK: …" come off one at a time.
        for _ in 0..<2 {
            guard let match = prefix.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let code = Range(match.range(at: 1), in: text), regionCodes.contains(text[code].uppercased()),
                  let whole = Range(match.range, in: text), whole.upperBound < text.endIndex else { break }
            text = String(text[whole.upperBound...])
        }
        text = replace(markers, in: text, with: " ")
        text = replace(emptyBrackets, in: text, with: " ")
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: edges)
        return cleaned.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned
    }

    /// The region or language code a provider put in front of the name, if any.
    public static func regionPrefix(_ raw: String) -> String? {
        let text = raw.precomposedStringWithCompatibilityMapping
        guard let match = prefix.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let code = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[code].uppercased()
        return regionCodes.contains(value) ? value : nil
    }

    /// Names local rules leave looking like provider codes go to the model:
    /// leftover symbols, or an all-caps name with a long word.
    public static func needsModel(_ cleaned: String) -> Bool {
        if cleaned.unicodeScalars.contains(where: { !allowed.contains($0) }) { return true }
        let words = cleaned.split(separator: " ")
        let letters = cleaned.filter(\.isLetter)
        return words.count >= 2 && letters.count >= 5 && letters == letters.uppercased() && words.contains { $0.filter(\.isLetter).count >= 5 }
    }

    /// A proposal is kept only when every word comes from the original name,
    /// it adds no digits and is not longer.
    public static func validate(raw: String, proposed: String) -> String? {
        let candidate = proposed.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: edges)
        let source = raw.precomposedStringWithCompatibilityMapping
        guard !candidate.isEmpty, candidate.count <= source.count, candidate.count <= 60 else { return nil }
        let sourceWords = words(source), sourceText = sourceWords.joined(separator: " ")
        let proposedWords = words(candidate)
        guard !proposedWords.isEmpty, proposedWords.allSatisfy({ sourceWords.contains($0) || sourceText.contains($0) }) else { return nil }
        let digits = Set(source.filter(\.isNumber))
        guard candidate.filter(\.isNumber).allSatisfy(digits.contains) else { return nil }
        return candidate
    }

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
