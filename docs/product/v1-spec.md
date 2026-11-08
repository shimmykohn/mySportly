# mySportly V1

Status: Feature scope agreed; native SwiftUI implementation and verification in progress as of 2026-10-18. See [build evidence](build-progress.md) for verified results and remaining device/provider acceptance.

## Product

An all-purpose live TV app that turns a provider's large, disorganized catalog into a useful personal lineup. Sports has its own section. AI channel organization is a first-release requirement.

The first release targets iPhone and iPad on iOS/iPadOS 27.0+. The installed development toolchain is Xcode 27.1. Apple TV and Mac are subsequent platform builds, not substitutes for iPhone/iPad acceptance.

V1 includes every feature below. Implementing in increments does not move features to a later release or make a partial implementation release-ready.

## Native interface contract

The user's latest direction supersedes the generated mockups' styling. Apple TV and Music are references for platform behavior and clarity, not pixel-perfect clones or a license to imitate Apple's private components.

- Use standard SwiftUI navigation, tabs, lists, forms, toolbars, menus, pickers, sheets, alerts, and confirmation dialogs.
- Let iOS supply Liquid Glass to system chrome. Do not draw custom tab bars, glass capsules, floating navigation docks, blur stacks, gradient wallpapers, glowing borders, or bespoke control styles.
- Use semantic system typography, SF Symbols, semantic foreground/background styles, standard spacing, native selection states, and automatic light/dark appearance.
- Use provider-supplied channel/program artwork when available. Missing artwork gets a standard symbol; do not fabricate program imagery or use generated UI screenshots as app assets.
- Use standard list rows with sections, navigation links, swipe actions, selection, and reorder/edit behavior for channels and organization.
- Use `Form` for source connection, preferences, and settings; standard sheets for bounded tasks and navigation destinations for deeper screens.
- Use native `AVPlayerViewController` for full playback controls, picture in picture, audio/captions, and AirPlay where available. UIKit bridging to Apple's player is allowed; a custom player-control skin is not required.
- Use `TabView` and `NavigationStack` on iPhone. Use system adaptive tabs/sidebar and `NavigationSplitView` where appropriate on iPad.
- Use the system tab accessory API for the compact player where supported. Keep the accessory small and accessible, without custom glass decoration.
- A time-based guide and multiview composition need app-specific layout, but keep their typography, surfaces, selection, navigation, and controls native. Offer an accessible guide list alongside the timeline.
- Support Dynamic Type, VoiceOver, Increase Contrast, Reduce Transparency, Reduce Motion, keyboard navigation, and iPad resizing.
- Do not add a web prototype, third-party UI kit, or image-based control facsimiles to satisfy the native app requirement.

## Navigation and screen map

Five primary destinations: Live, Guide, Sports, Library, Search. Search has an always-visible native search bar in its navigation header, matching the user's follow-up preference. Other searchable screens use the same header placement. Keep the toolbar settings action and native soft scroll-edge blur.

| Flow | Screens and presentations | Native structure |
| --- | --- | --- |
| First launch | Introduction; connect source; language and region; interests; import progress | NavigationStack, Form, Picker, ProgressView |
| Sources | Source list; Xtream connection; M3U connection/import; connection errors; edit/refresh/remove source | List, Form, SecureField, fileImporter, alert/confirmationDialog |
| Organizer | Suggested lineup; category review; duplicate/quality groups; uncertain matches; suggestion details; apply result and undo | Sectioned List, DisclosureGroup, selection, sheet, toolbar actions |
| Channel management | All channels; favorites; custom group list/editor; channel detail; preferred variant; bulk edit/reorder/hide | List, NavigationLink, Form, EditButton, swipe actions, Menu |
| Live | Personal lineup; recent channels; For You; relevance explanation; default-opening-screen preference | Native sections and rows, program detail sheet |
| Guide | Now; tonight; date/time navigation; timeline; accessible list; filters; program detail; guide mapping/time corrections | List, DatePicker, Picker/Menu, native detail sheet; restrained custom timeline layout |
| Sports | Live events; upcoming events; teams/leagues; favorites; event details; spoiler preference | Sectioned List, searchable selection lists, detail navigation |
| Search | Keyword results; natural-language results; refined filters; no-match state; lineup request preview | searchable, List, ContentUnavailableView, review sheet |
| Playback | Inline/fullscreen player; compact player; channel/variant selection; available audio/captions; playback errors/retry | AVKit player, system tab accessory, native lists/sheets/menus |
| Multiview | Channel selection; layout; active audio; replace/remove stream; connection-limit state | Native selection sheet and toolbar around player composition |
| Reminders | Program reminder action; reminder list; edit/cancel; notification permission state | Program detail action, List, Form, system permission request |
| Catch-up | Eligible previous programs; availability window; catch-up playback; unavailable state | Guide/program detail and AVKit player |
| Recordings | Start/stop; active recording; recordings list; local playback; storage/delete; interruption/failure | Native player action, List, ProgressView, confirmationDialog |
| Settings | Sources; languages/region; interests; preferred audio; appearance; default screen; AI; privacy; iCloud; storage | Form with standard navigation and controls |
| System integration | Play/open channel; open guide; quick-access widgets; system playback controls | App Intents, WidgetKit, supported Now Playing integration |

