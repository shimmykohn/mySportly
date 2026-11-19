import Foundation

/// A list item: one channel (or search match), or a numbered set of them
/// ("NFL 01" … "NFL 16") shown as one row that opens the set.
public enum FamilyEntry<Item: Identifiable & Sendable>: Identifiable, Sendable {
    case single(Item)
    case family(name: String, items: [Item])
    public var id: String {
        switch self {
        case .single(let item): "item-\(item.id)"
        case .family(let name, let items): "family-\(name)-\(items.first.map { "\($0.id)" } ?? "")"
        }
    }
}

public enum ChannelFamilies {
    /// Folds items of the same named set into one entry where its first item
    /// was, members in number order. A set needs at least two members here.
    public static func collapse<Item>(_ items: [Item], channel: (Item) -> Channel, family: (Channel) -> String?) -> [FamilyEntry<Item>] {
        var members: [String: [Item]] = [:], names: [String: String] = [:], keys: [String?] = []
        for item in items {
            let channel = channel(item)
            guard let name = family(channel)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { keys.append(nil); continue }
            let key = channel.sourceID.uuidString + "|" + GroupNames.normalized(name)
            members[key, default: []].append(item); names[key] = names[key] ?? name
            keys.append(key)
        }
        var result: [FamilyEntry<Item>] = [], placed = Set<String>()
        for (item, key) in zip(items, keys) {
            guard let key, let group = members[key], group.count > 1 else { result.append(.single(item)); continue }
            guard placed.insert(key).inserted else { continue }
            let sorted = group.sorted { channel($0).name.localizedStandardCompare(channel($1).name) == .orderedAscending }
            result.append(.family(name: names[key]!, items: sorted))
        }
        return result
    }
}
