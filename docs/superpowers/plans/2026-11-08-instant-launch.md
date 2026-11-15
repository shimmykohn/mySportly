# Instant Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home becomes interactive within about 1 s of opening the app with the saved catalog (test budget 1.5 s). The full catalog keeps preparing in the background.

**Architecture:** Measure launch phases with signposts. Shrink the saved catalog by pruning listings that have ended. Write a small encrypted *launch snapshot* (favorites, recents, and the head of the lineup, plus their next 24 h of listings) after every successful prepare. On launch, the store fills its published fields from that snapshot and drops the loading overlay. It then decodes the full catalog and runs the existing `PreparedCatalog` rebuild off the main actor. Scene-activation work (cloud status, source restore, refresh) waits on a new `catalogReady` flag instead of `loading`.

**Tech Stack:** Swift 6, SwiftUI, iOS/iPadOS 27, Swift Testing (`@Test`/`#expect`) for the `SportlyCore` package, XCTest UI tests on physical devices, CryptoKit AES-GCM, `os.signpost`.

**Spec:** `docs/superpowers/specs/2026-11-08-app-redesign-design.md` (sub-project 1, "Instant launch")

## Global Constraints

- Target iOS/iPadOS 27.0+, Xcode 27.1. The project uses file-system synchronized groups, so new files under `mySportly/` are picked up without editing `project.pbxproj`.
- Physical devices only: do not download or boot simulators.
- Core tests: `swift test --scratch-path /private/tmp/mysportly-core-build --disable-sandbox`
- Every file holding channels must be AES-GCM sealed with the existing `catalog-encryption-key`, written with `[.atomic, .completeFileProtectionUntilFirstUserAuthentication]`, inside the backup-excluded `ProviderCache` directory. Xtream stream URLs contain credentials.
- No network request and no model call before the first Home frame.
- Keep listings from now through +3 days. Drop listings whose `end` is at or before now.
- Never put real credentials in tests, fixtures, or launch arguments.
- Timing builds use `SWIFT_OPTIMIZATION_LEVEL=-O` with the existing Debug signing/iCloud configuration.

## Review Focus

1. **First launch after this update.** The saved catalog is legacy JSON with no format header, and there is no launch snapshot yet. It must still load, showing the existing spinner once, and then write a snapshot for next time. (Tasks 3, 6)
2. **Stale snapshot.** The snapshot was written days ago, so every listing in it has ended. Rows must show "No guide information", never a stale "now". (Tasks 4, 6)
3. **Source removed on another device.** iCloud deletes a source while the snapshot still holds its channels. Channels from inactive sources must not appear or play. (Task 6)
4. **Tap before the full catalog is ready.** Playing a snapshot channel works immediately. Scene activation during preparation must not start a refresh or source restore. (Task 6)
5. **Corrupt or undecryptable snapshot.** For example the Keychain key is unavailable before first unlock. Fall back to the normal full load with no error alert. (Tasks 5, 6)

---

### Task 1: Launch timeline instrumentation

**Files:**
- Create: `mySportly/Core/LaunchTimeline.swift`
- Modify: `mySportly/App/AppStore.swift:184-212` (`load()`), `mySportly/App/AppStore.swift:278-320` (`rebuild`)
- Test: `CoreTests/LaunchTimelineTests.swift`

**Interfaces:**
- Produces: `public struct LaunchTimeline: Sendable` with `public mutating func mark(_ phase: LaunchPhase, at: ContinuousClock.Instant = .now)`, `public func milliseconds(to phase: LaunchPhase) -> Int?` (from `.processStart`), and `public var summary: String` (`"phase=ms"` pairs in enum order, space separated). `public enum LaunchPhase: String, CaseIterable, Sendable { case processStart, snapshotLoaded, firstInteractive, catalogDecoded, catalogPrepared }`.
- Produces: `AppStore.launchTimeline: LaunchTimeline` (observable, `private(set)`).

