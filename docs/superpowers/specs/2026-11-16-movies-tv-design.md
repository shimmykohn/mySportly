# Movies & TV ("Watch") — Design

Date: 2026-11-16 · Status: awaiting approval

## Goal

Bring in Xtream movies and TV shows in a new **Watch** tab. They can be reached from Search, and the most recent unfinished title shows as a card at the top of Home.

## Decisions (from the user)

| # | Choice |
|---|--------|
| 1 | Movies **and** TV shows |
| 2 | A new tab named **Watch**. It is findable from the Search tab, and Home shows the most recent unfinished title as a card at the top |
| 3 | The catalog loads the first time the Watch tab opens (or when Search needs it) and is then cached on the device. It is not loaded during source refresh |
| 4 | Resume and watched marks synced through iCloud; movies and shows appear in Search; titles are tidied (local rules first, AI for leftovers) |
| 5 | M3U sources stay live-only |

## Data source (Xtream `player_api.php`)

- Movies: `get_vod_categories` and `get_vod_streams`. Each stream gives `stream_id`, `name`, `stream_icon`, `category_id`, `rating`, `added` and `container_extension`. `get_vod_info&vod_id=` is called only when a movie's page opens, for the plot, length, year, genre and backdrop.
- Shows: `get_series_categories` and `get_series`. Each show gives `series_id`, `name`, `cover`, `plot`, `rating`, `releaseDate` and `category_id`. `get_series_info&series_id=` is called when a show's page opens; it returns seasons and episodes (`id`, `episode_num`, `title`, `container_extension`, `info.duration_secs`, `info.plot`).
- Playback URLs:
  - Movie: `{root}/movie/{user}/{pass}/{stream_id}.{container_extension}`
  - Episode: `{root}/series/{user}/{pass}/{episode_id}.{container_extension}`
- A provider with no VOD (empty arrays or an error on those actions) is not a failure. The tab shows "Your provider doesn't offer movies or shows."

## Components

**Core (SportlyCore, unit-tested)**
- `VODModels.swift`:
  - Types: `VODCategory`, `Movie`, `Series`, `Season`, `Episode`, and `VODCatalog` (per-source movies, series and categories, plus a fetch date).
  - IDs are stable: `StableID` of source plus provider ID.
- `XtreamVOD.swift`:
  - Pure decoders from `Data` to models. They reuse the flexible string/int decoding Xtream needs.
  - URL builders for movies and episodes.
- `WatchProgress.swift`:
  - `WatchProgress {position, duration, updated, title, artwork, seriesID?, episodeLabel?}`.
  - Rules:
    - finished at ≥ 95% or within 120 s of the end;
    - resume only after 30 s;
    - `continueWatching(from:)` returns unfinished items, newest first;
    - `nextEpisode(after:in:)`.
- `NameCleaning` reuse: VOD titles get the same local rules plus year handling. "EN | The Batman (2022) 4K" becomes "The Batman", with the year kept as metadata.

**App**
- `VODLibrary` (an `@Observable` owned by `AppStore`, kept separate so AppStore doesn't grow):
  - Per-source load state: idle, loading, loaded, empty or failed.
  - Merged catalog across Xtream sources.
  - A lowercase title index for search.
  - Loads from the sealed cache first, then fetches if the cache is missing or older than 24 h, or on pull-to-refresh.
- Cache: `vod.<sourceID>.sealed` in the existing catalog cache directory, sealed with AES-GCM and the same key. It stays on the device and never syncs.
- Progress and watched state in `PersonalStore` (synced through iCloud):
  - key `vod.progress.<itemID>`;
  - the title and artwork are stored with it, so the Home card works without loading the catalog;
  - written every 15 s during playback and again on pause, stop or close.
- Playback reuses `PlaybackController`:
  - `play(..., live: false, startAt:)` seeks to the resume point;
  - Now Playing is not marked live;
  - a periodic time observer reports progress;
  - no feed alternates.
- The player screen for VOD shows the title, year/season·episode and plot, with no Streams menu and no guide progress. The native controls handle seeking. At the end of an episode, a "Next Episode" button appears.

**UI**
- **Watch tab** (`AppTab.watch`, symbol `play.rectangle.on.rectangle`), placed between My Stuff and Search:
  - "Movies | TV Shows" segmented control;
  - Continue Watching row;
  - lazy category rows of posters (20 each with "See All", which opens a poster grid);
  - pull to refresh.
- **Movie page**: backdrop, Play/Resume, plot, year, length, rating, a watched toggle.
- **Show page**: season picker; episode list with progress bars and watched checks; Play next episode.
- **Search tab**:
  - a "Movies & TV" Browse tile that switches to the Watch tab;
  - typed searches add "Movies" and "TV Shows" result sections once the catalog is loaded, and loading starts from the cache on the first search.
- **Home**: a Continue Watching card at the very top (poster, title, progress bar, Resume) for the most recent unfinished title. It's hidden when there is none.
- **Demo mode**: a small sample catalog (a few movies and one show) that plays Apple's public test streams.

## AI title cleanup

The existing names job gains VOD titles that local rules leave looking like codes. They are capped (2000) and only new titles are sent. Results are shared with channel names (`aiResults.names`).

## Errors and limits

- Fetch failure: the saved catalog stays; a banner says "Couldn't refresh movies and shows."
- Large catalogs (50k+): decode off the main actor; rows render lazily; search runs over the index with a 100-result cap.
- Connection limits: VOD playback replaces the live stream on the main player, like a channel switch. Watch Two stays live-only.

## Testing

- Core: decoder fixtures (movies, series, series info, mixed int/string fields, empty or error VOD); URL builders; progress rules; continue-watching order; next episode; title cleaning.
- UI (demo): Watch tab lists movies and shows → play a movie → close → Home shows the card → Resume.

## Out of scope

M3U movie links, downloads/offline, trailers, TMDB artwork, parental filtering.
