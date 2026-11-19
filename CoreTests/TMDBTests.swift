import Foundation
import Testing
@testable import SportlyCore

struct TMDBDetailsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func movieDetailsChooseArtRatingTrailerAndCast() throws {
        let title = try #require(TMDBDecode.title(Data(TMDBFixtures.movie.utf8), kind: .movie, fetched: now))
        #expect(title.kind == .movie && title.id == 550 && title.title == "Fight Club" && title.year == 1999)
        #expect(title.overview.hasPrefix("A ticking"), "Trimmed")
        #expect(title.backdrops == ["/neutralHigh.jpg", "/neutralFewerVotes.jpg", "/neutralLow.jpg", "/englishBackdrop.jpg"],
                "No language first, then English, each by vote; other languages and bad paths left out")
        #expect(title.logo == "/englishLogo.svg", "English logo before the one without a language")
        #expect(title.trailer == "officialNew", "Newest official English YouTube trailer; not fan, teaser, Vimeo or German")
        #expect(title.trailerURL == URL(string: "https://www.youtube.com/watch?v=officialNew"))
        #expect(title.certification == "R", "The US theatrical rating")
        #expect(title.rating == 8.4)
        #expect(title.cast.map(\.name) == ["Edward Norton", "Brad Pitt", "Helena Bonham Carter"], "Billing order, unnamed left out")
        #expect(title.cast[0].character == "The Narrator" && title.cast[0].photo == "/edward.jpg" && title.cast[2].photo == nil)
        #expect(title.recommendations.map(\.id) == [680, 807], "Once each, movies only")
        #expect(title.recommendations[0] == TMDBReference(id: 680, title: "Pulp Fiction", originalTitle: "Pulp Fiction", year: 1994))
        #expect(title.collection == nil)
        #expect(title.fetched == now)
    }

    @Test func oddPartsAreLeftOutNotFatal() throws {
        let title = try #require(TMDBDecode.title(Data(TMDBFixtures.movieInCollection.utf8), kind: .movie, fetched: now))
        #expect(title.collection == TMDBReference(id: 263, title: "The Dark Knight Collection"))
        #expect(title.rating == nil, "Three votes aren't enough")
        #expect(title.logo == "/neutralLogo.png", "No English logo: the one without a language, never French")
        #expect(title.backdrops.isEmpty && title.trailer == nil && title.cast.isEmpty && title.certification == nil)
        #expect(TMDBDecode.title(Data(#"{"id": 0, "title": "Zero"}"#.utf8), kind: .movie, fetched: now) == nil)
        #expect(TMDBDecode.title(Data("not json".utf8), kind: .movie, fetched: now) == nil)
    }

    @Test func showDetailsUseTheUSContentRating() throws {
        let show = try #require(TMDBDecode.title(Data(TMDBFixtures.show.utf8), kind: .tv, fetched: now))
        #expect(show.kind == .tv && show.title == "Breaking Bad" && show.year == 2008)
        #expect(show.certification == "TV-MA")
        #expect(show.backdrops == ["/breakingBad.jpg"] && show.logo == nil && show.trailer == nil)
        #expect(show.cast.map(\.character) == ["Walter White"])
        #expect(show.recommendations == [TMDBReference(id: 60059, title: "Better Call Saul", originalTitle: "Better Call Saul", year: 2015)])
        #expect(show.collection == nil)
    }

    @Test func searchFindAndCollection() throws {
        #expect(TMDBDecode.search(Data(TMDBFixtures.search.utf8)).map(\.id) == [949, 136400, 2], "No id or no title: left out")
        #expect(TMDBDecode.search(Data("[]".utf8)).isEmpty)
        #expect(TMDBDecode.find(Data(TMDBFixtures.find.utf8), kind: .movie) == 550)
        #expect(TMDBDecode.find(Data(TMDBFixtures.find.utf8), kind: .tv) == nil)
        let collection = try #require(TMDBDecode.collection(Data(TMDBFixtures.collection.utf8), fetched: now))
        #expect(collection.name == "The Dark Knight Collection")
        #expect(collection.parts.map(\.id) == [272, 155, 49026, 999], "By release date, undated last")
        #expect(collection.parts[1].title == "The Dark Knight" && collection.parts[1].year == 2008)
    }

    @Test func trailerKeysAreChecked() {
        #expect(TMDBChoice.isYouTubeKey("dQw4w9WgXcQ"))
        #expect(!TMDBChoice.isYouTubeKey("bad key&x=1"))
        #expect(!TMDBChoice.isYouTubeKey(nil))
        var title = TMDBTitle(kind: .movie, id: 1, title: "A", fetched: now)
        title.trailer = "../evil"
        #expect(title.trailerURL == nil)
    }
}

