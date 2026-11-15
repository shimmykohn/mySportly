# mySportly redesign

Date: 2026-11-08
Status: approved in conversation, awaiting written-spec review

## Goals

1. Opening the app shows Home in about 1 second with the saved catalog. Today it can take up to 2 minutes.
2. A native, Apple TV–inspired app where the UI speaks for itself: little explanatory text, no diagnostics in the main flows.
3. Playback gets its own screen, like YouTube or Apple Music.
4. One clear model for what you care about: follow teams, add leagues, favorite channels.
5. Search that feels instant, with no clutter.
6. AI that improves the catalog behind the scenes using the user's own OpenAI key.

## Non-goals

Recording, catch-up, Multiview, Siri/App Intents/Shortcuts, widgets, local reminders, spoiler preferences, guide-description translation, live scores, AI-written game blurbs.

## Approach

Keep the engine and replace the app on top. Keep the parsers (M3U, Xtream, XMLTV), the provider client, the catalog query index, guide-mapping recovery and the playback controller. Build a new app shell and new screens. Delete the removed features outright instead of keeping them working.

## Sub-projects, in build order

Each sub-project gets its own implementation plan and must leave the app buildable and usable.

### 1. Instant launch

Current cause: `AppStore.load()` decrypts and JSON-decodes the whole catalog (57k channels, 220k listings including expired ones), then rebuilds `PreparedCatalog` (directory, guide mappings, playback alternatives, query index) before hiding the loading overlay. CloudKit status, reminders and organization restore are also awaited before the first useful frame.

Design:
- Instrument first: add `os_signpost` intervals for decrypt, decode, each `PreparedCatalog` stage, and first Home frame. Measure the saved catalog on the user's iPhone before optimizing, and fix the largest phases first.
- **Home snapshot:** a small encrypted file containing exactly what Home renders (hero candidates, followed-team games, added-league rows, favorite channels with logo, current program, and stream reference). Write it after each successful prepare and read it first on launch. Home renders from it, and tapping a channel plays immediately.
- **Persisted prepared catalog:** store the prepared indexes along with a fingerprint (catalog content version + personal-choices revision + rules version). If the fingerprint matches on launch, load the indexes and skip the rebuild. Rebuild only after an import, a user change, or a rules/AI-result change.
- **Smaller, faster storage:** use a binary encoding (not JSON) for catalog and index files. Drop guide listings that ended, and keep only listings from now through +3 days.
- **Lineup first:** prepare the user's lineup (region/language scope) before the full catalog. Load the full-catalog Guide/Search index in the background after Home is visible. Searches before it's ready return lineup results.
- **No blocking network:** source refresh, restoring missing sources and AI work start only after the first Home frame, and only when due.
- **Acceptance:** a physical-device test fails if Home takes longer than 1.5 s to become interactive with the saved catalog. Use an optimized build (`SWIFT_OPTIMIZATION_LEVEL=-O`) for timing.

### 2. New shell and Home

- Tabs: **Home · Guide · My Stuff · Search** (`.sidebarAdaptable` on iPad). Live, Sports and Library tabs are removed, and their useful content moves into Home and My Stuff.
- Settings is opened from a profile button on Home's navigation bar. It contains Sources, OpenAI key, Region and language, Appearance, and iCloud sync. Nothing else.
- Home layout, top to bottom:
  1. **Hero banner:** up to 3 pages, swipeable. Priority: a followed team's live game → a followed team's next game today → a big game in an added league (live first) → a live program on a favorite channel. Art is team colors plus both team logos from the bundled sports reference, on Liquid Glass, or the channel logo for non-game picks. Actions: Watch, Follow/Favorite.
  2. **Your teams:** live and upcoming games for followed teams (live badge, start time).
  3. **One row per added league,** for example "NBA tonight".
  4. **Your channels:** favorite channels with the current program.
  - Empty rows are hidden. With nothing followed, Home shows a single native prompt to follow a team or add a league.
- Home renders only from the Home snapshot or prepared data. No network or model call happens in Home rendering. A 30 s foreground clock keeps live/upcoming states current.

### 3. Player

