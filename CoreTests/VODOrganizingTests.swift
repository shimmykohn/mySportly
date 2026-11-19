import Foundation
import Testing
@testable import SportlyCore

@Suite struct VODLanguageTests {
    @Test func foldersAndTitlesTellTheLanguage() {
        #expect(VODLanguage.detect(category: "EN - Action", title: "The Batman (2022)") == "en")
        #expect(VODLanguage.detect(category: "|FR| NETFLIX", title: "Lupin") == "fr")
        #expect(VODLanguage.detect(category: "NETFLIX | DE", title: "Dark") == "de")
        #expect(VODLanguage.detect(category: "ARABIC MOVIES", title: "Wadjda") == "ar")
        #expect(VODLanguage.detect(category: "TR: Diziler", title: "Dizi") == "tr")
        #expect(VODLanguage.detect(category: "US MOVIES", title: "Up") == "en")
        // The title's own tag wins over its folder's.
        #expect(VODLanguage.detect(category: "EN - Movies", title: "FR - Le Film") == "fr")
        #expect(VODLanguage.detect(category: "Movies", title: "Le Film [IT]") == "it")
    }

    @Test func everydayWordsAreNotLanguages() {
        #expect(VODLanguage.detect(category: "IN CINEMAS", title: "Dune") == "")
        #expect(VODLanguage.detect(category: "Horror", title: "It: Chapter Two") == "")
        #expect(VODLanguage.detect(category: "Horror", title: "IT: CHAPTER TWO") == "")
        #expect(VODLanguage.detect(category: "ROM COM", title: "Notting Hill") == "")
        #expect(VODLanguage.detect(category: "Drama", title: "The French Dispatch") == "")
        #expect(VODLanguage.detect(category: "4K MOVIES", title: "X-Men (2000)") == "")
        #expect(VODLanguage.detect(category: "Action", title: "Al-Kabeer") == "")
        // An ambiguous code still counts when it's clearly a tag.
        #expect(VODLanguage.detect(category: "IN - Bollywood", title: "Film") == "hi")
        #expect(VODLanguage.detect(category: "|IT| Film", title: "Film") == "it")
    }

    @Test func myLanguagesKeepUntaggedTitles() {
        let mine = VODLanguages(choice: .mine, preferred: ["en", "he"])
        #expect(mine.includes("en") && mine.includes("he") && mine.includes("") && !mine.includes("fr"))
        #expect(mine.rank("en") < mine.rank("he") && mine.rank("he") < mine.rank("") && mine.rank("") < mine.rank("fr"))
        #expect(VODLanguages(choice: .all, preferred: ["en"]).includes("fr"))
        let french = VODLanguages(choice: .only("fr"), preferred: ["en"])
        #expect(french.includes("fr") && !french.includes("en") && !french.includes(""))
        #expect(french.rank("fr") == 0)
        // Before the user's languages are known, nothing is hidden.
        #expect(VODLanguages(choice: .mine, preferred: []).includes("fr"))
        #expect(VODLanguages.Choice(saved: "") == .mine && VODLanguages.Choice(saved: "all") == .all && VODLanguages.Choice(saved: "fr") == .only("fr"))
        #expect(VODLanguages.Choice.only("fr").saved == "fr")
    }
}

@Suite struct VODShelfMergingTests {
    private let source = UUID()

    @Test func serviceFoldersBecomeOneShelf() {
        #expect(VODService.name(for: "EN - NETFLIX MOVIES") == "Netflix")
        #expect(VODService.name(for: "|FR| NETFLIX 4K") == "Netflix")
        #expect(VODService.name(for: "Disney+ Kids") == "Disney+")
        #expect(VODService.name(for: "APPLE TV+") == "Apple TV+")
        #expect(VODService.name(for: "AMAZON PRIME SERIES") == "Prime Video")
        #expect(VODService.name(for: "HBO MAX") == "HBO Max")
        #expect(VODService.name(for: "PARAMOUNT+") == "Paramount+")
        #expect(VODService.name(for: "Action") == nil)
        #expect(VODService.name(for: "Discovery Channel") == nil)
    }

    @Test func shelfNamesDropTagsAndTrailingMovies() {
        #expect(VODShelf.shelfName("EN - Action Movies") == "Action")
        #expect(VODShelf.shelfName("FR - ACTION") == "ACTION")
        #expect(VODShelf.shelfName("Kids TV Shows") == "Kids")
        #expect(VODShelf.shelfName("TV Shows") == "TV Shows")
        #expect(VODShelf.shelfName("New Movies") == "New Movies")
        #expect(VODShelf.shelfName("Movies") == "Movies")
    }

    @Test func rowsMergeServicesAndSpellings() {
        let categories = [source: [VODCategory(id: "1", name: "EN - NETFLIX MOVIES"), VODCategory(id: "2", name: "FR - ACTION"),
                                   VODCategory(id: "3", name: "NETFLIX 4K"), VODCategory(id: "4", name: "EN - Action Movies")]]
        let movies = ["1", "2", "3", "4"].map { Movie(id: "m\($0)", sourceID: source, providerID: $0, rawTitle: "T\($0)", title: "T\($0)", categoryID: $0) }
        let rows = VODShelf.rows(movies, categories: categories)
        #expect(rows.map(\.title) == ["Netflix", "Action"])
        #expect(rows[0].items.map(\.id) == ["m1", "m3"])
        #expect(rows[1].items.map(\.id) == ["m2", "m4"])
    }

    @Test func aCopyInTheUsersLanguageLeads() {
        let french = Movie(id: "fr", sourceID: source, providerID: "1", rawTitle: "FR - Dune", title: "Dune")
        let english = Movie(id: "en", sourceID: source, providerID: "2", rawTitle: "EN - Dune", title: "Dune")
        let copies = ["EN - Dune": "FR - Dune"]
        let plain = VODCopies.fold([french, english], copies: copies)
        #expect(plain.shown.map(\.id) == ["fr"])
        let ranked = VODCopies.fold([french, english], copies: copies) { $0.id == "en" ? 0 : 2 }
        #expect(ranked.shown.map(\.id) == ["en"] && ranked.versions["en"] == ["fr"])
    }
}

@Suite struct WatchLaterTests {
    @Test func newestFirstWithoutWatchedMovies() {
        let source = UUID()
        let old = WatchLaterItem(itemID: "m1", kind: .movie, sourceID: source, title: "Old", added: Date(timeIntervalSince1970: 100))
        let new = WatchLaterItem(itemID: "s1", kind: .show, sourceID: source, title: "New", added: Date(timeIntervalSince1970: 200))
        let watched = WatchLaterItem(itemID: "m2", kind: .movie, sourceID: source, title: "Seen", added: Date(timeIntervalSince1970: 300))
        #expect(WatchLaterItem.list([old, new, watched], finished: ["m2", "s1"]).map(\.itemID) == ["s1", "m1"])
        #expect(WatchLaterItem.key("m1") == "vod.later.m1")
        let movie = Movie(id: "x", sourceID: source, providerID: "1", rawTitle: "R", title: "Shown", year: 2020)
        #expect(WatchLaterItem(movie).kind == .movie && WatchLaterItem(movie).title == "Shown" && WatchLaterItem(movie).year == 2020)
    }
}
