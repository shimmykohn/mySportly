# iPad provider playback — 2026-10-20

Physical iPad A16 on iPadOS 27.0.1, Xcode 27.1 / SDK 27.1. No simulator was used. Existing source credentials stayed in the device Keychain. The saved catalog and personal organization were preserved.

## Diagnosis and observed recovery

- With the VPN active, all three recently attempted feeds failed before a video frame. The provider account endpoint returned HTTP 200 with an active account and zero of one connections used. The actual media endpoint returned HTTP 511, empty `text/html`, and no HLS playlist. AVPlayer reported the nested CoreMedia `HTTP 511` failure. This was a media-access rejection, not evidence of invalid login credentials or a missing playlist.
- Apple's public HLS sample played on the same iPad, including a nonzero video presentation size. The built app permits the provider's HTTP transport.
- The user disabled the iPad VPN. A fresh comparison then displayed real video on the first two feeds in approximately two seconds each: 1280×720 and 1920×1080. Their item status was ready to play, the video layer was ready, media time advanced, and no playback error was reported.
- Before the third sequential attempt, the provider still reported its single connection occupied. The diagnostic respected that limit and skipped opening another stream. This was not counted as a playback failure or pass.
- After the earlier connection had time to clear, the third feed was opened through the normal app's play URL. Its native player displayed the broadcaster's video with “This NBA event will resume shortly.” This confirms video delivery; it does not assert that active game footage was on air at that moment.
- The before/after comparison points to the VPN connection as the cause of the initial rejection. The provider's exact VPN/IP policy is unknown, and a second VPN-on trial was not performed.

## App changes

- Decode nested HTTP media failures into bounded messages without including provider addresses, credentials, or server-supplied error text.
- Stop automatic reconnect attempts for explicit access/missing-stream rejections and HTTP 511. Retain bounded retries for transient failures and an explicit Try Again action.
- Preserve the provider-specific error when offering alternate streams.
- Add opt-in, single-use physical-device diagnostics for recent feeds and media transport. These reuse the app's personal store rather than creating a competing CloudKit store. Diagnostic completion is distinct from successful video playback.

## Verification and delivery

- Optimized Debug `build-for-testing` succeeded.
- Two focused core tests passed for nested HTTP decoding, credential-free messages, permanent rejection handling, and transient retry classification.
- Three physical-iPad behavioral checks passed: a real local HTTP 404 shows its cause and does not reconnect automatically while manual retry still works; pause during preparation does not autoplay; Apple's public HLS sample plays.
- The opt-in real-provider checks completed, with the outcomes described above. No successful-playback claim is inferred from their XCTest pass status alone.
- `git diff --check` passed.
- The latest app was launched normally on iPad without sample/test arguments, and the third feed was left open. The user-disabled VPN remains off. No iPhone playback check was performed in this change.

Raw diagnostic reports, screenshots, and test results remain under `/private/tmp/mysportly-*2026-10-20*`; no source credentials, stream URLs, or personal viewing-history screenshots are copied into this repository. Relevant result bundles are `mysportly-playback-final-2026-10-20.xcresult` and `mysportly-vpn-off-2026-10-20.xcresult`.
