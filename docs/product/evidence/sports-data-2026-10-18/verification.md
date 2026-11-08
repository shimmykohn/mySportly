# Sports data and native browsing verification

October 18, 2026. Physical iPhone 17 Pro and iPad A16, iOS/iPadOS 27.0.1, built with Xcode 27.1. Optimized Debug build retains development CloudKit configuration. No simulator was used.

## Data and local tests

- API-SPORTS account setup succeeded. Authenticated current-season requests failed with the free-plan season restriction; the user selected TV-guide games plus available reference names/logos.
- Export verification matched the bundled 173 public teams and six leagues. The resource contains zero historical games, and no API key is shipped. The temporary key file was removed.
- 61 Swift core tests and four persistence tests passed. Coverage includes opponent/time matching, ambiguous/doubleheader rejection, guide offsets, stale/incorrect dates, sports classification, lineup/manual overrides, interest ordering and unknown provider-prefix groups.
- `git diff --check` passed.

## Real device data and playback

- Both devices decoded a real API-SPORTS logo, then decoded the saved disk copy in a new cache instance with networking unavailable.
- The matched-provider video check passed on iPhone (2.25 seconds) and iPad (3.47 seconds). These checks used a visible AVPlayerLayer, advancing playback and one provider connection; playback stopped afterward. They do not establish compatibility of every provider stream or codec.
- Final iPhone matching check: 57,033 saved channels, 53 EPG game groups, 303 feed links; 1.884 seconds off the main actor and longest observed main-actor heartbeat gap 21.58 ms. Sport grouping took 10.43 ms, placing 1,513 visible feeds into 11 groups, including 31 Golf and 80 Tennis feeds.
- Earlier iPad check: 57,033 saved channels, 69 EPG game groups, 378 feed links; 2.607 seconds off the main actor and heartbeat gap 21.61 ms. Sport grouping took 12.76 ms, with 1,522 visible feeds in 11 groups (31 Golf, 80 Tennis). Different cached guides account for different game/feed counts. These measurements are individual observations, not frame-rate guarantees.

## Native UI checks

- iPhone passed changing interests, compact/expanded categories, the toolbar lineup filter, removal of the Live heading, automatic NFL/NCAAF/new-label folders, channel search, Recent swipe removal, and the native player flow (first video frame, feed switching, 720p preference, close, and team/league game pages).
- Real cached-guide game pages and logo display passed on both devices earlier in this pass. Library membership and independent Favorites passed on iPad.
- The iPhone Browse by Sport check revealed that a parent accessibility identifier shadowed the child row identifiers. Video evidence showed the rows expanded correctly. After removing the identifier, the final iPhone group/navigation/search check passed (27.142 s), as did the real saved-guide game-page check (19.111 s). The final build was installed and reopened with the normal saved catalog. These are whole test durations.
- iPad initially timed out before starting UI tests while enabling automation. After the user enabled UI Automation, all three final screen checks passed: interests/filter menu/discovered league folders (27.900 s), sport groups/search (26.313 s), and native player/feed/quality/team/league navigation (40.494 s). These are whole test durations. The app was reopened with its normal saved catalog afterward.

Sample UI checks use a clearly labeled in-memory catalog and Apple's public HLS video. Real-provider checks and counts above are separate. iCloud sync, recording and sustained reconnect behavior were not revalidated. The performance test creates an additional AppStore in its host and logs a duplicate CloudKit-handler warning; this is not a successful iCloud sync check.

## Reviewed screenshots

- [Interested Sports on iPhone (sample)](home-sports-iphone-sample.png)
- [Compact categories on iPad (sample)](home-categories-ipad-sample.png)
- [Discovered league folders on iPhone (sample)](league-folders-iphone-sample.png)
- [Native player and quality controls on iPad (sample)](player-ipad-sample.png)
- [Real guide game and API-SPORTS logos on iPhone](game-iphone.png)
