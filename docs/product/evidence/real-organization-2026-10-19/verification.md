# Actual playlist organization — October 19, 2026

Xcode 27.1, iOS SDK 27.1, deployment target iOS/iPadOS 27.0. Optimized Debug on physical devices only. Full provider reports remain in temporary diagnostic storage; this file retains aggregate counts and bounded channel-name examples, with no source credentials, media URLs, keys, or viewing history.

## Actual Jev run and audience

- The saved source contains 57,033 playable entries. Before refreshing, these formed 39,838 shared-name groups; the preferred US/English audience, with the user's Include Unknown Languages setting, contained 7,797 groups.
- The first audit included other regions. That run was stopped when the user clarified the scope. The engine now always uses the preferred region/language audience, independently of the browser's All Channels filter. Known other languages and other regions are excluded; region-matching entries with absent language tags remain eligible only because the user's Unknown Languages setting is on.
- All preferred groups were processed. The total 21,686 current-policy saved decisions includes retained work from the earlier wider audit; it is not a count of US-only groups.
- After the actual refresh, the preferred audience contained 7,796 groups. All are processed. On the iPad, after the two obvious Golf/Tennis review corrections, 3,828 are classified, 2,912 need review, and 1,056 need a name. These are workflow states, not measured accuracy scores. Uncertain results are retained but are not applied as confident classifications.

## Refresh and sync acceptance

- An actual provider refresh completed, advanced the source refresh timestamp, and retained all 21,688 saved placement records byte-for-byte at the decoded value and mutation-version level. Of these, 21,686 use the current decision policy; two older records are retained separately.
- The refreshed catalog still contains 57,033 entries, now in 39,840 groups. There were six new groups, four removed groups, and four changed fingerprints among retained groups. Only one preferred-lineup group was eligible for another decision.
- A subsequent explicit Jev run changed exactly one saved result, the US `NEXT` group with changed context. Preferred pending groups returned to zero. Refresh itself made no model requests.
- The iPad received all **21,686 of 21,686** expected current-policy decisions through private CloudKit. Both mutation versions and complete decoded placement values matched the iPhone report. Only expected identifiers/versions were supplied to the verifier; placement payloads were not copied to the iPad.
- Clear review corrections were saved on the iPad for the 20-feed Golf family and 50-feed Tennis family. Both now have manual Sports/Golf or Sports/Tennis placements. The iPhone became unavailable before their reverse-direction check; the user explicitly requested iPad-only testing for the remainder. Do not claim this final reverse check passed.

## Bounded grouping examples

| Shared group | Feeds | Saved path | Result |
| --- | ---: | --- | --- |
| US CNN | 2 | News | Jev classified |
| US FOX NEWS | 4 | News | Jev classified |
| US MSNBC | 1 | News | Jev classified |
| US HBO | 1 | Movies | Jev classified |
| US HISTORY | 1 | Documentary | Jev classified |
| US NICKELODEON | 1 | Kids | Jev classified |
| US BOBS BURGERS | 1 | Entertainment | Jev classified |
| NFL | 17 | Sports / American Football / NFL | Jev classified |
| NBA | 30 | Sports / Basketball / NBA | Jev classified |
| Golf | 20 | Sports / Golf | Reviewed correction |
| Tennis | 50 | Sports / Tennis | Reviewed correction |

Tennis had an over-specific Tennis Channel suggestion with low confidence. It remained in review rather than being applied. This illustrates why saved review states and manual corrections are part of the workflow.

## Native workflow and background processing

- Settings → AI is a dedicated native Form with Your Categories, audience, connection, progress, review, and Apple capability status. New profiles choose their own categories; optional suggestions are unselected. Existing choices and saved placements survive editing the list.
- Live uses one native spinner in the title position inside the existing soft header. Opening, actual iCloud activity, playlist refresh/import, Jev, and feed preparation can activate it. No progress strip, helper sentence, extra details panel, or empty/loading Favorites Today section appears there.
- Detailed progress and Pause/Resume remain on the AI page. The queue contains opaque group IDs; decisions are saved before each batch checkpoint. Restoring an interrupted queue requires explicit Resume. The completed decisions sync; the work queue is local to its starting device.
- Apple's real continued-processing task and system Live Activity ran successfully on the iPad in the earlier progress check. The sample work advanced while the app was on Home, then Pause/Resume retained the count. This tests actual OS background execution with clearly labeled sample work, not a promise of indefinite or force-quit execution.

## Checks and limitations

- 82 core tests and 4 persistence tests passed in `/private/tmp/mysportly-final-core.log`.
- Core coverage includes reusable review decisions, stable slot families, context changes, edition separation, manual precedence, bounded structured requests, invalid responses, and durable queue serialization/checkpoints.
- The broader app-state suite exposed three stale assertions expecting leagues not to include their teams. Those assertions were updated to verify the requested inherited membership and separate favorites behavior.
- All 13 application-state checks passed on the physical iPad, including the preferred audience remaining separate from All Channels and league membership remaining separate from favorites. Native AI settings and personal category creation passed in `/private/tmp/mysportly-soft-header-ipad-final.xcresult`. The header checks initially queried the wrong accessibility type; the actual native spinner is an ActivityIndicator, not a ProgressIndicator. Both remaining flows passed in `/private/tmp/mysportly-soft-header-ipad-confirmed.xcresult`: refresh without an inline loading/empty-favorites section, and Jev's header spinner with granted continued processing, progress advancing on Home, and Pause/Resume preserving the count. Screenshots were exported and inspected.
- The normal iPad app reopened with the 57,033-channel saved catalog. All saved placements remained identical, both manual correction versions survived, preferred pending groups stayed at zero, and the provider refresh timestamp did not change. Reopening caused neither a provider refresh nor a Jev rerun.
- The iPhone's latest UI test attempt encountered a sheet-focus failure and an expanded system Live Activity covering controls; it did not pass. The device was subsequently unavailable and the user chose iPad-only continuation. The final header build is delivered to the iPad; iPhone installation and the reverse correction check remain pending.
- Apple PCC naming remains disabled pending entitlement/runtime acceptance. Downloadable models remain an adapter contract. No OpenAI naming service or live-score service is activated.
- This pass does not retest live-provider playback, recording, broad codec compatibility, or every offline/concurrent CloudKit conflict.

Screens: [refresh header](header-refresh-ipad.png), [Jev header](header-jev-ipad.png), [native AI settings](ai-settings-ipad.png), [personal categories](personal-categories-ipad.png). These show the explicitly labeled sample profile; actual-playlist evidence is the separate aggregate audit above.