struct TMDBRequestTests {
    @Test func detailsAppendEverythingAPageShows() {
        #expect(TMDBEndpoint.details(.movie, id: 550).absoluteString ==
                "https://api.themoviedb.org/3/movie/550?append_to_response=images,videos,credits,recommendations,release_dates&include_image_language=en,null&language=en-US")
        #expect(TMDBEndpoint.details(.tv, id: 1396).absoluteString ==
                "https://api.themoviedb.org/3/tv/1396?append_to_response=images,videos,credits,recommendations,content_ratings&include_image_language=en,null&language=en-US")
    }

    @Test func searchSendsOnlyTheTitleAndYear() {
        let url = TMDBEndpoint.search(.movie, title: "Romeo + Juliet & Co", year: 1996)
        #expect(url.absoluteString == "https://api.themoviedb.org/3/search/movie?query=Romeo%20%2B%20Juliet%20%26%20Co&include_adult=false&language=en-US&year=1996")
        #expect(TMDBEndpoint.search(.tv, title: "Severance").absoluteString ==
                "https://api.themoviedb.org/3/search/tv?query=Severance&include_adult=false&language=en-US")
        #expect(TMDBEndpoint.find(imdbID: "tt0137523").absoluteString ==
                "https://api.themoviedb.org/3/find/tt0137523?external_source=imdb_id&language=en-US")
        #expect(TMDBEndpoint.collection(263).absoluteString == "https://api.themoviedb.org/3/collection/263?language=en-US")
        for url in [url, TMDBEndpoint.details(.movie, id: 1), TMDBEndpoint.find(imdbID: "tt0000001"), TMDBEndpoint.collection(1)] {
            #expect(url.host == "api.themoviedb.org" && url.scheme == "https")
            #expect(!url.absoluteString.contains("api_key"), "The token goes in a header, never the URL")
        }
    }

    @Test func imageURLs() {
        #expect(TMDBImage.url("/abc.jpg", size: .backdrop) == URL(string: "https://image.tmdb.org/t/p/w1280/abc.jpg"))
        #expect(TMDBImage.url("/logo.svg", size: .logo) == URL(string: "https://image.tmdb.org/t/p/w500/logo.png"), "SVG logos as PNG")
        #expect(TMDBImage.url("/face.jpg", size: .profile) == URL(string: "https://image.tmdb.org/t/p/w185/face.jpg"))
        #expect(TMDBImage.url("abc.jpg", size: .backdrop) == nil)
        #expect(TMDBImage.url("/../../etc/passwd", size: .backdrop) == nil)
        #expect(TMDBImage.url("/a b.jpg", size: .backdrop) == nil)
    }

    @Test func onlyTheReadAccessTokenIsAccepted() {
        let token = "eyJ" + String(repeating: "a", count: 40) + "." + String(repeating: "b", count: 60) + "." + String(repeating: "c-_", count: 14)
        #expect(TMDBToken.isReadAccessToken(token))
        #expect(!TMDBToken.isReadAccessToken(token + " "))
        #expect(!TMDBToken.isReadAccessToken("eyJ" + String(repeating: "a", count: 100)), "Three parts")
        #expect(!TMDBToken.isReadAccessToken(String(repeating: "0", count: 32)))
        #expect(TMDBToken.isAPIKey(String(repeating: "0a", count: 16)))
        #expect(!TMDBToken.isAPIKey(token))
    }

    @Test func failures() {
        #expect(TMDBFailure(status: 401) == .credentials)
        #expect(TMDBFailure(status: 404) == .notFound)
        #expect(TMDBFailure(status: 429) == .busy)
        #expect(TMDBFailure(status: 500) == .unavailable)
        #expect(TMDBFailure.credentials.errorDescription?.contains("token") == true)
    }
}

