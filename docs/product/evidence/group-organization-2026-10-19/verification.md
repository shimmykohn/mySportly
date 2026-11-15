# Group organization verification — October 19, 2026

Build: Xcode 27.1, iOS SDK 27.1, deployment target iOS 27.0; optimized Debug with `SWIFT_OPTIMIZATION_LEVEL=-O`. Physical iPad A16 and iPhone 17 Pro only; no simulator.

## Local checks

- 75 core tests in 13 suites passed; 4 persistence tests in one suite passed.
- Coverage includes stable group identity through reloads, numbered-family shrinkage, region/language separation, changed context, manual precedence, dynamic taxonomy, metadata sanitization, staged choices through four levels, None/Here routing and invalid-response rejection.
- `git diff --check` passed. No supplied API key was added to the repository.

## Physical iPad

- Six UI flows passed: empty Favorites Today and refresh controls; Organizer correction and a newly created category path; repeated Sports visits; unified Library and Favorites Today; Interests/filter/discovered league groups; Golf/Tennis grouping and search.
- Three application-state checks passed: both cached Sports scopes and invalidation; the saved catalog; persistence of group corrections through rebuild and the empty Favorites state.
- Saved catalog: 57,033 channels. All Sports preparation 0.560759208 seconds; My Sports 0.497291042 seconds. Twenty repeat requests in each scope did not trigger another computation. These are data-query measurements, not frame-rendering timings.
- Real official Jev choice request passed using the per-device Keychain key.
- Real staged pipeline passed on three public sample groups: one classified and two left in review. Completed results persisted in the isolated test store, and a second run skipped unchanged groups.
- After the final fourth-level traversal change, the app rebuilt and the real staged pipeline passed again.
- The final app was reopened with its normal saved playlist. UI fixtures use an isolated sample profile; they do not imply real-provider playback acceptance.

Screens reviewed: [Group path](group-path-ipad-sample.png), [Sports](sports-ipad-sample.png), [refresh](refresh-ipad-sample.png), [league groups](league-groups-ipad-sample.png).

## Physical iPhone

- Final optimized app installation succeeded.
- After the user unlocked the device, all **11 selected checks passed**: six native UI flows, three grouping/cache application-state checks, and two real Jev integration checks. The native UI coverage matches the six iPad flows listed above.
- Saved catalog: 57,033 channels. All Sports preparation 0.400375084 seconds; My Sports 0.3655795 seconds. Twenty repeat requests per scope reused their prepared result without another computation. These are data-query measurements, not frame-rendering timings.
- The one-use setup credential was imported into Keychain, and the official Jev choice request returned a valid Sports choice. The real staged pipeline processed three public sample groups: two classified and one left in review. Its second run skipped unchanged groups. The Mac's temporary key file remains deleted.
- Reviewed native portrait layouts and reopened the final app with the normal saved playlist. No app-code change or rebuild was necessary for this retry.

Screens reviewed: [Group path](group-path-iphone-sample.png), [Sports](sports-iphone-sample.png), [league groups](league-groups-iphone-sample.png). These images use the isolated sample profile.

## Limits

- Apple PCC is disabled pending its account entitlement; no PCC naming call is claimed.
- Downloadable decision-model support is an interface, not an installed model.
- No live-provider stream, recording, broad codec coverage or cross-device iCloud round trip was retested in this pass.
- Raw local test bundles: `/private/tmp/mysportly-groups-ipad-01.xcresult`, `/private/tmp/mysportly-groups-ipad-02.xcresult`, `/private/tmp/mysportly-groups-ipad-final.xcresult`, `/private/tmp/mysportly-groups-iphone-final.xcresult`. These are local diagnostics, not public artifacts.
