# Library, refresh and App Intents acceptance — 2026-10-19

Physical iPhone 17 Pro and iPad A16, iOS/iPadOS 27.0.1. Xcode 27.1 and SDK 27.1. No simulator was used. The delivery build uses Swift optimization while retaining Debug signing and the existing development CloudKit environment.

## Product behavior

- Library has one saved-item list for channels, categories, subcategories, shared channel groups, teams, leagues and personal collections. A star prioritizes a saved item. Removing the star keeps the save.
- Saving NFL creates one Library item. Its known teams are browsable inside it; teams can be saved and starred independently. Removing the league preserves separately saved teams. Existing direct saves/favorites are retained.
- Sports remains a browsing shortcut to games and sports channels. Category paths organize broadcasts; they do not create a separate sports Library.
- Native Settings → Where Data Comes From describes provider content, the cached API-SPORTS reference snapshot, built-in recognition rules/offline aliases, and personal/Jev choices. Channel details disclose the original provider name/group and the origin of the applied classification.
- Native Automatic Refresh settings default to daily playlists and guide-only updates every six hours. Successful timestamps belong to each device's own cache. Failures retain data and have an hour retry backoff. Pull-to-refresh remains available; refresh never starts Jev. The native header spinner is retained.
- Six App Shortcuts cover playing, searching, opening saved items, saving channels, refreshing and Guide. Search and opening saved items use iOS 27 system schemas. Only saved items are indexed in the dedicated Spotlight index. The local Siri catalog contains no provider URLs or credentials.
- No optional Apple cloud, OpenAI or downloadable naming helper was activated. That decision remains for discussion.

## Real playlist and sync checks

- The iPhone received both manual Golf/Tennis corrections created on iPad. The verifier matched **2/2 exact expected mutation versions**. Both were still manual Sports/Golf and Sports/Tennis placements. The phone had 57,033 channels, no preferred pending groups and no new Jev work.
- An actual iPad **guide-only refresh** retained all **57,033 channels** and produced **224,608 guide programs**. All **21,688 saved placement records** were exactly unchanged, including their mutation versions. The playlist refresh timestamp was unchanged. No Jev run was started.
- After that refresh, iPadOS reported a pending background processing request with an earliest start six hours after the successful guide refresh. This proves scheduling acceptance, not execution at a guaranteed wall-clock time. iOS chooses when to run it.
- These checks read the authorized existing provider connection from Keychain; no credentials or stream URLs are retained here.

## Automated checks

- **87 core + 4 persistence tests passed.** They include refresh cadence/disabled schedules/backoff, guide-only replacement, backward-compatible cache decoding, stable category identity, and the prior organization/sync regression coverage.
- **15 app-state tests passed again on the optimized iPad build**, including direct league membership, independent team saves, channel unstar retaining a save, saved categories, and App Intent route handling.
- **Six distinct iPad UI flows passed**: unified Library/team saves/favorites today; iOS 27 typed Search intent handing off into native Search; native refresh settings and data origins; header-only refresh/no empty favorites; repeated Sports visits; and manual category correction followed by browsing the new category/subcategory.
- The category navigation check initially used the removed Library → Organizer entry. Its test was updated to the current Live → Organize Channels path and passed.
- Siri's actual voice-command check **did not pass**. Activation returned to Home without opening Guide; a subsequent system Siri accessibility query timed out. The app's typed App Intent handoff passing does not establish spoken Siri recognition. The voice test is opt-in with `SPORTLY_TEST_SIRI=1` in the test runner environment and requires device Siri setup. Manual spoken acceptance remains open.
- iPhone screen tests **did not run successfully** because iOS timed out enabling automation. The install and reverse iCloud check succeeded separately. The user handoff for unlocking/approving automation is still pending.

## Evidence locations

Raw local results (temporary, not committed):

- `/private/tmp/mysportly-library-refresh-core.log`
- `/private/tmp/mysportly-library-refresh-ipad.xcresult`
- `/private/tmp/mysportly-final-optimized-state-ipad.xcresult`
- `/private/tmp/mysportly-library-delivery.log` — final optimized build with help-text-only updates after the behavioral checks
- `/private/tmp/mysportly-siri-ipad.log` — header/repeated-Sports passes; first Siri failure
- `/private/tmp/mysportly-final-navigation-ipad.xcresult` — corrected Organizer pass; Siri failure
- `/private/tmp/mysportly-library-refresh-iphone.log` — automation timeout
- `/private/tmp/mysportly-reverse-sync-phone.json` — reverse correction versions
- `/private/tmp/mysportly-guide-refresh-ipad.json` — real guide refresh and queued OS request

[Unified Library](ipad-library-sample.png), [Automatic Refresh](ipad-refresh-settings.png), and [Data Origins](ipad-data-origins.png) show the isolated sample profile. Numeric provider results above come from the separate actual-catalog checks. The Siri Home Screen capture is not copied into the repository.

Playback, recording and every offline CloudKit conflict were not retested in this change.

## Delivery

The final optimized build succeeded and was installed on both physical devices. Both were launched normally with no sample/test arguments, returning them to their saved profiles. The final post-test code change only updated Settings help text to match the new Library and filter navigation. No spoken Siri or iPhone screen-test pass is claimed.