struct TMDBMatchTests {
    let results = TMDBDecode.search(Data(TMDBFixtures.search.utf8))

    @Test func titlesNormalize() {
        #expect(TMDBMatch.normalized("The Lord of the Rings: The Fellowship of the Ring") == "lord of the rings the fellowship of the ring")
        #expect(TMDBMatch.normalized("Amélie") == "amelie")
        #expect(Set(["Ocean’s Eleven", "Ocean's Eleven", "Oceans Eleven"].map(TMDBMatch.normalized)) == ["oceans eleven"])
        #expect(TMDBMatch.normalized("Fast & Furious") == TMDBMatch.normalized("Fast and Furious"))
        #expect(TMDBMatch.normalized("Spider-Man: No Way Home") == "spider man no way home")
        #expect(TMDBMatch.normalized("The") == "the")
    }

    @Test func yearsWithinOneAgree() {
        #expect(TMDBMatch.yearsAgree(1995, 1996))
        #expect(!TMDBMatch.yearsAgree(1995, 1997))
        #expect(TMDBMatch.yearsAgree(nil, 1995) && TMDBMatch.yearsAgree(1995, nil))
    }

    @Test func bestResultMatchesTitleAndYear() {
        #expect(TMDBMatch.best(results, title: "Heat", year: 1995)?.id == 949)
        #expect(TMDBMatch.best(results, title: "Heat", year: 1996)?.id == 949, "A year apart")
        #expect(TMDBMatch.best(results, title: "Heat", year: 1986)?.id == 2)
        #expect(TMDBMatch.best(results, title: "Heat", year: 2000) == nil)
        #expect(TMDBMatch.best(results, title: "Heat", year: 2013)?.id == 136400, "\"The Heat\" is the same title")
        #expect(TMDBMatch.best(results, title: "heat", year: nil)?.id == 949, "No year: the first with the same name")
        #expect(TMDBMatch.best(results, title: "Cold", year: nil) == nil)
        #expect(TMDBMatch.best(results, title: "  ", year: 1995) == nil)
    }

    @Test func exactYearAndExactNameComeFirst() {
        let dunes = [TMDBReference(id: 1, title: "Dune", year: 2020), TMDBReference(id: 2, title: "Dune", year: 2021)]
        #expect(TMDBMatch.best(dunes, title: "Dune", year: 2021)?.id == 2)
        let mixed = [TMDBReference(id: 1, title: "Star Wars: The Clone Wars", year: 2008), TMDBReference(id: 2, title: "The Clone Wars", year: 2009)]
        #expect(TMDBMatch.best(mixed, title: "Clone Wars", year: 2008)?.id == 2, "Same name beats a containing one")
    }

    @Test func originalAndContainingNames() {
        let amelie = [TMDBReference(id: 194, title: "Amélie", originalTitle: "Le Fabuleux Destin d'Amélie Poulain", year: 2001)]
        #expect(TMDBMatch.best(amelie, title: "Le fabuleux destin d’Amelie Poulain", year: 2001)?.id == 194)
        let starWars = [TMDBReference(id: 11, title: "Star Wars", year: 1977)]
        #expect(TMDBMatch.best(starWars, title: "Star Wars Episode IV A New Hope", year: 1977)?.id == 11)
        #expect(TMDBMatch.best(starWars, title: "Star Wars Episode IV A New Hope", year: nil) == nil, "Containing names need a year")
        let up = [TMDBReference(id: 22947, title: "Up in the Air", year: 2009)]
        #expect(TMDBMatch.best(up, title: "Up", year: 2010) == nil, "Too short to count inside another name")
        let aliens = [TMDBReference(id: 679, title: "Aliens", year: 1986)]
        #expect(TMDBMatch.best(aliens, title: "Alien", year: 1985) == nil, "Whole words only")
    }

