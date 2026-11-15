import Foundation

/// Demo movies and a show; every title plays Apple's public HLS example.
enum SampleVOD {
    static let sourceID = SampleCatalog.sourceID
    static let streamURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!

    static let catalog: VODCatalog = {
        var catalog = VODCatalog(sourceID: sourceID, fetched: .now)
        catalog.movieCategories = [VODCategory(id: "1", name: "Sports Documentaries"), VODCategory(id: "2", name: "Classics")]
        catalog.seriesCategories = [VODCategory(id: "10", name: "Drama")]
        let movies: [(String, String, Int, String)] = [
            ("1", "Sample Final Whistle", 2024, "1"), ("2", "Sample Long Season", 2023, "1"),
            ("3", "Sample Night Game", 1998, "2"), ("4", "Sample Comeback", 1986, "2"),
        ]
        catalog.movies = movies.map { id, title, year, category in
            Movie(id: "sample.movie.\(id)", sourceID: sourceID, providerID: id, rawTitle: "\(title) (\(year))", title: title, year: year,
                  categoryID: category, rating: 7.4, added: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)! * 86_400))
        }
        catalog.series = [Series(id: "sample.series.1", sourceID: sourceID, providerID: "1", rawTitle: "Sample Clubhouse", title: "Sample Clubhouse",
                                 year: 2025, categoryID: "10", plot: "An illustrative show for exploring the app without a provider.", genre: "Drama")]
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
