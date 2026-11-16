import Foundation
import Testing
@testable import SportlyCore

struct VODTests {
    let source = UUID()

    @Test func titlesLoseProviderNoiseAndKeepTheYear() {
        #expect(VODTitle.clean("EN | The Batman (2022) 4K") == ("The Batman", 2022))
        #expect(VODTitle.clean("Dune - 2021") == ("Dune", 2021))
        #expect(VODTitle.clean("Blade Runner 2049").title == "Blade Runner 2049")
        #expect(VODTitle.clean("Blade Runner 2049").year == nil)
        #expect(VODTitle.clean("(2020)").title == "(2020)")
    }

    @Test func moviesDecodeMixedTypesAndSkipBadRows() throws {
        let json = #"""
        [{"stream_id": 12, "name": "EN | Heat (1995)", "stream_icon": "https://img/heat.jpg", "category_id": "4", "rating": "8.3", "added": "1700000000", "container_extension": "mkv"},
         {"stream_id": "13", "name": "Up", "stream_icon": "", "category_id": 4, "rating": 0, "container_extension": null},
         {"stream_id": "13", "name": "Up again"},
         {"name": "No id"},
         "garbage"]
        """#
        let movies = XtreamVOD.movies(Data(json.utf8), sourceID: source)
        #expect(movies.map(\.title) == ["Heat", "Up"])
        #expect(movies[0].year == 1995)
        #expect(movies[0].poster == URL(string: "https://img/heat.jpg"))
        #expect(movies[0].rating == 8.3)
        #expect(movies[0].container == "mkv")
        #expect(movies[1].container == "mp4")
        #expect(movies[1].rating == nil)
        #expect(movies[0].id == StableID.vod(source: source, kind: "movie", provider: "12"))
    }

    @Test func categoriesAndEmptyResponses() {
        #expect(XtreamVOD.categories(Data(#"[{"category_id":"1","category_name":"Action"},{"category_id":2}]"#.utf8)).map(\.name) == ["Action", "Other"])
        #expect(XtreamVOD.movies(Data(#"{"user_info":{"auth":0}}"#.utf8), sourceID: source).isEmpty)
        #expect(XtreamVOD.series(Data("".utf8), sourceID: source).isEmpty)
    }

    @Test func seriesInfoBuildsSortedSeasonsWithCleanEpisodeTitles() throws {
        let show = Series(id: "s", sourceID: source, providerID: "7", rawTitle: "EN | Severance", title: "Severance")
        let keyed = #"""
        {"seasons": [{"season_number": 1, "name": "Season One"}],
         "info": {"backdrop_path": ["https://img/back.jpg"]},
         "episodes": {"2": [{"id": "202", "episode_num": 1, "title": "Severance - S02E01 - Hello, Ms. Cobel", "container_extension": "mp4"}],
                      "1": [{"id": "102", "episode_num": "2", "title": "Half Loop", "info": {"duration_secs": "3200"}},
                            {"id": "101", "episode_num": 1, "title": "", "container_extension": "mkv"}]}}
        """#
        let detail = XtreamVOD.seriesDetail(Data(keyed.utf8), series: show)
        #expect(detail.seasons.map(\.number) == [1, 2])
        #expect(detail.seasons[0].name == "Season One")
        #expect(detail.seasons[1].name == "Season 2")
        #expect(detail.seasons[0].episodes.map(\.title) == ["Episode 1", "Half Loop"])
        #expect(detail.seasons[0].episodes[1].duration == 3200)
        #expect(detail.seasons[1].episodes[0].title == "Hello, Ms. Cobel")
        #expect(detail.backdrop == URL(string: "https://img/back.jpg"))

        let listed = #"{"episodes": [[{"id": 1, "episode_num": 1, "season": 3, "title": "A"}]]}"#
        #expect(XtreamVOD.seriesDetail(Data(listed.utf8), series: show).seasons.map(\.number) == [3])
    }

    @Test func movieDetailAcceptsStringOrListBackdrop() {
        let json = #"{"info": {"plot": " A heist. ", "duration_secs": 10200, "backdrop_path": "https://img/b.jpg", "releasedate": "1995-12-15"}}"#
        let detail = XtreamVOD.movieDetail(Data(json.utf8))
        #expect(detail.plot == "A heist.")
        #expect(detail.duration == 10200)
        #expect(detail.backdrop == URL(string: "https://img/b.jpg"))
        #expect(detail.year == 1995)
    }

    @Test func playbackURLUsesKindAndContainer() {
        let url = XtreamVOD.playbackURL(root: URL(string: "http://host:8080")!, path: "series", username: "u", password: "p", providerID: "55", container: "mkv")
        #expect(url.absoluteString == "http://host:8080/series/u/p/55.mkv")
    }

    func progress(_ id: String, at position: Double, of duration: Double, updated: TimeInterval, show: String? = nil) -> WatchProgress {
        WatchProgress(itemID: id, kind: show == nil ? .movie : .episode, sourceID: source, providerID: id, container: "mp4", title: id,
                      seriesID: show, position: position, duration: duration, updated: Date(timeIntervalSince1970: updated))
    }

    @Test func resumeRules() {
        #expect(progress("a", at: 10, of: 6000, updated: 0).resumePosition == nil, "Too early to resume")
        #expect(progress("a", at: 600, of: 6000, updated: 0).resumePosition == 600)
        #expect(progress("a", at: 5800, of: 6000, updated: 0).isFinished, "Within two minutes of the end")
        #expect(progress("a", at: 950, of: 1000, updated: 0).isFinished, "95% through")
        var watched = progress("a", at: 600, of: 6000, updated: 0); watched.watched = true
        #expect(watched.resumePosition == nil)
    }

    @Test func continueWatchingIsNewestFirstWithOneEntryPerShow() {
        let items = ContinueWatching.items([
            progress("movie", at: 600, of: 6000, updated: 10),
            progress("e1", at: 300, of: 3000, updated: 20, show: "show"),
            progress("e2", at: 300, of: 3000, updated: 30, show: "show"),
            progress("done", at: 5990, of: 6000, updated: 40),
        ])
        #expect(items.map(\.itemID) == ["e2", "movie"])
    }

    @Test func upNextAndNextEpisode() {
        let episodes = (1...3).map { Episode(id: "e\($0)", providerID: "\($0)", season: 1, number: $0, title: "E\($0)") }
        let detail = SeriesDetail(seasons: [Season(number: 1, name: "Season 1", episodes: episodes)])
        #expect(ContinueWatching.upNext(in: detail, progress: [:])?.id == "e1")
        #expect(ContinueWatching.upNext(in: detail, progress: ["e1": progress("e1", at: 2990, of: 3000, updated: 1)])?.id == "e2")
        #expect(ContinueWatching.upNext(in: detail, progress: ["e2": progress("e2", at: 600, of: 3000, updated: 1)])?.id == "e2")
        #expect(ContinueWatching.nextEpisode(after: "e2", in: detail)?.id == "e3")
        #expect(ContinueWatching.nextEpisode(after: "e3", in: detail) == nil)
    }
}

struct VODShelfTests {
    let a = UUID(), b = UUID()
    func movie(_ id: String, _ title: String, source: UUID, category: String, added: Double? = nil) -> Movie {
        Movie(id: id, sourceID: source, providerID: id, rawTitle: title, title: title, categoryID: category, added: added.map(Date.init(timeIntervalSince1970:)))
    }

    @Test func rowsMergeCategoriesAcrossSourcesByCleanName() {
        let movies = [movie("1", "Heat", source: a, category: "1"), movie("2", "Up", source: b, category: "9"), movie("3", "Odd", source: a, category: "x")]
        let rows = VODShelf.rows(movies, categories: [a: [VODCategory(id: "1", name: "EN | Action")], b: [VODCategory(id: "9", name: "Action")]])
        #expect(rows.map(\.title) == ["Action", "Other"])
        #expect(rows[0].items.map(\.id) == ["1", "2"])
    }

    @Test func recentAndSearch() {
        let movies = [movie("1", "Heat", source: a, category: "1", added: 10), movie("2", "The Heat", source: a, category: "1", added: 20), movie("3", "Up", source: a, category: "1")]
        #expect(VODShelf.recentMovies(movies).map(\.id) == ["2", "1"])
        #expect(VODShelf.search("heat", in: movies).map(\.id) == ["1", "2"])
        #expect(VODShelf.search("h", in: movies).isEmpty)
    }
}

struct VODFormatTests {
    @Test func containersAreRequestedAsTheyAre() {
        #expect(VODFormat.requested("MP4") == "mp4")
        #expect(VODFormat.requested("MKV") == "mkv")
        #expect(VODFormat.requested("avi") == "avi")
        #expect(!VODFormat.isNative("webm"))
    }
}
