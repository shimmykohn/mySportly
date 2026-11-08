import Foundation

extension AppStore {
    func bookmark(_ channel: Channel) -> LibraryBookmark { LibraryBookmark(kind: .channel, reference: channel.id, name: name(channel)) }
    func bookmark(_ sports: SportsLibraryItem) -> LibraryBookmark { LibraryBookmark(kind: sports.kind == .team ? .team : .league, reference: sports.name, name: sports.name) }
    var savedLibraryItems: [LibraryBookmark] {
        var items: [String: LibraryBookmark] = [:]
        for channel in favorites { let item = bookmark(channel); items[item.id] = item }
        for key in personal.keys(prefix: "library.item.") {
            if var item = personal.value(key, default: Optional<LibraryBookmark>.none) {
                if item.kind == .channel, let channel = channelIndex[item.reference] { item.name = name(channel) }
                items[item.id] = item
            }
        }
        for item in sportsLibrary { let entry = bookmark(item); items[entry.id] = entry }
        for group in groups {
            let item = LibraryBookmark(kind: .collection, reference: group.id.uuidString, name: group.name)
            items[item.id] = item
        }
        return items.values.sorted {
            let a = isLibraryFavorite($0), b = isLibraryFavorite($1)
            return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func hasLibraryItem(_ item: LibraryBookmark) -> Bool {
        switch item.kind {
        case .team, .league: hasSportsItem(SportsLibraryItem(name: item.reference, kind: item.kind == .team ? .team : .league))
        case .collection: groups.contains { $0.id.uuidString == item.reference }
        case .channel: personal.has("library.item.\(item.id)") || (channelIndex[item.reference].map { flag($0, "favorite") } ?? false)
        default: personal.has("library.item.\(item.id)")
        }
    }
    func saveLibraryItem(_ item: LibraryBookmark) {
        if item.kind == .team || item.kind == .league { saveSportsItem(SportsLibraryItem(name: item.reference, kind: item.kind == .team ? .team : .league)) }
        else { set("library.item.\(item.id)", item) }
    }
    func removeLibraryItem(_ item: LibraryBookmark) {
        if item.kind == .team || item.kind == .league { removeSportsItem(SportsLibraryItem(name: item.reference, kind: item.kind == .team ? .team : .league)); return }
        do {
            var changes: [String: Data?] = ["library.item.\(item.id)": nil, "library.favorite.\(item.id)": nil]
            if item.kind == .channel { changes["channel.\(item.reference).favorite"] = try JSONEncoder().encode(false) }
            if item.kind == .collection { changes["group.\(item.reference)"] = nil }
            try personal.write(changes); rebuild()
        } catch { inform("Changes weren’t saved", error.localizedDescription) }
    }
    func isLibraryFavorite(_ item: LibraryBookmark) -> Bool {
        switch item.kind {
        case .channel: personal.value("channel.\(item.reference).favorite", default: false)
        case .team, .league: isSportsFavorite(SportsLibraryItem(name: item.reference, kind: item.kind == .team ? .team : .league))
        default: personal.value("library.favorite.\(item.id)", default: false)
        }
    }
    func setLibraryFavorite(_ item: LibraryBookmark, _ favorite: Bool) {
        if favorite { saveLibraryItem(item) }
        switch item.kind {
        case .channel: set("channel.\(item.reference).favorite", favorite)
        case .team, .league: setSportsFavorite(SportsLibraryItem(name: item.reference, kind: item.kind == .team ? .team : .league), favorite)
        default: set("library.favorite.\(item.id)", favorite)
        }
    }
}
