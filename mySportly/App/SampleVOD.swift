import Foundation

/// Demo movies and a show; every title plays Apple's public HLS example.
enum SampleVOD {
    static let sourceID = SampleCatalog.sourceID
    static let streamURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!

    static let catalog: VODCatalog = {
        var catalog = VODCatalog(sourceID: sourceID, fetched: .now)
        // Folders the way providers name them: language tags, and one
        // streaming service spread over several folders.
        catalog.movieCategories = [
            VODCategory(id: "1", name: "Sports Documentaries"), VODCategory(id: "2", name: "Classics"),
            VODCategory(id: "3", name: "EN - NETFLIX MOVIES"), VODCategory(id: "4", name: "|FR| NETFLIX"), VODCategory(id: "5", name: "NETFLIX 4K"),
            VODCategory(id: "6", name: "EN - Action Movies"), VODCategory(id: "7", name: "FR - ACTION"), VODCategory(id: "8", name: "AMAZON PRIME"),
        ]
        catalog.seriesCategories = [VODCategory(id: "10", name: "Drama"), VODCategory(id: "11", name: "EN - NETFLIX SERIES"), VODCategory(id: "12", name: "|AR| NETFLIX")]
        let movies: [(String, String, Int, String)] = [
            ("1", "Sample Final Whistle", 2024, "1"), ("2", "Sample Long Season", 2023, "1"),
            ("3", "Sample Night Game", 1998, "2"), ("4", "Sample Comeback", 1986, "2"),
            ("5", "Sample Night Heist", 2025, "3"), ("6", "Sample Dernier Match", 2024, "4"), ("7", "Sample Crown Run", 2022, "5"),
            ("8", "Sample Fast Break", 2021, "6"), ("9", "Sample La Poursuite", 2020, "7"), ("10", "Sample Harbor Lights", 2023, "8"),
            ("11", "DE - Sample Bergpokal", 1975, "2"),
        ]
        catalog.movies = movies.map { id, title, year, category in
            Movie(id: "sample.movie.\(id)", sourceID: sourceID, providerID: id, rawTitle: "\(title) (\(year))", title: VODTitle.clean("\(title) (\(year))").title,
                  year: year, categoryID: category, rating: 7.4, added: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)! * 86_400))
        }
        let shows: [(String, String, Int, String)] = [
            ("1", "Sample Clubhouse", 2025, "10"), ("2", "Sample Locker Room", 2024, "11"), ("3", "Sample Desert League", 2023, "12"),
        ]
        catalog.series = shows.map { id, title, year, category in
            Series(id: "sample.series.\(id)", sourceID: sourceID, providerID: id, rawTitle: title, title: title, year: year, categoryID: category,
                   plot: "An illustrative show for exploring the app without a provider.", genre: "Drama")
        }
        return catalog
    }()

    static func movieDetail(_ movie: Movie) -> MovieDetail {
        var detail = MovieDetail()
        detail.plot = "An illustrative title for exploring the app without a provider. It plays Apple’s public test stream."
        detail.duration = 600; detail.genre = "Documentary"; detail.year = movie.year
        return detail
    }

    static func seriesDetail(_ show: Series) -> SeriesDetail {
        let seasons = (1...2).map { season in
            Season(number: season, name: "Season \(season)", episodes: (1...4).map { number in
                Episode(id: "sample.episode.\(season).\(number)", providerID: "\(season)\(number)", season: season, number: number,
                        title: "Sample Episode \(number)", plot: "An illustrative episode.", duration: 600)
            })
        }
        return SeriesDetail(seasons: seasons)
    }
}