## Setup and personalization

- Suggest languages and region from device language/region preferences, then ask the user to confirm or edit. This is a starting suggestion, not inferred physical location or a permanent content restriction. Do not require location permission.
- Support ranked language preferences, optional additional languages, preferred regions, and interests.
- Keep channel language, regional edition, audio-track preference, and guide-display language separate.
- The initial personal test profile is English with United States regional preference. Do not hard-code that profile for everyone.
- Unknown-language or uncertain channels stay discoverable. Users can pin any channel regardless of filters.
- Follow-up choice: use **My Lineup** as the default across Live, Guide, Sports, Search, and the player picker. Match selected regions and known channel languages; allow unknown language only through the explicit **Include Unknown Languages** setting. Unknown regions are discoverable in **Unclassified** and **All Channels**. The shared scope is editable and synced as a personal choice. Explicit favorites and custom groups stay available independently.
- Favorites, recent channels, groups, hide/reorder/rename, bulk editing, preferred source variants, appearance, and default opening screen are included without a customization paywall.

## Catalog and AI organizer

- Accept Xtream Codes and M3U sources. Keep provider identity, source channel IDs, original names, and original metadata intact.
- Build a local catalog/index; use stable source-scoped identifiers. Re-importing must not duplicate channels or erase user choices.
- Normalize obvious metadata locally; evaluate TypeSafe/Jev for ambiguous categories, likely language, candidate duplicate/variant groups, and ranking. Return explicit unknown/uncertain outcomes.
- Local rules run before optional AI and read country/language tags and category keywords from original provider metadata. Preserve raw identities and names; do not label a US channel English solely because it is US. Manual overrides remain authoritative. Pure provider-metadata review must not substitute cached AI decisions.
- Distinguish the same feed in different qualities from regional, language, time-shifted, event, or differently scheduled feeds. Similar names alone do not justify merging.
- Preview organization changes; users can inspect uncertain matches, edit groups, apply suggestions, and undo. Explicit user corrections outrank later automated suggestions.
- Preserve all original stream variants. Grouping is a reversible presentation choice, not deletion of the provider catalog.
- Cache decisions and process new or changed catalog entries incrementally. Large imports and searches must not block the UI.
- Use Apple's available on-device model for supported natural-language assistance. Optional stronger Apple PCC/OpenAI services remain adapters with capability and configuration checks.
- Requests such as "organize my channels", "find basketball now", or "make a weekend lineup" operate against real catalog/guide candidates. Validate returned identifiers and actions before applying them.
- AI unavailability, rate limits, missing configuration, or uncertainty must preserve normal search, organization, and playback. Never label a rule-only fallback as a completed model evaluation.
- Send only necessary channel/program metadata to an enabled cloud AI service. Do not send provider credentials, credential-bearing URLs, or video/audio to classification services.
- App-managed cloud model keys require a service boundary; never embed a shared service key in the app. Cloud AI billing/configuration is an implementation dependency, not an extra app-user signup requirement.

## Guide, relevance, and sports

- Load actual provider/EPG data, with Now, Tonight, Favorites, Sports, and Language filters. Keep channel order stable; show personalized program ranking in For You.
- Display accurate local times, dates, time zones, current progress, now/next, and source freshness. Support manual channel-to-guide mapping and time offsets.
- Show missing or stale guide data explicitly. Do not invent program times, live events, scores, or availability.
- Xtream's guide is automatic unless a replacement XMLTV URL is supplied. Provide a native **TV Guide Status** screen with matched/current/missing/expired coverage for the selected lineup; guide-text language must not be treated as evidence of stream audio language.
- Default Guide to channels with listings in the selected six-hour window, with a native **Only Channels with Listings** toggle to reveal missing mappings. This affects guide presentation, not stream availability or source import.
- Recommendations use explicit preferences/favorites first. Explain relevant factors; make use of viewing history controllable.
- Support native swipe-to-remove for individual Recently Watched entries, preserving the stream and favorites. Use the same synced history tombstones as other personal deletions.
- Keep explicitly inactive provider event slots out of Home's automatic channels and recommendations while retaining access through All Channels. Exclude placeholder program titles from recommendations/Sports, and recommend at most one feed per shared schedule and time offset.
- Repair missing guide mappings with conservative local, source-scoped rules: unique normalized channel names and country, existing mapped quality variants, XMLTV display names, and exact local station call signs. Preserve editions, languages, time shifts, valid provider IDs, and all manual choices. Ambiguous feeds remain unmapped. Show the automatic match reason and explicit automatic/provider-only controls.
- Provide optional guide-description translation while retaining the original text. Translation does not establish audio language.
- Guide opens with a compact Now & Next row for each channel. Time selection remains in the toolbar; lineup, listings-only, optional timeline, and guide status live in Guide Filters. A channel opens its schedule before program details.
- Sports has All Sports and My Sports. Library has separate Teams and Leagues collections. Adding an item saves it and includes its matching programs in My Sports and Live recommendations. An independent Favorite action pins a saved item in Library; unfavoriting does not remove it. Removing from Library clears the favorite. Existing follows carry over.
- Team/league detail pages show matching programs in the next 48 hours and separate matching channels without guide listings. Use conservative whole-name and alias matching with league context for ambiguous nicknames. An unscheduled event channel must never be labeled a confirmed live game.
- Sports names currently come from an offline directory, with custom entries supported. Schedules come from provider EPG; no sports score or logo API is connected. API-SPORTS' free developer plan is a candidate for future metadata/logo integration; no subscription or key was added.