    @Test func translatedTitlesTakeTheTopResultFromTheExactYear() {
        let godfather = [TMDBReference(id: 238, title: "The Godfather", originalTitle: "The Godfather", year: 1972),
                         TMDBReference(id: 240, title: "The Godfather Part II", year: 1974)]
        #expect(TMDBMatch.best(godfather, title: "Der Pate", year: 1972)?.id == 238)
        #expect(TMDBMatch.best(godfather, title: "Der Pate", year: 1973) == nil, "Without the name, only the exact year")
        #expect(TMDBMatch.best(godfather, title: "Der Pate", year: nil) == nil)
        #expect(TMDBMatch.best(godfather, title: "Der Pate 2", year: 1974) == nil, "Only TMDB's top result")
    }

    @Test func aLookupThatKnowsMoreMatchesAgain() {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        let titleOnly = TMDBLookup(key: "m", kind: .movie, title: "The Lion King")
        var withYear = titleOnly; withYear.year = 1994
        var withIMDb = withYear; withIMDb.imdbID = "tt0110357"
        #expect([titleOnly, withYear, withIMDb].map(\.evidence) == [0, 1, 2])
        #expect(TMDBLookup(key: "m", kind: .movie, title: "x", tmdbID: 8587).evidence == 3)
        let fromHome = TMDBMatchRecord(tmdbID: 420818, saved: saved, evidence: titleOnly.evidence)
        #expect(fromHome.answers(titleOnly, at: saved + 60))
        #expect(!fromHome.answers(withYear, at: saved + 60), "The page knows the year: match again")
        let fromPage = TMDBMatchRecord(tmdbID: 8587, saved: saved, evidence: withIMDb.evidence)
        #expect(fromPage.answers(titleOnly, at: saved + 60) && fromPage.answers(withIMDb, at: saved + 60))
        #expect(!fromPage.answers(withIMDb, at: saved + 31 * 86_400), "Stale")
    }

    @Test func lookupsUseTheProvidersIDsFirst() {
        let source = UUID()
        var movie = Movie(id: "m", sourceID: source, providerID: "1", rawTitle: "EN | Heat (1995)", title: "Heat", year: nil, tmdbID: 1)
        var detail = MovieDetail()
        detail.year = 1995; detail.tmdbID = 949; detail.imdbID = "tt0113277"
        #expect(TMDBLookup.movie(movie, detail: detail) == TMDBLookup(key: "m", kind: .movie, title: "Heat", year: 1995, tmdbID: 949, imdbID: "tt0113277"))
        movie.year = 1996
        #expect(TMDBLookup.movie(movie, detail: nil) == TMDBLookup(key: "m", kind: .movie, title: "Heat", year: 1996, tmdbID: 1))
        let show = Series(id: "s", sourceID: source, providerID: "2", rawTitle: "Severance", title: "Severance", year: 2022, tmdbID: 95396)
        #expect(TMDBLookup.show(show, detail: SeriesDetail()) == TMDBLookup(key: "s", kind: .tv, title: "Severance", year: 2022, tmdbID: 95396))
    }

    @Test func cacheExpiry() {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        let found = TMDBMatchRecord(tmdbID: 550, saved: saved), missed = TMDBMatchRecord(tmdbID: nil, saved: saved)
        #expect(found.isFresh(at: saved + 29 * day) && !found.isFresh(at: saved + 31 * day))
        #expect(missed.isFresh(at: saved + 2 * day) && !missed.isFresh(at: saved + 4 * day))
        #expect(!found.isFresh(at: saved - day), "A clock that moved back counts as stale")
        let title = TMDBTitle(kind: .movie, id: 550, title: "Fight Club", fetched: saved)
        #expect(title.isFresh(at: saved + 6 * day) && !title.isFresh(at: saved + 8 * day))
        #expect(TMDBCachePolicy.retention < 180 * day, "Inside TMDB's six-month limit")
    }
}

struct TMDBLibraryTests {
    let source = UUID()
    func movie(_ id: String, _ title: String, year: Int?, tmdb: Int? = nil) -> Movie {
        Movie(id: id, sourceID: source, providerID: id, rawTitle: title, title: title, year: year, tmdbID: tmdb)
    }