- [ ] **Step 1: Write failing tests** in `CoreTests/LaunchTimelineTests.swift`. Test `marksAreRelativeToProcessStart`: mark `.processStart` at instant `t`, then `.firstInteractive` at `t + .milliseconds(850)`, and expect `milliseconds(to: .firstInteractive) == 850`. Test `unmarkedPhaseIsNil`: expect `milliseconds(to: .catalogPrepared) == nil`. Test `summaryListsMarkedPhasesInOrder`: expect `"processStart=0 firstInteractive=850"`.
- [ ] **Step 2: Run them and confirm they fail.** Run: `swift test --scratch-path /private/tmp/mysportly-core-build --disable-sandbox --filter LaunchTimelineTests`. Expected: compile failure, `LaunchTimeline` not found.
- [ ] **Step 3: Implement `LaunchTimeline`.** Store `[LaunchPhase: ContinuousClock.Instant]`. A later mark of the same phase does not overwrite the first one.
- [ ] **Step 4: Wire it into `AppStore`.** Mark `.processStart` in `init`. Wrap each phase of `load()` in `OSSignposter(subsystem: "app.iska.mysportly", category: "Launch")` intervals named `decrypt`, `decode`, `prepare`, `restore`, and mark `.catalogDecoded` after `cache.load()` and `.catalogPrepared` when `rebuild` publishes. In DEBUG, print `"[Launch] " + summary` once `.catalogPrepared` is marked.
- [ ] **Step 5: Run core tests.** Same command without the filter. Expected: PASS.
- [ ] **Step 6: Measure the baseline on the user's iPhone** with an `-O` build and the saved catalog. Record the `[Launch]` line in `docs/product/evidence/instant-launch-2026-11/baseline.md` as numbers only, with no channel names or URLs.
- [ ] **Step 7: Commit** with message `perf: instrument launch phases`.

### Task 2: Prune ended listings

**Files:**
- Modify: `mySportly/Core/Domain.swift` (`CatalogSnapshot`)
- Modify: `mySportly/App/AppStore.swift` (after `cache.load()` and before each `cache.save`)
- Test: `CoreTests/CatalogTests.swift`

**Interfaces:**
- Produces: `public mutating func pruneGuide(now: Date, horizon: TimeInterval = 3 * 86_400)` on `CatalogSnapshot`. It keeps programs where `end > now && start < now + horizon`. Channels, `guideChannels`, and refresh timestamps are untouched.

- [ ] **Step 1: Write failing tests.** `pruneDropsEndedAndFarFutureListings`: for programs ending at `now - 1`, ending exactly at `now`, live, starting at `now + 2 days`, and starting at `now + 4 days`, expect only the live and +2-day programs to remain. `pruneKeepsGuideRefreshTimestamps`: expect `guideRefreshed` to be unchanged.
- [ ] **Step 2: Run and confirm they fail** (`--filter CatalogTests`).
- [ ] **Step 3: Implement `pruneGuide`.**
- [ ] **Step 4: Call it.** In `load()` right after decode, call `catalog.pruneGuide(now: .now)`. Before each `cache.save` call (`AppStore.swift:464` and `:518`), call it on the snapshot being saved.
- [ ] **Step 5: Run core tests.** Expected: PASS.
- [ ] **Step 6: Commit** with message `perf: drop ended guide listings from the saved catalog`.

### Task 3: Versioned catalog codec

**Files:**
- Create: `mySportly/Core/CatalogCodec.swift`
- Modify: `mySportly/Persistence/SecureStorage.swift:69-80` (`CatalogCache.load/save`)
- Test: `CoreTests/CatalogCodecTests.swift`

**Interfaces:**
- Produces: `public enum CatalogCodec` with `public static func encode<T: Encodable>(_ value: T) throws -> Data` and `public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T`.
- Encoded data starts with the 4-byte magic `SPC1` followed by the chosen format's bytes. Data without the magic is decoded as legacy JSON.

