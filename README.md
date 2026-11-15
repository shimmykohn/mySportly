# mySportly

A native SwiftUI live TV app for iPhone and iPad, targeting iOS/iPadOS 27.0+ with Xcode 27.1. It turns a large Xtream/M3U catalog into an Apple TV–style Home around the teams, leagues and channels you care about.

## Open and run

Open `mySportly.xcodeproj`, choose the **mySportly** scheme, and select an iPhone or iPad running iOS 27 or later (or the iOS Simulator). Use the existing development team or your own signing team.

The first launch offers **Connect a Source** and **Explore Sample Catalog**. Enter provider credentials in the app. Sample channels and schedules are explicitly labeled; their player opens Apple’s public HLS test stream. Add the launch argument `--demo` for an isolated, in-memory sample profile during UI testing (`--demo-sports-api-check` adds a live sample game, `--demo-home-follows` follows the Knicks, adds the NBA and favorites a sample channel).

## The app

- **Four tabs: Home · Guide · My Stuff · Search**, with an adaptive iPad sidebar. Settings opens from the profile button on Home and holds Sources, Region and Language, Appearance, iCloud sync, and OpenAI.
- **Home** is Apple TV–inspired: a hero of up to three pages (a followed team's live game, then its game later today, then the biggest live or upcoming game in an added league by matching streams, then a live program on a favorite channel), **Your Teams**, one row per added league (live and next 24 hours, without repeating Your Teams), and **Your Channels**. Game art uses colors taken from both team logos, with the logos on Liquid Glass. Rows with nothing to show are hidden; with nothing followed, Home shows one prompt to follow teams and leagues. Home is built by `HomeContent.build` from the launch snapshot first and updates when guide matching finishes; it makes no data request or model call.
- **Player:** a full-screen screen that zooms out of the tapped game, hero or channel. Portrait shows the native AVKit player (AirPlay, PiP, audio and subtitle menus), the title, channel and league, live progress for the current program, and a favorite heart; transport controls are the system player's own. Swipe down (or the chevron) minimizes into the mini player in the tab bar; landscape on iPhone shows only the video. First-frame readiness, bounded reconnects and automatic alternate feeds on failure are unchanged.
- **Follow model:** **Follow** a team, **Add** a league, **Favorite** a channel. My Stuff lists Teams, Leagues and Channels with swipe to remove; team and league pages show upcoming games on your lineup. Followed teams can notify you when a game starts (off by default, per team). A one-time, non-destructive migration turned older saves into follows and favorites. "Hide Channel" stays in channel context menus.
- **Titles:** every screen uses the standard (inline) navigation title; shelf headers use the Headline text style.
- **Search:** recent searches and short Liquid Glass browse buttons (Sports, News, Movies, Kids, your leagues, common sports) before typing; instant local results grouped as **Teams**, **Live Now** and **Channels** while typing. With an OpenAI key, a query local matching can’t interpret is sent to the Decisions API and the answer is searched locally, in place.
- **Guide:** current/tonight/date guide, list and iPad timeline, program details with Watch Live. Xtream imports its own EPG when the optional XMLTV field is blank; missing guide mappings are recovered locally from unique same-source/country names, quality variants, provider mappings and local call signs.
- **Sources:** Xtream Codes and M3U URL/file import, XMLTV guide, encrypted local catalog, Keychain credentials, cancel/refresh/remove. Automatic refresh keeps a daily playlist and a six-hour guide update with retry backoff and OS-scheduled background processing.
- **Instant launch:** reopening shows the first screen from a small sealed launch snapshot (favorites, recents, the feeds of Home's games, the head of the lineup and their next 24 hours of listings, plus Home's games). The full catalog then decodes and prepares in the background, reusing saved metadata and guide-match stages when their input fingerprints match. Saved listings keep only now through +3 days. Debug builds print a `[Launch]` timeline measured from the kernel's process start. Measurements are in `docs/product/evidence/instant-launch-2026-11/baseline.md`.
- **AI with OpenAI:** with your key (Settings → OpenAI, stored only in this device’s Keychain), new or changed channel groups are sorted into categories in the background with the Decisions API (`gpt-6-luna`), up to 400 groups per request. Results apply only at confidence ≥ 0.60 and selected probability ≥ 0.70; refused or uncertain groups keep their local category. Unchanged groups are never resent; results sync like other personal choices. Without a key everything uses local rules. See `docs/product/openai-decisions-api.md`.
- Removed in the redesign: Live, Sports and Library tabs; recording, catch-up, Multiview, reminders, spoiler settings, description translation, App Intents/Shortcuts, widgets, the Organizer and its diagnostics, Jev and Apple Intelligence.

## Integration setup

The app uses no mySportly account. CloudKit uses `iCloud.app.iska.mysportly`. Existing personal data stays local when cloud initialization fails. **Sync Personal Choices** takes effect after closing and reopening the app. Source secrets and the OpenAI key use the Keychain; provider caches are encrypted and excluded from backup.

## Verification

```sh
swift test --scratch-path /private/tmp/mysportly-core-build --disable-sandbox
```

UI and app tests run from the **mySportly** scheme on the iOS Simulator or a device, with `-parallel-testing-enabled NO`. Simulator launch timings include accessibility automation that XCUITest enables, so launch budgets are judged on devices.

The opt-in provider tests read a one-use `mySportly-provider-check.json` from the test host's temporary directory and delete that input afterward. Never put real credentials or API keys in source, launch arguments, or test fixtures; AI tests use recorded responses shaped like the documented API.