- Full-screen player screen opened with the native zoom navigation transition from the tapped item. Swipe down to minimize into the mini player (`tabViewBottomAccessory`). Rotating to landscape goes full screen.
- Portrait content: video, title, channel and league, live progress bar for the current guide program, previous/next channel, play/pause. AirPlay, PiP, audio/subtitle menus, and a favorite heart. Nothing else.
- Built on AVKit (`AVPlayerViewController`) for native controls. Keep the existing behaviors: first-frame readiness, bounded reconnect, alternate feeds used automatically on failure, previous channel.

### 4. Follow model and My Stuff

- **Team → Follow.** Followed teams' games go to the top of Home and can send a notification when a game starts (opt-in per team, off by default).
- **League → Add to My Sports.** Gives a league row on Home and surfaces the league in Search. Doesn't follow any teams.
- **Channel → Favorite.** Shown in Your channels.
- No separate "saved" state, and no stars on top of saves.
- **My Stuff tab:** one list with sections Teams, Leagues, Channels. Swipe to remove. Tapping a team or league opens its page (upcoming games on the user's lineup). Tapping a channel plays it.
- **Migration (non-destructive, one-time):** saved or starred teams → followed. Saved leagues → added. Favorite or saved channels → favorite. Saved categories, channel groups and custom collections are not carried into the new UI. Their records are left in place and simply unused.
- "Hide channel" stays as a context-menu action. All other organizer tools (rename, reorder, bulk edit, custom groups, guide mapping screens, Guide Status, Where Data Comes From, Channel Details diagnostics) are removed.

### 5. Search

- Before typing: recent searches and browse tiles (Sports, News, Movies, Kids, plus one tile per added league and common sports).
- As you type: instant local results grouped as **Teams, Live now, Channels**, ranked by your lineup and follows.
- Removed: "Try a search" copy, filter bar, scope controls, "Ask Apple Intelligence".
- AI fallback (sub-project 6) runs only when local matching can't interpret the query, for example "knicks tonight" or "premier league in spanish". Results appear in place with no separate button.

### 6. AI with OpenAI

The user's OpenAI API key is entered in Settings and stored in the device Keychain. It is never bundled, logged, synced, or written to the catalog. Without a key, everything works using local rules only.

| Job | API | Notes |
|---|---|---|
| Categorize channel groups | Decisions API `choice` (`gpt-6-luna`), two requests: category, then subcategory | Port of `GroupDecisions` from TypeSafe Jev. Keep confidence thresholds (auto-apply ≥0.60 confidence and ≥0.70 selected probability). Below that, keep the local/provider category. |
| Merge duplicate feeds (HD/4K/backup) | Decisions API `predicate` | Only for candidate pairs found locally (shared normalized name, same source/country). |
| Detect games in guide listings | Local parsing proposes candidate teams/league, then Decisions API `choice` among those candidates (≤255) | Feeds Home's teams/league rows. |
| Search fallback | Decisions API `choice` questions over known values: sport, league, team, time window, language | Called only when local search can't interpret the query, with a short timeout. Local results are shown in the meantime. |
| Clean display names | Local rules first. Leftovers go to an OpenAI Responses model with a strict JSON schema | Output is validated (length, must be derived from the original) and cached. Never used to merge feeds or change playback. |

- Runs in the background after an import and on foreground when there are new or changed groups. Batches up to 400 questions per Decisions request. Results are cached per group signature and synced via private iCloud like today's decisions. Unchanged groups are never resent.
- Inputs: channel/group titles, provider folder labels, region/language labels, guide titles. Never credentials, stream URLs, or viewing history. All text is treated as data.
- Removed: TypeSafe Jev client, Apple Foundation Models / PCC paths, Settings → AI screen, continued-processing Live Activity for organization.

## Error handling

- Home snapshot missing or corrupt → fall back to the persisted prepared catalog, then to a full rebuild, with a single native spinner in the navigation title.
- AI call failure or missing key → keep local results, retry with backoff on the next import or foreground. Never show errors inline in Home or Search. Settings shows the key status.
- Playback failure → automatic alternate feed, then a native inline error on the player with Retry.

## Testing

- Core Swift package tests (`swift test`) for: snapshot round-trip and fingerprint invalidation, expired-listing pruning, Home hero ranking, follow-model migration, local search grouping, and Decisions request/response mapping (with recorded fixtures, never live keys in tests).
- Physical-device tests (no simulators, per README): launch-to-interactive budget, Home renders from snapshot, player open/minimize/restore with Apple's sample HLS stream, migration of existing saves.
- Remove the tests for deleted features along with the features.
