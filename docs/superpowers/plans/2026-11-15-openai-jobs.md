# Remaining OpenAI Jobs Implementation Plan

**Goal:** Build the three AI jobs the redesign spec lists after group sorting: merge duplicate feeds, detect games in guide listings, clean display names.

**Spec:** `docs/superpowers/specs/2026-11-08-app-redesign-design.md` (AI table, rows 2–4).

## Decisions

- **One local cache, not iCloud.** Answers live in a sealed `ai.sealed` file (`AIResults`: merges by pair key, games by listing key with expiry, names by raw name). They are derived from the provider catalog, so they are not personal choices and never sync.
- **Applied as overrides, personal wins.** `AIResults.overrides(for:)` produces `channel.<id>.variants` and `channel.<id>.name` values that are merged under the user's own overrides before `PreparedCatalog` runs. A user rename or a manual split always wins.
- **Merges.** Local strict groups (same source, guide ID, quality-stripped name, language, region) apply without AI. Looser candidates (same source, region and aggressively normalised base name, not already together) become one `choice` question per pair (`same`/`different`), compared against the group's first channel. Accepted at confidence ≥ 0.70 and probability ≥ 0.80. Groups over 12 channels are skipped.
- **Games.** Matchup-looking sports listings the local parser can't resolve get two `choice` questions (first-named team, second-named team) over candidate teams: token hits plus every team of a league the listing names. Accepted when both answer, differ, share a league, and pass the same thresholds. Keyed by title+summary, so one answer covers every channel carrying it; expires at listing end.
- **Names.** `NameCleaning.local` (NFKC fold, region prefixes such as `US|`, quality and RAW/backup markers) applies to every name. Only names local rules leave suspicious go to `gpt-5-nano` through the Responses API with a strict JSON schema, 100 per request. A proposal is kept only if every word comes from the original name and it is not longer. Display only: playback, guide matching and merging use raw names.
- **When.** `runAIJobs()` runs with group sorting: at launch once the catalog is ready, on foreground, after a key is saved, and after every catalog or guide refresh. Only unanswered items are sent.

## Cost (gpt-6-luna $0.10 / 1M input, Decisions output free; gpt-5-nano $0.05 in / $0.40 out)

First run on a ~57k-channel catalog: well under $1 in total. After that, only new listings and channels: a few cents a day at most.

## Tests

Core: `NameCleaningTests`, `FeedMergingTests`, `GameDetectionTests`, `AIResultsTests`, Responses decoding. App behaviour is unchanged without a key except local name cleaning and strict feed merging.
