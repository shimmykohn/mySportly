import Foundation

/// Browsing groups describe the sport, never a claim that numbered feeds carry
/// the same event. Provider identities and every individual stream stay intact.
public enum ChannelSport: String, CaseIterable, Codable, Sendable {
    case baseball, basketball, combat, cricket, football, golf, hockey, motorsport, rugby, soccer, tennis

    public var title: String {
        switch self {
        case .combat: "Combat Sports"
        case .football: "American Football"
        case .motorsport: "Motorsport"
        default: rawValue.capitalized
        }
    }

    public var symbol: String {
        switch self {
        case .baseball: "baseball"
        case .basketball: "basketball"
        case .combat: "figure.boxing"
        case .cricket: "figure.cricket"
        case .football: "american.football"
        case .golf: "figure.golf"
        case .hockey: "hockey.puck"
        case .motorsport: "steeringwheel"
        case .rugby: "figure.rugby"
        case .soccer: "soccerball"
        case .tennis: "figure.tennis"
        }
    }

    private static let keywords: [String: ChannelSport] = [
        "BASEBALL": .baseball, "MLB": .baseball,
        "BASKETBALL": .basketball, "NBA": .basketball, "WNBA": .basketball, "NCAAB": .basketball,
        "BOXING": .combat, "MMA": .combat, "UFC": .combat,
        "CRICKET": .cricket, "IPL": .cricket,
        "NFL": .football, "NCAAF": .football,
        "GOLF": .golf, "PGA": .golf, "LPGA": .golf,
        "HOCKEY": .hockey, "NHL": .hockey,
        "MOTORSPORT": .motorsport, "MOTORSPORTS": .motorsport, "F1": .motorsport,
        "NASCAR": .motorsport, "INDYCAR": .motorsport, "MOTOGP": .motorsport,
        "RUGBY": .rugby,
        "SOCCER": .soccer, "MLS": .soccer, "EPL": .soccer, "UEFA": .soccer,
        "TENNIS": .tennis, "ATP": .tennis, "WTA": .tennis
    ]

    static func matches(in words: Set<String>) -> Set<ChannelSport> {
        var matches = Set(words.compactMap { keywords[$0] })
        if words.contains("AMERICAN") && words.contains("FOOTBALL") { matches.insert(.football) }
        // "Football" alone is ambiguous across countries. Generic networks
        // such as ESPN stay outside a specific sport until there is evidence.
        return matches
    }
}

public struct SportChannelGroup: Identifiable, Sendable {
    public let sport: ChannelSport
    public let count: Int
    public var id: String { sport.rawValue }
}