## Playback, multiview, catch-up, and recording

- Prove the user's provider formats with native playback early. Xtream is a source API, not a guarantee of Apple-compatible codecs. Add another playback engine only if compatibility evidence requires it.
- Include quick channel switching, previous channel, mini player, fullscreen, available audio/captions, picture in picture, and AirPlay.
- Reconnect with bounded retries. Offer or select an appropriate alternate saved variant under the user's preference; avoid endless switching and stale playback tasks.
- If a playing feed supplies no video, wait eight playing seconds and try at most two exact same-source event alternatives, retaining event time, teams, language, and region. Release the old player item first to respect one-connection accounts. Explain the switch; show an explicit no-video message if no alternative is available. This does not add codec support to AVPlayer.
- The player close control uses the system toolbar's regular Liquid Glass background and a neutral X, without a blue prominent fill. It dismisses the sheet; the mini player has a separate Stop control.
- Multiview is an iPad feature. Respect source connection limits and hardware capability; allow one selected audible stream. Tear down replaced/stopped players promptly.
- Catch-up appears only when the source supports it for that channel/program and time window.
- Recording choice confirmed: on-device recording while the app stays active. Recordings remain local. Scheduled unattended/cloud DVR is outside V1.
- Verify recording support per stream/format. Handle app lifecycle interruption, storage exhaustion, network failure, partial recordings, and deletion explicitly. Do not imply guaranteed recording after the app is closed.

## Persistence, credentials, and sync

- No mySportly account. Use the person's existing Apple Account for optional iCloud sync; support local use when iCloud is unavailable.
- Use SwiftData for personal data and a compatible private CloudKit schema. Sync the lineup, groups, favorites, corrections, preferences, and user-enabled history.
- Cache provider catalogs and EPG locally instead of synchronizing enormous refreshed datasets through the user's personal CloudKit store.
- Store provider secrets in Keychain; only use supported credential-sync mechanisms. Treat token-bearing M3U URLs as credentials too.
- Keep recording files local; synchronize neither video blobs nor transient player state as ordinary preference records.
- Report actual cloud configuration/account state. The existing project's empty container list is not evidence of working iCloud sync.
- Define stable identities, idempotent imports, deletion handling, conflict behavior, and persistent user-override precedence before release.

## Acceptance

1. Connect a real provider inside the app, import its catalog, and play representative streams on iPhone and iPad.
2. Organize a representative messy catalog; inspect grouping errors, language ambiguity, and regional variants; demonstrate apply, correction, undo, and persistence after refresh.
3. Show relevant real guide listings; validate time zones, missing mappings, and stale data; search and play a returned program/channel.
4. Demonstrate channel editing, favorites, recent playback, Sports, reminders, and guide corrections.
5. Verify native fullscreen, mini player, audio/captions where supplied, picture in picture, AirPlay on hardware, previous channel, and stream recovery.
6. Exercise iPad multiview with actual provider limits and one audible player.
7. Validate supported catch-up and foreground recording with local playback; unsupported cases must be honest and actionable.
8. Confirm personal data survives relaunch and synchronizes between two real devices using the same iCloud account, including a user correction.
9. Validate on-device AI on eligible hardware and configured cloud adapters separately; offline/AI-unavailable behavior remains usable.
10. Test Siri/Shortcuts, widgets, and system playback controls; verify navigation and accessibility in light/dark mode, large text, and resized iPad windows.

Build success, generated designs, sample catalogs, mocked services, and a configured entitlement do not independently satisfy these acceptance checks.
