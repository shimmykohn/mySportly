# Sports data, streams, and intelligence

Discussion proposal and implementation status, updated October 18, 2026. Current sports data, matching and picker work is separated from future AI recommendations below.

API-SPORTS Free is connected for reference exports. Authenticated checks blocked current 2026 seasons, so the user selected TV-guide games with available API-SPORTS names and logos. See [the verified free API comparison](sports-api-comparison.md). No purchase or additional AI integration is included.

## Current build

- Teams and leagues come from the bundled directory, with custom names supported. Membership and Favorites are separate and use the existing personal store/iCloud path.
- Current games are derived from EPG opponent pairs and broadcast windows, with conservative channel-name fallback against those games. Six leagues and 173 public API-SPORTS team/logo references are bundled, backed by a bounded per-device image cache. The free reference covers 2024 data; current roster coverage is not guaranteed. No key is shipped in the app. Games appear under Sports, teams and leagues with their matching feeds.
- Apple Foundation Models classification and search interpretation are implemented with runtime availability checks. The TypeSafe and OpenAI server adapters are written but the gateway is not deployed/configured. The OpenAI adapter uses Responses with Structured Outputs, not the Decisions API. PCC is disabled.
- Live shows interested categories first with compact previews, and other categories as drill-in rows. Sports expands only when selected as an interest; explicit Favorites and Recently Watched remain independent. My Lineup moved into the filter menu and the Live title was removed. Sports has a compact Browse by Sport disclosure. Sport screens discover repeated provider prefixes (including previously unknown league labels) without a league allowlist. These are browsing folders, not claims that feeds carry the same game. Groups respect lineup filters and manual category corrections; generic or ambiguous networks remain ungrouped.
- AVKit supplies playback controls. Native SwiftUI Stream and Quality pickers select a matching feed and an adaptive HLS preference. Switching releases the prior player item. Automatic recovery tries bounded event alternatives after playback produces audio without a video frame.

## Original product direction (future items remain recommendations)

Sports shows one row per game: teams and logos, league, start time/status, and the number of matching feeds. Opening it reveals a native list of feeds; Watch uses the preferred compatible feed. Rows show provider, language, and reported quality. Actual detected resolution can replace the provider label after playback begins. Automatic choice should prioritize compatibility, language, and previous successful playback over a claimed 4K label.

Library keeps Teams and Leagues as collections. Adding an item saves it; Favorite pins it. A team page offers its schedule and available feeds. A league page offers its games and teams, with standings as a secondary destination. A scheduled game without a matched feed offers a reminder and an honest unavailable state. It must not acquire a Watch button solely because an API says the game exists.

Use native SwiftUI lists, menus, sheets, header search, and system scroll edges throughout. Keep Live useful for all television; sports-specific content belongs in Sports and relevant team/league pages. Add a spoiler preference before displaying scores on the main browsing screens.

## Sports data and storage

