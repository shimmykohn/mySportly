# Unified sports Library and Favorites Today

## Behavior

- Library has one Teams & Leagues collection. A saved league includes the teams in the local sports directory. Open its Teams row to browse and favorite them. The search finds both direct saves and included teams.
- League membership is derived, not copied into separate per-team cloud records. This works for directory leagues without adding a league-specific code path. Unknown leagues do not acquire guessed members.
- Existing individual and legacy saves stay intact. A favorited inherited team gets an explicit save in the same local transaction as its favorite, so removing its league preserves that choice. Removing a favorite keeps the item in Library. Removing a league removes only inherited membership and that league's favorite.
- My Sports uses the compact set of saved leagues and independent teams, avoiding repeated matching of all league members.
- Live shows Favorites Today before channel favorites and recent history. It includes broadcasts on now or coming later in the device's local calendar day. A broadcast spanning midnight can remain on now. Finished, cancelled and postponed games, tomorrow's starts and elapsed guide windows are excluded.
- Team and league favorites share one game row. Unparsed sports broadcasts (for example motorsport) can still appear from matching guide listings. A grouped game does not also appear as an individual guide listing.
- Home's guide query runs off the main actor and skips the full catalog scan for unscheduled channels. No model or network call is added to Home rendering. A 30-second foreground clock and scene activation update the day/time filters.

## Meaning of status and refresh

The app has no live score/event-status service. A passed guide end time does not prove that a game or stream ended. The game page now says the scheduled guide time has passed, and Guide Status uses No Remaining Guide Listings. Status words embedded in a channel's original title are supplied by the provider.

The current refresh operation imports both playlist and guide. Home pull-to-refresh, Sources and Guide Status expose it. Launch reads the saved cache; missing-source restoration only imports a source that has no local channels. There is no daily or periodic refresh scheduler yet. Failed guide refreshes retain the previous guide and do not advance its successful-import timestamp.

Proposed next work: separate guide refresh from full catalog import, refresh stale data while keeping cached browsing available, use roughly daily playlist and 4–6-hour guide freshness targets, show last successful update and stale status, and back off after failures. iOS background execution should be treated as opportunistic; freshness must also be checked on foreground activation.

## Rules, reference data and optional AI

Category and sport names, recognition aliases, language/country rules, and formatting tokens are fixed local rules. Actual channel inventories, repeated prefix subgroups, counts and stream matches are derived from the provider catalog and guide. Prefix grouping has no league allowlist. Sports names and logos use the bundled API-SPORTS reference plus offline aliases; that reference is updated with app builds and is not a current roster service.

A future naming assistant could receive a bounded sample of clean titles, provider group and proposed parent category, then return a validated group ID and one- or two-word label. Cache it against the group's metadata signature and preserve user edits. Names are untrusted input. Never send credentials or stream URLs; never use a generated label to silently merge feeds, decide game status, or change playback mapping. Apple Foundation Models guided generation is a candidate on supported devices; unsupported devices retain deterministic labels. No new AI feature was activated in this change.

## Verification

Local core and persistence suites passed: 65 core tests and 4 persistence tests. Added cases cover arbitrary league membership, reference arrival, independent saves, favorite schedule deduplication, midnight/DST boundaries, non-live states and guide-only sports.

Physical iPhone and iPad application-state tests passed for legacy saves, inherited membership, independent favorites, league removal and unfavoriting without removing a team. The full native UI flow passed on iPad (68.657 seconds) and iPhone (62.899 seconds): save NBA, open included teams, favorite Knicks independently, see one Home game despite two favorites/two streams, remove NBA, retain Knicks, and unfavorite while keeping the team saved. These are whole UI-test durations, not performance measurements. The existing add/remove team Sports-results check also passed on iPhone (31.475 seconds).

The first screen checks exposed an active team-search state and notification-intercepted toolbar taps. Return now ends the team search. The final tests explicitly submit search even when iPadOS does not expose its keyboard to XCTest, dismiss transient notification banners, and verify each back navigation. Screenshots from the final passing runs were inspected. Both apps were reopened normally with their saved catalogs afterward; no simulator was used.

Result bundles: `/private/tmp/mysportly-favorites-iphone-03.xcresult` and `/private/tmp/mysportly-favorites-ipad-02.xcresult`. Application-state checks: iPhone-01 and iPad-01 bundles with the same prefix. Local suite log: `/private/tmp/mysportly-favorites-core.log`.

Screenshots: [iPhone Home](evidence/library-favorites-2026-10-18/home-iphone-sample.png), [iPad Home](evidence/library-favorites-2026-10-18/home-ipad-sample.png), [iPad Library](evidence/library-favorites-2026-10-18/library-ipad-sample.png). The schedule shown is an explicitly labeled test fixture. This pass verifies Library and guide-display behavior; it does not retest provider playback, API access, or cross-device iCloud synchronization.