- [ ] **Step 1: Write failing tests.** `roundTripsSnapshot`: encode a `CatalogSnapshot` with 3 channels and 5 programs, decode it, and expect equal channel IDs, program IDs, and `guideRefreshed`. `decodesLegacyJSON`: `JSONEncoder().encode(snapshot)` passed through `CatalogCodec.decode` must decode. `encodedDataHasMagic`: expect the first 4 bytes to equal `Data("SPC1".utf8)`.
- [ ] **Step 2: Write the benchmark test** `benchmarkFormats`, tagged `.timeLimit(.minutes(3))`. Use the 57,033-channel / 220,500-program synthetic workload from `CatalogQueryTests.fullSizedCatalogQueriesStayBoundedAndSearchEveryChannel`. Time decoding with `JSONDecoder` and with `PropertyListDecoder` (binary) and print `[CatalogCodec] json_decode_s=… plist_decode_s=… json_bytes=… plist_bytes=…`. No assertion on timing.
- [ ] **Step 3: Run and confirm they fail** (`--filter CatalogCodecTests`).
- [ ] **Step 4: Run the benchmark, then implement.** Use binary property lists after `SPC1` only if the benchmark shows plist decode at least 30% faster than JSON. Otherwise use JSON after `SPC1`. Record the numbers and the choice in a doc comment on `CatalogCodec`.
- [ ] **Step 5: Use `CatalogCodec` in `CatalogCache.load/save`.** Replace `JSONDecoder`/`JSONEncoder` there. The legacy path covers existing files.
- [ ] **Step 6: Run core tests.** Expected: PASS.
- [ ] **Step 7: Commit** with message `perf: versioned catalog codec with legacy JSON read`.

### Task 4: Launch snapshot model

**Files:**
- Create: `mySportly/Core/LaunchSnapshot.swift`
- Test: `CoreTests/LaunchSnapshotTests.swift`

**Interfaces:**
- Consumes: `PreparedCatalog` (`directory.lineup`, `directory.favorites`, `channelsByID`, `guide`, `guideMappings.matches`).
- Produces:
  ```swift
  public struct LaunchSnapshot: Codable, Sendable {
      public static let channelLimit = 300
      public static let window: TimeInterval = 24 * 3600
      public var createdAt: Date
      public var channels: [Channel]            // favorites, then recents, then lineup head; unique; ≤ channelLimit
      public var favoriteIDs: [String]
      public var lineupIDs: [String]            // ordered, subset of channels
      public var guide: [String: [GuideProgram]] // key "sourceUUID|guideID", only keys used by `channels`
      public var guideMatches: [String: GuideMatch]
      public init(prepared: PreparedCatalog, recentIDs: [String], now: Date)
      public func active(sources: Set<UUID>, now: Date) -> LaunchSnapshot // drops inactive-source channels and listings with end <= now
  }
  ```
  `GuideMatch` gains `Codable` conformance in `GuideMappingResolver.swift`.

- [ ] **Step 1: Write failing tests** using a small `PreparedCatalog` built from 400 channels and 3 favorites:
  - `favoritesComeFirstAndLimitHolds`: `channels.count == 300` and `Array(channels.prefix(3).map(\.id)) == favoriteIDs`.
  - `recentsFollowFavorites`: a recent ID that isn't a favorite appears at index 3.
  - `guideOnlyCoversSnapshotChannelsWithinWindow`: no key outside the snapshot channels' keys, and no program with `start >= now + 24h` or `end <= now`.
  - `activeDropsRemovedSourcesAndEndedListings`: `active(sources: [], now:)` yields empty `channels`. `active` with `now + 25h` yields an empty `guide`.
  - `roundTripsThroughCatalogCodec`.
- [ ] **Step 2: Run and confirm they fail** (`--filter LaunchSnapshotTests`).
- [ ] **Step 3: Implement `LaunchSnapshot`** and add `Codable` to `GuideMatch`. Resolve each channel's guide key the way `AppStore.guideID(for:)` does (manual mapping is applied by the store at read time, so store the raw `guideMatches` entry, not a rewritten channel).
- [ ] **Step 4: Run core tests.** Expected: PASS.
- [ ] **Step 5: Commit** with message `feat: launch snapshot model`.