[API-SPORTS](https://api-sports.io/) is the recommended provider to evaluate first. Its free tier advertises 100 requests per day per API. That is a shared developer quota, not 100 requests for every app user. A small server cache can protect the developer key and reuse requests without adding user accounts.

Its [NFL guide](https://www.api-football.com/news/post/how-to-get-started-with-api-nfl-the-complete-beginners-guide) documents stable team/league identities, logo URLs, schedules, status, results, standings, statistics, and coverage-dependent injuries. It explicitly recommends caching images; image requests do not consume the daily data quota, although rate limits apply. Check each sport and season's actual coverage before offering a feature.

Store metadata in a local database and logos in a bounded disk cache. Show saved data immediately on launch and refresh stale records asynchronously. Retain names if an image fails. Reference data refreshes infrequently; schedules refresh more often. Frequent live-score polling needs a separate quota budget: 100 daily calls cannot support continuous rapid updates. Basic start reminders can be scheduled locally; timely reschedule/score notifications while the app is closed require a backend/push path.

Use iCloud for personal membership, Favorites, manual match corrections, and preferences. Public metadata, logo files, and model downloads can be fetched per device and should not inflate the private sync database. Preserve existing library identities with an explicit alias-to-provider-ID migration; ambiguous/custom names remain valid and must not be guessed into a different team.

## Linking a game to its feeds

Use app-owned identities with namespaced provider IDs. Keep these entities distinct:

- League and team reference records.
- Event: league, participants, start/end window, season/round, status, and source update time.
- Channel/feed: the user's source identity, original name, EPG identifier, language and quality metadata.
- Event-feed link: event ID, channel ID, validity window, supporting evidence, and matching method/version.

First parse provider prefixes, team aliases, opponent pairs, league, dates and times. Retrieve a small set of plausible API events using that evidence. Link only when the evidence is sufficiently specific. Regional network names, one ambiguous nickname, or a league name alone do not establish a match. Use guide corrections/time offsets before comparing times. Event slots are reused, so mappings expire or change with the event window; ESPN is not permanently assigned to one team.

One event may have many feeds, and one channel may carry many events over time. Keep original channels accessible. Distinguish strong matches from suggestions; allow correction and removal. Save accepted results and rerun only when relevant metadata changes. Normal app opening reads the saved index and never waits for whole-catalog AI processing.

## Two AI jobs

| Job | Recommended approach |
| --- | --- |
| Fixed decisions: category, candidate game match, language evidence, duplicate-feed grouping | Local rules first. Evaluate an optional local decision model for ambiguous cases, or one hosted decision provider with consent. |
| Language tasks: interpreting a request, explaining results, previewing a proposed lineup | Apple Foundation Models when available; an optional OpenAI language model for requests that need it. |

Both paths consume actual catalog/guide/API evidence. A typed result limits its format and allowed choices; it does not guarantee the chosen game is correct. Include Unknown/No Match, validate every returned ID, and measure errors on real labeled provider examples. Model confidence alone must not authorize silent merging.

[TypeSafe's official API](https://docs.typesafe.ai/api) serves Jev as a hosted model. No official downloadable Jev weights were established in this review. [OpenAI Decisions](https://developers.openai.com/api/docs/guides/decisions) is a distinct hosted endpoint, currently public beta with gpt-6-luna, providing choice, predicate, and score answers. Evaluate these as alternatives for the same bounded decision task; do not call both for every channel. The existing Responses adapter would need a separate Decisions adapter.

Cloud requests should contain only short metadata and candidate IDs, never playlist credentials or playback URLs. Retain the existing server-side keys, consent, device registration, and usage-budget design. A provider choice remains open until an accuracy/cost/latency evaluation; there is no configured paid service today.

## Optional on-device decision model

[Laya](https://huggingface.co/convaiinnovations/laya) is a plausible evaluation candidate: its published model card identifies Apache-2.0 weights, 421M-parameter English and 322M multilingual models. The published downloads are approximately 808 MB and 647 MB respectively, before any app-specific conversion/compression. Those are upstream sizes, not a promised app download size or iPhone performance result. No iOS integration was established or benchmarked in this review.

[Core AI](https://developer.apple.com/core-ai/) is available in the iOS 27 SDK and runs converted models on Apple silicon. It supplies the execution framework, not the sports knowledge or trained decision model. Conversion, tokenization, quantization accuracy, memory, battery, and concurrent video playback must be tested on both physical devices before choosing a model.

Apple's system language model is OS-managed and availability-dependent. The [current Apple device list](https://support.apple.com/en-us/121115) includes this iPhone 17 Pro but not the iPad A16. Core AI compatibility is a separate question; the app's rules and cached matches must work everywhere even without any model.

If a local model materially improves measured matching, offer an optional Download Offline Organizer action with the actual size, storage check, Wi-Fi preference, progress, cancellation/retry, and Remove Download. Store versioned model data locally, verify the artifact, and keep it out of iCloud backups. Defer or pause inference during video playback or thermal pressure. Never redownload/reclassify the entire catalog on every launch.

## Native quality and feed controls

There are two separate settings: switching between provider URLs, and limiting adaptive quality within one HLS stream. Use native SwiftUI Menu/Picker controls in our player sheet for Feed and Quality. Auto is the default. Offer data-saving/resolution preferences only when supported by the asset and label provider quality honestly.

Apple's [preferredMaximumResolution](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredmaximumresolution) is a preferred HLS upper bound, not a promise of an exact resolution. The SDK marks [transportBarCustomMenuItems](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/transportbarcustommenuitems) as tvOS-only, unavailable on iOS. Keep AVKit's native playback controls and place the app's feed picker alongside them rather than claiming an iPhone AVKit menu extension exists. Preserve one active stream while switching.

## Suggested implementation order

1. Sports API adapter, persistent metadata/logo cache, and stable identities, preserving saved teams and leagues.
2. Event-to-feed links from conservative rules, one-game rows, and the native feed/quality controls.
3. A labeled matching evaluation with ambiguous names, reused slots, wrong dates, missing EPG, multiple languages, and multiple feeds per game.
4. Add whichever optional decision model improves that evaluation; enable language assistance independently.

Acceptance should include offline launch, stale/empty API responses, quota exhaustion, iCloud membership migration, inaccurate provider quality labels, and responsive navigation/video playback during background matching. This proposal does not authorize purchasing a plan or enabling paid model usage.