    @Test func recommendationsInTheLibrary() {
        let index = TMDBLibraryIndex([
            movie("pulp", "Pulp Fiction", year: 1994, tmdb: 680),
            movie("seven", "Se7en", year: 1995),
            movie("heat86", "Heat", year: 1986),
            movie("begins", "Batman Begins", year: nil),
            movie("prestige", "The Prestige", year: 2006, tmdb: 9999),
            movie("memento", "Memento (Director's Cut)", year: 2000),
        ])
        let references = [
            TMDBReference(id: 680, title: "Pulp Fiction", year: 1994), TMDBReference(id: 807, title: "Se7en", year: 1995),
            TMDBReference(id: 949, title: "Heat", year: 1995), TMDBReference(id: 272, title: "Batman Begins", year: 2005),
            TMDBReference(id: 1124, title: "The Prestige", year: 2006), TMDBReference(id: 77, title: "Memento", year: 2000),
            TMDBReference(id: 680, title: "Pulp Fiction", year: 1994),
        ]
        #expect(index.matches(references, known: ["memento": 77]).map(\.id) == ["pulp", "seven", "begins", "memento"],
                "By id, by title within a year, by a match made before; never a title known to be another, once each")
        #expect(index.matches(references, excluding: ["pulp"]).map(\.id) == ["seven", "begins"])
        #expect(index.matches(references, known: ["seven": 12345]).map(\.id) == ["pulp", "begins"], "Known to be something else")
        #expect(index.matches([]).isEmpty)
    }

    @Test func showsMatchByOriginalName() {
        let shows = TMDBLibraryIndex([Series(id: "casa", sourceID: source, providerID: "1", rawTitle: "La Casa de Papel", title: "La Casa de Papel", year: 2017)])
        let reference = TMDBReference(id: 71446, title: "Money Heist", originalTitle: "La Casa de Papel", year: 2017)
        #expect(shows.matches([reference]).map(\.id) == ["casa"])
    }
}

struct XtreamTMDBTests {
    let source = UUID()

    @Test func listsCarryTheProvidersTMDBID() {
        let movies = #"""
        [{"stream_id": 1, "name": "Heat (1995)", "tmdb": "949"}, {"stream_id": 2, "name": "Up", "tmdb_id": 14160},
         {"stream_id": 3, "name": "None", "tmdb": "0"}, {"stream_id": 4, "name": "Odd", "tmdb": "tt0113277"},
         {"stream_id": 5, "name": "Huge", "tmdb": "1e30"}, {"stream_id": 6, "name": "Empty", "tmdb": "", "tmdb_id": "550"}]
        """#
        #expect(XtreamVOD.movies(Data(movies.utf8), sourceID: source).map(\.tmdbID) == [949, 14160, nil, nil, nil, 550])
        let series = #"[{"series_id": 1, "name": "Breaking Bad", "tmdb": "1396"}, {"series_id": 2, "name": "Other"}]"#
        #expect(XtreamVOD.series(Data(series.utf8), sourceID: source).map(\.tmdbID) == [1396, nil])
    }

    @Test func infoCarriesTMDBAndIMDbIDs() {
        let movie = XtreamVOD.movieDetail(Data(#"{"info": {"plot": "A heist.", "tmdb_id": "949", "imdb_id": "tt0113277"}}"#.utf8))
        #expect(movie.tmdbID == 949 && movie.imdbID == "tt0113277" && movie.plot == "A heist.")
        let other = XtreamVOD.movieDetail(Data(#"{"info": {"tmdb": 550, "imdb_id": "nm0000093"}}"#.utf8))
        #expect(other.tmdbID == 550 && other.imdbID == nil)
        let show = Series(id: "s", sourceID: source, providerID: "7", rawTitle: "Breaking Bad", title: "Breaking Bad")
        let detail = XtreamVOD.seriesDetail(Data(#"{"info": {"tmdb": "1396", "backdrop_path": []}, "episodes": {}}"#.utf8), series: show)
        #expect(detail.tmdbID == 1396 && detail.imdbID == nil)
    }
}
