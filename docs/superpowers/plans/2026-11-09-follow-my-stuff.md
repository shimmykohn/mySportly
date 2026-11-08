# Follow Model and My Stuff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** One clear model: Follow a team, Add a league, Favorite a channel. My Stuff lists exactly those. Organizer tools and diagnostics screens are removed.

**Architecture:** The existing `sports.library.<id>` entries already hold saved teams and leagues, and `channel.<id>.favorite` holds favorites, so the model keeps those keys: a saved team *is* followed, a saved league *is* added. A one-time, non-destructive migration (pure function in `SportlyCore`) turns stars and saved channel bookmarks into the new model. Game-start alerts for followed teams are planned by a pure function and scheduled with `UNUserNotificationCenter`. `MyStuffView`, `TeamPage`, `LeaguePage` and `FollowPicker` replace the Library screens.

**Spec:** `docs/superpowers/specs/2026-11-08-app-redesign-design.md`, sub-project 4.

## Global Constraints

- Same build, test and simulator commands as `2026-11-08-home.md`.
- Team → **Follow** / **Following**. League → **Add to My Sports** / **Added**. Channel → **Favorite** (heart). No separate saved state, no stars.
- My Stuff: one list with sections **Teams**, **Leagues**, **Channels**; swipe to remove; team or league opens its page (upcoming games on the user's lineup); a channel plays.
- Game-start notifications: opt-in per team, off by default, only for followed teams.
- Migration is one-time (`migration.followModel.v1`) and non-destructive: saved or starred teams → followed; saved leagues → added; favorite or saved channels → favorite. Categories, channel groups and custom collections are not carried over; their records stay.
- Removed screens: Organizer, channel rename/reorder/bulk edit, custom groups, guide mapping screens, Guide Status, Where Data Comes From, Channel Details. "Hide Channel" stays in channel context menus.

## Review Focus

1. **Migration running twice** (iCloud brings an older record after migration): the flag makes it a no-op; saved channels already favorite stay favorite. (Task 1)
2. **A starred team whose save was removed on another device**: the explicit `saved: false` entry wins; it is not resurrected. (Task 1)
3. **Unfollowing a team with alerts on**: its pending notifications are removed. (Task 2)
4. **Notification permission denied**: the toggle shows it is off and links to Settings; nothing crashes. (Task 3)
5. **A followed team with no games on the lineup**: its page says so in one line, not an empty screen. (Task 3)

---

### Task 1: Migration and alert planning (Core)
**Files:** Create `mySportly/Core/FollowModel.swift`; Test `CoreTests/FollowModelTests.swift`.
- `public enum FollowMigration { public static let flag = "migration.followModel.v1"; public static func updates(values: [String: Data]) -> [String: Data?] }`: empty when the flag exists. Stars always came with a save (they are keyed only by ID), so they need nothing. Legacy `preferences.teams`/`preferences.leagues` names become entries. Saved channel bookmarks (`library.item.*` with `kind == .channel`) set `channel.<ref>.favorite = true`. Always sets the flag.
- `public struct GameAlert: Hashable, Sendable { id, gameID, date, title }` and `public enum GameAlerts { static func plan(sports: HomeSportsData, notifyTeamIDs: Set<String>, now: Date) -> [GameAlert] }`: games of opted-in teams starting after `now` and within 7 days, one per game, at most 50, sorted by start; title "Away at Home".
- [ ] Tests: `explicitRemovalWins`, `legacyListsBecomeEntries`, `savedChannelBecomesFavorite`, `flagMakesItIdempotent`, `alertsOnlyForOptedInFutureGames`, `alertsDedupeAndCap`. Run (FAIL), implement, run (PASS), commit `feat: follow-model migration and game alert planning`.

### Task 2: Store and alerts
**Files:** Modify `AppStore.swift`, `LibraryStore.swift` (replace); Create `mySportly/Sports/GameAlertScheduler.swift`.
- Store: `followedTeams`, `addedLeagues` (direct `sportsLibrary` items by kind), `isFollowing(_ item:)`, `follow(_:)`, `unfollow(_:)`, `notifiesGameStart(_ team:)`, `setNotifiesGameStart(_:_:)` (key `sports.notify.<id>`; enabling requests notification authorization). Run the migration once in `load()` after personal data is available.
- `GameAlertScheduler.update(plan:channelFor:)` replaces pending requests whose identifiers start with `game.`; `userInfo["channelID"]` is the first playable feed so tapping plays through `NotificationRouting`.
- Reschedule after guide matching and whenever follows or notify flags change.
- [ ] Build; core and unit tests pass; commit `feat: follow, add and favorite on the store with game alerts`.

### Task 3: My Stuff, team and league pages, follow picker
**Files:** Create `mySportly/Features/MyStuff/MyStuffView.swift`, `TeamPage.swift`, `LeaguePage.swift`, `FollowPicker.swift`; Modify `ContentView.swift`, `HomeView.swift` (prompt opens `FollowPicker`), `ContentView.swift` `PlayableChannelRow` context menu (Favorite/Remove Favorite, Hide Channel only).
- `MyStuffView`: sections Teams (logo, name, league; swipe **Unfollow**), Leagues (swipe **Remove**), Channels (favorites; swipe **Remove Favorite**; tap plays). Toolbar `+` opens `FollowPicker`. Empty: `ContentUnavailableView("Nothing Here Yet", systemImage: "star")` with **Follow Teams**.
- `TeamPage`: large logo, league, **Follow/Following** button, **Notify When Games Start** toggle when following, upcoming games on the lineup (`HomeGameCard` rows) or "No games on your channels this week."
- `LeaguePage`: **Add to My Sports/Added**, upcoming games, its teams with Follow buttons.
- `FollowPicker`: segmented Teams/Leagues, search, Follow/Add buttons.
- Accessibility identifiers: `my-stuff-team-<name>`, `my-stuff-league-<name>`, `my-stuff-channel-<id>`, `follow-<name>`, `team-notify`.
- [ ] Build; screenshot My Stuff, a team page and the picker; commit `feat: My Stuff with team and league pages`.

### Task 4: Remove organizer tools and diagnostics
Delete `Features/Organizer/`, `Features/Channels/ChannelManagement.swift`, `CategoryChannelsView.swift`, `TaxonomyChannelsView.swift`, `Features/Guide/GuideStatusView.swift`, `Features/Settings/DataOriginView.swift`, `Features/Library/` (replaced), and their store-only helpers when unused. Remove UI tests for these screens; retarget `testUnifiedLibrary…` to My Stuff and the follow picker.
- [ ] Build all targets; commit `chore: remove organizer tools and diagnostics screens`.

### Task 5: Tests
`MyStuffUITests.testFollowTeamAppearsInMyStuffAndHome` (`--demo --demo-sports-api-check`: follow picker → follow Knicks → My Stuff Teams shows it → Home Your Teams shows the game → swipe Unfollow removes it) and `testFavoriteChannelAppearsAndRemoves`.
- [ ] Run on the simulator (PASS); commit `test: follow model and My Stuff`.