### Task 5: Encrypted launch snapshot store

**Files:**
- Modify: `mySportly/Persistence/SecureStorage.swift` (`CatalogCache`)
- Modify: `mySportly/App/AppStore.swift` (`rebuild` publish block, source removal at `:518`)

**Interfaces:**
- Consumes: `LaunchSnapshot`, `CatalogCodec`.
- Produces: on `CatalogCache`: `func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) throws`, `func loadLaunchSnapshot() -> LaunchSnapshot?` (returns nil on missing, undecryptable, or undecodable data and never throws), and `func removeLaunchSnapshot()`. File name: `launch.sealed`.

- [ ] **Step 1: Implement the three methods,** sealing data the same way `save(_:)` does.
- [ ] **Step 2: Write the snapshot after each publish.** In `rebuild`'s success block, after `self.queryIndex = prepared.query`, build `LaunchSnapshot(prepared:recentIDs:now:)` inside `catalogWork`. Pass recent IDs from the same `history.` keys as `recent`. Then save it through the cache, debounced: cancel any pending save task and wait 2 s.
- [ ] **Step 3: Remove the snapshot** when the last source is removed (`sources.isEmpty` after removal at `:518`).
- [ ] **Step 4: Build the app for a device** (`xcodebuild build -project mySportly.xcodeproj -scheme mySportly -destination 'generic/platform=iOS'`). Expected: `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit** with message `feat: persist encrypted launch snapshot`.

### Task 6: Launch from the snapshot

**Files:**
- Modify: `mySportly/App/AppStore.swift` (`load()`, published fields, `rebuild`, search entry point)
- Modify: `mySportly/mySportlyApp.swift` (scene-phase `.active` block, remote-change handler)
- Modify: `mySportly/App/ContentView.swift:24` (loading overlay)
- Modify: `mySportly/Features/Live/LiveView.swift` (root accessibility value)

**Interfaces:**
- Consumes: `CatalogCache.loadLaunchSnapshot()`, `LaunchSnapshot.active(sources:now:)`, `LaunchTimeline`.
- Produces: `AppStore.catalogReady: Bool` (`private(set)`, false until the first full `rebuild` publishes). `AppStore.loading` now means only "nothing to show yet".

- [ ] **Step 1: Reorder `load()`:**
  1. Read `cache.loadLaunchSnapshot()`, then call `.active(sources: Set(sources.map(\.id)), now: .now)`. If it has channels, set `channels`, `lineup`, `favorites`, `channelIndex`, `guideIndex`, and `guideMatches` from it. Set `loading = false`, set `showSetup` from `setup.complete`, and mark `.snapshotLoaded` and `.firstInteractive`.
  2. Then, in order: `cache.load()` and prune, `rebuild(force: true)`, `waitForCatalog()`, set `catalogReady = true`. If no snapshot was used, set `loading = false` and mark `.firstInteractive` here instead.
  3. Only after `catalogReady`: `reminders.reload()`, `recorder.reload()`, `personal.refreshCloudStatus()`, `organization.restore()`, `restoreMissingSources()`, route consumption, and `refreshDueSources()`.
- [ ] **Step 2: Guard scene activation.** In `mySportlyApp.swift`, replace `guard !store.loading` with `guard store.catalogReady`. Replace the `!store.loading` remote-change check with `store.catalogReady`.
- [ ] **Step 3: Search before the catalog is ready.** While `queryIndex == nil`, the search entry point returns snapshot channels whose `name(channel)` contains every keyword, matched case- and diacritic-insensitively, in lineup order.
- [ ] **Step 4: Expose launch time to UI tests.** On the Live root, set `.accessibilityIdentifier("home-root")` and `.accessibilityValue("launch-ms=\(store.launchTimeline.milliseconds(to: .firstInteractive) ?? -1)")`.
- [ ] **Step 5: Build for a device.** Expected: `BUILD SUCCEEDED`. Run core tests. Expected: PASS.
- [ ] **Step 6: Manual check on the user's iPhone** (`-O` build). Open the app twice. On the first open, after the update, expect the spinner once. On the second open, Home should appear immediately, and the `[Launch]` line should show `firstInteractive` under 1500. Then play a favorite before `catalogPrepared` and confirm it plays. Record the numbers in the evidence file.
- [ ] **Step 7: Commit** with message `perf: show Home from the launch snapshot before the full catalog`.

### Task 7: Launch budget device test

**Files:**
- Create: `mySportlyUITests/LaunchBudgetUITests.swift`

**Interfaces:**
- Consumes: the `home-root` element and its `launch-ms=` accessibility value from Task 6.

- [ ] **Step 1: Write `testSavedCatalogHomeIsInteractiveWithinBudget`.** Launch the normal app with no `--demo`, which reads the saved catalog and makes no provider request before the first frame. Terminate, then launch again so a snapshot exists. Wait up to 5 s for `home-root`, parse `launch-ms=`, and `XCTAssertLessThanOrEqual(ms, 1500)` and `XCTAssertGreaterThan(ms, 0)`.
- [ ] **Step 2: Run on the iPhone.** Run: `xcodebuild test -project mySportly.xcodeproj -scheme mySportly -destination 'platform=iOS,name=<device name>' -only-testing:mySportlyUITests/LaunchBudgetUITests SWIFT_OPTIMIZATION_LEVEL=-O`. Expected: `** TEST SUCCEEDED **`. Repeat on the iPad.
- [ ] **Step 3: Record the results** (milliseconds, device, build settings) in the evidence file and update the launch paragraph in `README.md`.
- [ ] **Step 4: Commit** with message `test: device launch budget for saved catalog`.

### Task 8: Persisted prepared stages (decision gate)

The spec asks for persisted indexes so the full catalog can skip its rebuild. Decoding a large `Codable` graph can be slower than rebuilding it, so this task builds the cache only if it pays off.

**Files:**
- Test: `CoreTests/PreparedCatalogBenchmarkTests.swift`
- Create, only if the gate passes: `mySportly/Core/PreparedStagesCache.swift`

- [ ] **Step 1: Write the benchmark** `benchmarkPreparedStages` on the synthetic workload. Time each `PreparedCatalog.init` stage (directory, guide grouping, `GuideMappingResolver`, `PlaybackAlternatives`, `CatalogQueryIndex`). Also time `CatalogCodec` encode and decode of `ChannelDirectory.metadata` (`[String: ChannelMetadata]`, adding `Codable`) and `GuideMappingResolver.matches`. Print all timings.
- [ ] **Step 2: Apply the gate.** Use the device `catalogDecoded→catalogPrepared` time from Task 6 together with the benchmark. If device prepare is under 5 s, or decoding the two maps is not at least 2× faster than computing them, stop here. Record "not adopted" with the numbers in the evidence file, commit the benchmark, and finish.
- [ ] **Step 3 (gate passed): Implement `PreparedStagesCache`** with `struct PreparedStages: Codable { var fingerprint: String; var metadata: [String: ChannelMetadata]; var guideMatches: [String: GuideMatch] }`. The fingerprint is a SHA-256 of the channel IDs, `guideRefreshed`, `personal.catalogRevision`, and a `rulesVersion` constant. Pass the cached maps into `ChannelDirectory`, `GuideMappingResolver`, and `CatalogQueryIndex`, which already accept `metadata:`/`guideMatches:`. Test that a fingerprint mismatch recomputes, and that a match yields identical `lineup` IDs to a fresh build.
- [ ] **Step 4: Run core tests and the Task 7 device test.** Expected: PASS. Then commit with message `perf: reuse persisted catalog stages`.
