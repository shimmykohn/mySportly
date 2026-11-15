# Player, Guide, and Sports Library review

Scope: native SwiftUI changes requested on October 18, 2026. Physical iPad and iPhone only; no simulator runtime was installed or used. Preserve the existing native lists, navigation, sheets, header search, and soft scroll edges.

## Findings and changes

- **Player:** the reported Cowboys–Packers 4K feed reached playing state with audio but no playable video track or presentation size on the iPad. An exact same-source/event/time alternate rendered 1280 × 720 video. The player now checks for absent video after eight seconds of actual playback and tries at most two matching feeds, releasing the preceding item first. It explains the switch or offers Stream Options if no playable alternative exists. This does not change AVPlayer’s codec support or guarantee every provider stream; the exact cause of the original feed’s missing playable video remains unconfirmed.
- **Dismissal:** the player uses a plain X with no circular/glass background. Video remains mounted while connecting. Dismissing the sheet preserves the mini player; Stop ends playback.
- **Guide:** the initial screen previously mixed time, lineup, guide health, layout, and listing controls. It now shows compact channel/now/next rows; channel details open the schedule. Time remains a toolbar action, while secondary controls and guide status are in Guide Filters. Future listings are explicitly marked “Later.”
- **Sports:** saved names match provider guide titles/descriptions using a local vocabulary and conservative aliases. Ambiguous names require league context. Matching event channels without guide listings are separate from confirmed scheduled programs; no scores or event times are invented.
- **Library:** Teams and Leagues are distinct collections. Add to Library saves an item and includes it in My Sports and relevant live recommendations. Favorite is a separate action that pins saved items at the top of Library and their collection. Unfavoriting preserves membership; removing an item clears its favorite. Each item opens a scoped schedule and matching channels.
- **Persistence:** existing follow lists remain readable. New membership changes and favorites use separate per-item entries in the existing private personal store. An explicit removal prevents an older follow list from reintroducing a removed item. Saving or favoriting sports does not rebuild the channel catalog.
- **Search:** submitting native header search dismisses its expanded search presentation so tabs/sidebar navigation remains available.

## Data and logos

The team/league directory is offline, with custom entries supported. Schedules still come from the user's provider EPG. No sports metadata/logo API or subscription was configured. [API-SPORTS](https://api-sports.io/) advertises a free developer plan with 100 requests per day for each API and is a candidate for a later metadata integration. App users would not need accounts. Image permissions and caching rules need to be checked for the selected assets/provider before distribution.

## Evidence and validation

Before screenshots in this directory show the Guide opening state and the old general sports preferences form. The opening capture includes initial loading and is not a steady-state performance measurement.

Local core tests: 45 passing tests, including whole-word/alias sports matching, conservative event alternatives, guide mapping, full-catalog bounds, and personal-store behavior.

Physical iPad application tests: 14 passing tests. On the saved 57,033-channel catalog, sports matching returned eight live programs, four upcoming programs, and 11 channels without listings in 0.153 seconds. Background Guide query took 0.131 seconds; largest measured main-thread heartbeat gap was 62 ms during catalog, Guide, organizer, and sports work. These are query/responsiveness measurements, not end-to-end tap timings.

Screen checks and final device playback results are recorded in verification.txt after completion. Screenshots of controlled sports examples are labeled sample data; saved Guide screenshots use the actual provider catalog. This was a targeted design/accessibility-label review, not a full VoiceOver, Dynamic Type, or accessibility audit.

## Screenshots

| Screen | iPad | iPhone |
| --- | --- | --- |
| Saved Guide | [Guide](after-guide-ipad.png) | [Guide](after-guide-iphone.png) |
| Plain X and actual sample video | [Player](after-player-ipad.png) | [Player](after-player-iphone.png) |
| Sports collections and favorites | [Library](after-library-ipad.png) | [Library](after-library-iphone.png) |
| Saved team programs | [Team](after-team-ipad.png) | Covered by device UI checks |
| League without listings | [League](after-league-ipad.png) | Covered by device UI checks |

All requested device workflows passed. See [verification](verification.txt) for the exact tests, timings, corrections, and limits.
