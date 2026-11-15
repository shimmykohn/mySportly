# Group decisions

The original per-channel Apple/OpenAI/TypeSafe classifier and prototype gateway have been retired. The app now uses the group pipeline in `mySportly/Core/GroupDecisions.swift`.

## Current personal build

- A person supplies their own TypeSafe key in Settings → AI → Connection. The key lives in that device's Keychain, outside the app bundle, logs, iCloud records, and catalog.
- Settings → AI is a native Form with the preferred audience, user-owned category choices, connection, progress, and review links. New profiles choose categories before their first run. Optional starting choices are not preselected. Existing profiles keep their established choices until edited. Editing the choice list guides future decisions without discarding saved placements. Interests and favorites affect presentation priority separately.
- Jev always uses the person's selected regions and languages, including the explicit Unknown Languages preference. Switching the browser to All Channels does not widen AI processing. Pending and resumed work is checked against the current audience before each request and again before saving.
- The app calls TypeSafe's official `POST https://api.typesafe.ai/v1/systemone`, pinned to `jev-1.13.0` for reproducibility.
- Up to 32 groups share a checkpoint batch. Each question carries its own structured group metadata and readable category choices; later questions offer only children of the selected parent. Requests split further when their encoded body exceeds 48 KB. Organize My Lineup queues new or changed groups within the preferred audience, capped at 100,000 per explicit run.
- Inputs contain bounded shared titles, provider folder labels, language/region labels, and candidate paths. URLs, provider credentials, media, and viewing history are excluded. Text fields are treated as data, not instructions.
- Responses must contain exactly the requested IDs, known choices, finite confidence/probabilities, and a normalized distribution. A close split stays reviewable instead of discarding the entire batch. No open-ended model category is accepted as an existing choice.
- Automatic placement requires confidence ≥0.60 and selected probability ≥0.70 at every step. These are conservative initial product thresholds, not measured accuracy guarantees. Other decisions stay in review.
- `none` asks the `GroupNameProposer` for a short new label. `here` keeps broad coverage at its parent. Apple PCC is the current proposer, gated behind its separately granted entitlement and runtime availability. This build keeps `SportlyPCCEnabled=false`; a missing entitlement leaves a visible Needs a name result and manual naming available. New proposed names require acceptance.
- Every completed result, including Needs review and Needs a name, is saved as a per-group private iCloud record. Unchanged results are reused after refresh and on other devices. Stream IDs, qualities, numbered slots and changing events do not invalidate an established family. Changed provider context or a deliberately updated decision-policy version makes automatic results eligible for another explicit run; refresh itself does not call Jev. Manual group corrections remain authoritative, and channel-level manual categories win over groups.
- Leaf categories finish without another model question. Root descriptions distinguish adult animation from children's programming, and provider country/coverage labels do not become redundant sport subcategories. Titles are sampled across each group instead of taking only its first members.
- Live shows one native spinner in the soft navigation header's title position while opening, syncing iCloud, refreshing, organizing, or preparing the feed. It has no text, separate progress panel, or completed/empty placeholder. AI settings contains the progress bar, completed count, and Pause/Resume. A device-local queue checkpoints opaque group IDs only after decisions have been saved. Restoring an unfinished run requires an explicit Resume; launching or refreshing never silently starts model calls.
- User-started work requests Apple's `BGContinuedProcessingTask`, including its system Live Activity. On iOS 27 scheduling uses `submitTaskRequest`. Work can continue after leaving the app when the system grants execution. If unavailable, the app pauses on backgrounding; system expiration or user cancellation also preserves completed work. This is not guaranteed execution after force-quitting or indefinite unattended work.
- A future downloadable model can implement `GroupDecisionModel`; no downloadable model is bundled or advertised as installed.

A broadly distributed app with a shared developer-paid key would need a hosted authenticated service and usage controls. The present implementation is a personal-key integration and does not ship a shared key.

## Device acceptance

The Debug-only `DevelopmentGroupAudit` reads a one-use request from the app's Documents directory and operates on the normal app's one live store. It can inspect, organize an explicitly authorized preferred lineup, prepare/resume a durable queue, refresh the actual source, observe expected iCloud mutation versions, or apply a validated manual correction. Its reports exclude source/playback URLs, credentials and viewing history. Release builds omit this helper. Keep full playlist reports outside the repository; retain only aggregate results and bounded examples in the evidence log.

## References

- [TypeSafe HTTP API](https://docs.typesafe.ai/api)
- [Choice and hierarchical decisions](https://docs.typesafe.ai/primitives/choice)
- [Apple continued background processing](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados/)
- [Apple PCC access](https://developer.apple.com/private-cloud-compute/)
