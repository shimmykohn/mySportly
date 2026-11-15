# Remove Non-Goal Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Delete the features the redesign spec lists as non-goals, outright, so later sub-projects build on less code.

**Architecture:** Pure removal. Each task deletes one feature's files, its store members, its UI entry points and its tests, then builds. No stored personal data is deleted; unused keys stay in place.

**Spec:** `docs/superpowers/specs/2026-11-08-app-redesign-design.md`, "Non-goals" and "Approach" ("Delete the removed features outright instead of keeping them working").

## Global Constraints

- Same build, test and simulator commands as `2026-11-08-home.md`.
- Removed: recording, catch-up, Multiview, Siri/App Intents/Shortcuts, widgets, local reminders, spoiler preferences, guide-description translation.
- Never delete personal records or the encrypted catalog; leave orphaned preference keys untouched.
- The widget extension target is removed from `project.pbxproj` by deleting exactly its target, build phases, product reference, embed phase, target dependency and file references; `xcodebuild -list` must then show only `mySportly`, `mySportlyTests` and `mySportlyUITests`.
- Source refresh scheduling (`SourceRefreshCoordinator`, background refresh) stays.

## Review Focus

1. **A recording in progress from the previous build** has a local file and a `recording.*` channel in history: launch must not crash and history must skip unknown channels. (Task 1)
2. **Notification taps routed through `NotificationRouting`** for reminders: removing reminders must keep source-refresh notification routing (if any) working. (Task 3)
3. **Deep links `mysportly://library` and `refresh`** from old shortcuts: unknown routes are ignored without an alert. (Task 4)
4. **Catch-up URLs in `ProviderClient`**: live playback URLs are byte-identical after removing catch-up parameters. (Task 2)
5. **The app still builds for iPad**, where Multiview had the only "Open Multiview" entry. (Task 2)

---

### Task 1: Recording
Delete `mySportly/Recordings/`, `RecordingsView`, the store's `recorder` and `startRecording`, recording rows in `LibraryView`, recording connection accounting in `play`, `recording.*` channel handling. Build, run core and unit tests, commit `chore: remove recording`.

### Task 2: Multiview and catch-up
Delete `Features/Multiview/`, `showMultiview`, `multiviewCounts` (connection accounting keeps only the playing stream), catch-up (`archiveDays` UI, program-based playback URLs in `ProviderClient.playbackURL(_:secrets:program:)` keep the `program` parameter only if live uses it; otherwise remove it and its tests). Build; commit `chore: remove multiview and catch-up`.

### Task 3: Reminders, spoilers, translation
Delete `mySportly/Reminders/`, `RemindersView`, reminder buttons in Guide program details, spoiler preference reads, guide-description translation (`guideLanguage`, translation UI). Build; commit `chore: remove reminders, spoiler settings and translation`.

### Task 4: App Intents, Shortcuts and widgets
Delete `Integrations/ChannelIntents.swift`, `IntentCatalogRepository.swift`, `WidgetBridge.swift`, `appEntityIdentifier` uses, `updateIntentCatalog`, `updateWidgetSnapshot`, the `mySportlyWidgets/` folder and its target (see Global Constraints), intent-only routes, and intent tests (`LibraryRefreshIntentUITests` intent cases, unit tests). Keep URL routing for `guide` and `search` only if a remaining feature uses it; otherwise remove `AppRouteInbox`. Build all targets; commit `chore: remove App Intents, Shortcuts and widgets`.
