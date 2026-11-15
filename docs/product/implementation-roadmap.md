# mySportly implementation and acceptance

Status: Native V1 implementation is present. Device/provider acceptance remains in progress. See [build evidence](build-progress.md) for results; unchecked acceptance items below are not silently deferred features.

## Implemented in the project

- [x] Default SwiftUI navigation and all agreed feature screens, including adaptive iPad tabs/sidebar.
- [x] Source-scoped catalog and guide models; Xtream/M3U imports; XMLTV parsing; secure credentials and encrypted local caches.
- [x] Local SwiftData personal records with per-field mutation history, tombstones, explicit overrides, and CloudKit-compatible schema.
- [x] Favorites, history controls, language/region/audio/translation preferences, groups, bulk editing, hide/reorder/rename, variant selection and separation.
- [x] Local country/language/category metadata rules, manual-override precedence, shared My Lineup/All Channels/Unclassified scopes, and explicit treatment of unknown languages.
- [x] Metadata candidates, Apple model review, uncertainty handling, cached incremental decisions, preview/apply, provenance-aware undo, and manual-override precedence.
- [x] Guide list/timeline, Now/Tonight/date navigation, mapping/time corrections, independent guide freshness, current-program clock, For You explanations, Sports, and translation.
- [x] Saved EPG coverage diagnostics and date-aware Only Channels with Listings filtering; explicit explanation of automatic Xtream EPG and optional replacement XMLTV.
- [x] Keyword and Apple-interpreted search against actual catalog/guide candidates; lineup preview before group creation.
- [x] Native AVKit player, compact player, channel switching, reconnect/recovery, iPad multiview, supported Xtream catch-up, foreground HLS recording, and local recording library/playback.
- [x] Local notification reminders with edit/cancel and permission/error states.
- [x] App Intents/Shortcuts, widget extension, app-group snapshot, and queued cold-launch routing.
- [x] Optional TypeSafe/Jev and OpenAI service boundary, metadata whitelist, device registration, expiring install tokens, strict output validation, and persisted usage limits. Deployment is still a separate dependency.
- [x] Apple PCC availability/entitlement gate. It remains disabled until configured and verified.
- [x] Core, persistence, service, app-state, and UI test sources. Executed results are tracked separately below.

## Executed local verification

- [x] 19 core tests covering M3U identity and import behavior, XMLTV time handling, conservative variant grouping, output validation, HLS support, guide freshness, tombstone conflict resolution, undo provenance, source refresh guarding, and consent revocation.
- [x] 3 tests using the actual SwiftData implementation: saved values/tombstones, mutation provenance, and local sync preference persistence.
- [x] 6 mocked intelligence-service tests covering metadata restrictions, batch bounds, output validation, install-token expiry/tampering, persisted budgets, and the TypeSafe endpoint contract.
- [x] Generic iOS build-for-testing compiled the app, widget extension, and app/UI test targets. Subsequent device build results are in the evidence log.
- [x] Physical iPhone: five app-state, two native UI, and four real integration tests passed; five screen captures were inspected. Further device verification is recorded in the evidence log.
- [x] Physical iPhone: private CloudKit container access, actual public HLS video playback, and temporary HLS recording/replay passed after correcting audio-session configuration.
- [x] Physical iPad: five app-state and three real integration tests passed; three native UI tests passed across targeted runs, including timeline and two-stream multiview/audio selection. Apple model test skipped on ineligible A16 hardware.
- [x] Real iCloud group round trip: iPhone creation reached iPad; iPad deletion reached iPhone. Temporary group removed.

## Physical-device acceptance still required

Use physical iPhone/iPad devices only, per the user’s instruction. Do not download, boot, or use simulators for this task.

- [x] Run the initial app-state/UI tests and inspect native screens on iPhone.
- [x] Verify the guide ranking and bounded Apple model correction on iPhone.
- [x] Run the native UI tests on physical iPad.
- [x] Connect the user’s provider inside the app: 57,033 channels and 220,543 guide listings imported; the source and catalog survive reopening on the iPhone. Large guide downloads and native Guide rendering were corrected against this catalog.
- [x] Verify saved-catalog reopening, foreground return, actual source refresh, and native staged download progress on physical iPad.
- [x] Measure and optimize Sports/Search with the saved 57,033-channel catalog on physical iPhone and iPad; verify Live recommendations, broad result counts, latest-query behavior, and manual-override/index invalidation regressions. See the evidence log for before/after timings and measurement limits.
- [x] Move catalog rebuilds, Guide ranking, Organizer preparation, and widget snapshots away from the UI thread; verify navigation and main-actor responsiveness with the real catalog on both devices.
- [x] Use a native top search field on the dedicated Search screen and other searchable screens; inspect native soft scroll-edge headers on iPhone and iPad.
- [x] Verify actual first-frame rendering of one saved provider channel on both devices, sequentially within the one-stream limit.
- [ ] Prove representative provider playback, alternate feeds, codec/container support, and media error behavior.
- [ ] Exercise organizer quality and performance on a representative messy catalog, including ambiguous languages, regions, time-shifted feeds, manual corrections, apply/undo, and re-import.
- [ ] Verify actual EPG, reminder delivery, language/audio/caption behavior, and program search results.
- [ ] Prove PiP, AirPlay, system media controls, reconnection, and iPad multiview with the provider’s actual limits.
- [ ] Record and replay a supported stream; verify background interruption, partial recordings, low storage, connection exhaustion, and catch-up behavior.
- [x] Provision the CloudKit container/App Group and verify a real private-container request.
- [x] Prove two-device group creation and deletion through the normal app UI.
- [x] Restore the real source and all 57,033 channels on iPad using its synced configuration and iCloud Keychain connection, without entering credentials again.
- [ ] Prove personal sync across two devices with offline edits, deletion, and conflicting changes.
- [ ] Verify Apple Intelligence and Translation on eligible hardware. Configure the optional cloud service and budget before real TypeSafe/OpenAI requests; verify PCC separately if its entitlement is granted.
- [ ] Inspect widgets/Shortcuts, Dynamic Type, VoiceOver, light/dark appearance, accessibility settings, and resized iPad layouts.

## Inputs for the remaining acceptance work

Provider credentials should be entered in the app, never copied into project files or test logs. Physical-device signing uses the selected Apple development team. A second iPad/iPhone signed into the same Apple Account is needed for sync proof. Cloud model access requires server-side credentials and an explicit spend/usage decision; no paid requests have been made during implementation.
