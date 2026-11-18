import Foundation

/// Recorded-shape TMDB responses (trimmed), as documented at
/// developer.themoviedb.org. No live calls; no token.
enum TMDBFixtures {
    /// `/movie/550?append_to_response=images,videos,credits,recommendations,release_dates`
    static let movie = #"""
    {
      "id": 550, "title": "Fight Club", "original_title": "Fight Club", "release_date": "1999-10-15",
      "overview": " A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression. ",
      "vote_average": 8.438, "vote_count": 30120, "belongs_to_collection": null,
      "images": {
        "backdrops": [
          {"aspect_ratio": 1.778, "height": 1080, "iso_639_1": "en", "file_path": "/englishBackdrop.jpg", "vote_average": 5.9, "vote_count": 12, "width": 1920},
          {"aspect_ratio": 1.778, "height": 1080, "iso_639_1": null, "file_path": "/neutralLow.jpg", "vote_average": 5.2, "vote_count": 4, "width": 1920},
          {"aspect_ratio": 1.778, "height": 2160, "iso_639_1": null, "file_path": "/neutralHigh.jpg", "vote_average": 5.6, "vote_count": 20, "width": 3840},
          {"aspect_ratio": 1.778, "height": 1080, "iso_639_1": null, "file_path": "/neutralFewerVotes.jpg", "vote_average": 5.6, "vote_count": 8, "width": 1920},
          {"aspect_ratio": 1.778, "height": 1080, "iso_639_1": "fr", "file_path": "/french.jpg", "vote_average": 6.0, "vote_count": 30, "width": 1920},
          {"aspect_ratio": 1.778, "height": 1080, "iso_639_1": null, "file_path": "not a path.jpg", "vote_average": 9.0, "vote_count": 99, "width": 1920}
        ],
        "logos": [
          {"aspect_ratio": 4.2, "height": 300, "iso_639_1": null, "file_path": "/neutralLogo.png", "vote_average": 5.5, "vote_count": 3, "width": 1260},
          {"aspect_ratio": 4.2, "height": 300, "iso_639_1": "en", "file_path": "/englishLogo.svg", "vote_average": 5.3, "vote_count": 2, "width": 1260}
        ],
        "posters": []
      },
      "videos": {
        "results": [
          {"iso_639_1": "en", "iso_3166_1": "US", "name": "Fan Trailer", "key": "fanTrailer1", "site": "YouTube", "size": 1080, "type": "Trailer", "official": false, "published_at": "2024-01-01T00:00:00.000Z", "id": "v1"},
          {"iso_639_1": "en", "iso_3166_1": "US", "name": "Official Trailer", "key": "officialOld", "site": "YouTube", "size": 1080, "type": "Trailer", "official": true, "published_at": "2014-06-05T11:00:00.000Z", "id": "v2"},
          {"iso_639_1": "en", "iso_3166_1": "US", "name": "20th Anniversary Trailer", "key": "officialNew", "site": "YouTube", "size": 1080, "type": "Trailer", "official": true, "published_at": "2019-10-15T16:00:00.000Z", "id": "v3"},
          {"iso_639_1": "en", "iso_3166_1": "US", "name": "Teaser", "key": "teaserKey01", "site": "YouTube", "size": 1080, "type": "Teaser", "official": true, "published_at": "2023-01-01T00:00:00.000Z", "id": "v4"},
          {"iso_639_1": "en", "iso_3166_1": "US", "name": "Vimeo Trailer", "key": "123456789", "site": "Vimeo", "size": 1080, "type": "Trailer", "official": true, "published_at": "2023-02-01T00:00:00.000Z", "id": "v5"},
          {"iso_639_1": "de", "iso_3166_1": "DE", "name": "Trailer (Deutsch)", "key": "germanKey01", "site": "YouTube", "size": 1080, "type": "Trailer", "official": true, "published_at": "2025-01-01T00:00:00.000Z", "id": "v6"}
        ]
      },
      "credits": {
        "cast": [
          {"id": 287, "name": "Brad Pitt", "character": "Tyler Durden", "profile_path": "/brad.jpg", "order": 1, "credit_id": "52fe4250c3a36847f80149f7"},
          {"id": 819, "name": "Edward Norton", "character": "The Narrator", "profile_path": "/edward.jpg", "order": 0, "credit_id": "52fe4250c3a36847f80149f3"},
          {"id": 1283, "name": "Helena Bonham Carter", "character": "Marla Singer", "profile_path": null, "order": 2, "credit_id": "52fe4250c3a36847f80149fb"},
          {"id": 7470, "name": "", "character": "Nobody", "order": 3, "credit_id": "52fe4250c3a36847f8014a00"}
        ],
        "crew": [{"id": 7467, "name": "David Fincher", "job": "Director", "department": "Directing"}]
      },
      "recommendations": {
        "page": 1, "total_pages": 1, "total_results": 4,
        "results": [
          {"id": 680, "title": "Pulp Fiction", "original_title": "Pulp Fiction", "release_date": "1994-09-10", "media_type": "movie"},
          {"id": 807, "title": "Se7en", "original_title": "Se7en", "release_date": "1995-09-22", "media_type": "movie"},
          {"id": 680, "title": "Pulp Fiction", "original_title": "Pulp Fiction", "release_date": "1994-09-10", "media_type": "movie"},
          {"id": 1396, "name": "Breaking Bad", "first_air_date": "2008-01-20", "media_type": "tv"}
        ]
      },
      "release_dates": {
        "results": [
          {"iso_3166_1": "DE", "release_dates": [{"certification": "18", "descriptors": [], "iso_639_1": "", "note": "", "release_date": "1999-11-11T00:00:00.000Z", "type": 3}]},
          {"iso_3166_1": "US", "release_dates": [
            {"certification": "", "descriptors": [], "iso_639_1": "", "note": "Venice", "release_date": "1999-09-10T00:00:00.000Z", "type": 1},
            {"certification": "NR", "descriptors": [], "iso_639_1": "", "note": "", "release_date": "2000-06-06T00:00:00.000Z", "type": 4},
            {"certification": "R", "descriptors": [], "iso_639_1": "", "note": "", "release_date": "1999-10-15T00:00:00.000Z", "type": 3}
          ]}
        ]
      }
    }
    """#

    /// A movie in a collection, with too few votes for a rating and a logo only in another language and none.
    static let movieInCollection = #"""
    {
      "id": 155, "title": "The Dark Knight", "release_date": "2008-07-16", "overview": "", "vote_average": 8.5, "vote_count": 3,
      "belongs_to_collection": {"id": 263, "name": "The Dark Knight Collection", "poster_path": "/poster.jpg", "backdrop_path": "/backdrop.jpg"},
      "images": {"backdrops": [], "logos": [
        {"iso_639_1": "fr", "file_path": "/frenchLogo.png", "vote_average": 9.0, "vote_count": 9},
        {"iso_639_1": null, "file_path": "/neutralLogo.png", "vote_average": 1.0, "vote_count": 1}
      ]},
      "videos": "unexpected",
      "credits": {"cast": [{"name": "Christian Bale", "order": "first"}]}
    }
    """#

    /// `/tv/1396?append_to_response=images,videos,credits,recommendations,content_ratings`
    static let show = #"""
    {
      "id": 1396, "name": "Breaking Bad", "original_name": "Breaking Bad", "first_air_date": "2008-01-20",
      "overview": "Walter White, a chemistry teacher, turns to a life of crime.", "vote_average": 8.9, "vote_count": 15000,
      "images": {"backdrops": [{"iso_639_1": null, "file_path": "/breakingBad.jpg", "vote_average": 5.5, "vote_count": 10}], "logos": []},
      "videos": {"results": []},
      "credits": {"cast": [{"id": 17419, "name": "Bryan Cranston", "character": "Walter White", "profile_path": "/bryan.jpg", "order": 0, "credit_id": "52542282760ee313280017f9"}]},
      "recommendations": {"results": [{"id": 60059, "name": "Better Call Saul", "original_name": "Better Call Saul", "first_air_date": "2015-02-08", "media_type": "tv"}]},
      "content_ratings": {"results": [{"descriptors": [], "iso_3166_1": "DE", "rating": "16"}, {"descriptors": [], "iso_3166_1": "US", "rating": "TV-MA"}]}
    }
    """#

    /// `/search/movie?query=Heat`
    static let search = #"""
    {"page": 1, "total_pages": 1, "total_results": 5, "results": [
      {"id": 949, "title": "Heat", "original_title": "Heat", "release_date": "1995-12-15", "popularity": 50.1},
      {"id": 136400, "title": "The Heat", "original_title": "The Heat", "release_date": "2013-06-27"},
      {"id": 2, "title": "Heat", "original_title": "Heat", "release_date": "1986-03-14"},
      {"id": 0, "title": "No id"},
      {"id": 3, "title": " "}
    ]}
    """#

    /// `/find/tt0137523?external_source=imdb_id`
    static let find = #"""
    {"movie_results": [{"id": 550, "title": "Fight Club", "release_date": "1999-10-15", "media_type": "movie"}], "person_results": [], "tv_results": [], "tv_episode_results": [], "tv_season_results": []}
    """#

    /// `/collection/263`; one part uses `name`, as the reference's schema shows.
    static let collection = #"""
    {"id": 263, "name": "The Dark Knight Collection", "overview": "", "parts": [
      {"id": 49026, "title": "The Dark Knight Rises", "original_title": "The Dark Knight Rises", "release_date": "2012-07-17", "media_type": "movie"},
      {"id": 999, "title": "Untitled Sequel", "release_date": "", "media_type": "movie"},
      {"id": 272, "title": "Batman Begins", "original_title": "Batman Begins", "release_date": "2005-06-10", "media_type": "movie"},
      {"id": 155, "name": "The Dark Knight", "original_name": "The Dark Knight", "release_date": "2008-07-16", "media_type": "movie"}
    ]}
    """#
}
