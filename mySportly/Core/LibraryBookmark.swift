import Foundation

public struct LibraryBookmark: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case channel = "Channels", category = "Categories", channelGroup = "Channel Groups", team = "Teams", league = "Leagues", collection = "Collections"
        public var symbol: String {
            switch self { case .channel: "tv"; case .category, .channelGroup, .collection: "folder"; case .team: "person.2"; case .league: "sportscourt" }
        }
    }
    public var kind: Kind
    public var reference: String
    public var name: String
    public var path: [String]
    public var id: String { kind.rawValue + "." + StableID.hash(reference) }
    public init(kind: Kind, reference: String, name: String, path: [String] = []) {
        self.kind = kind; self.reference = reference; self.name = name; self.path = path
    }
    public static func category(_ path: [String]) -> Self {
        Self(kind: .category, reference: path.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }.joined(separator: "\u{1F}"), name: path.last ?? "Category", path: path)
    }
}
