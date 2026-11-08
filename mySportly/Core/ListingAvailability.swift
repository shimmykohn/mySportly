import Foundation

/// Provider status labels, not a prediction about whether a stream will play.
public enum ListingAvailability {
    public static func isInactiveChannel(_ name: String) -> Bool {
        let text = words(name)
        return text.contains(" no event streaming ") || text.contains(" no event scheduled ") ||
            text.contains(" no live event ") || text == " off air "
    }
    public static func isPlaceholderProgram(_ title: String) -> Bool {
        let text = words(title)
        return isInactiveChannel(title) || [" no event ", " no events ", " off air ", " channel offline ",
            " no programming ", " no program information ", " to be announced ", " tba "].contains(text)
    }
    private static func words(_ text: String) -> String {
        " " + text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
    }
}
