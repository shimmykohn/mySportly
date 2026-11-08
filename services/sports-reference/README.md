# Public sports directory

API-SPORTS account setup and authenticated checks completed October 18, 2026 (New York). The free plan rejected 2026 schedules for NFL, NBA, MLB, NHL, basketball and football, returning `plan: Free plans do not have access to this season, try from 2022 to 2024.` The user selected current TV-guide games with API-SPORTS reference artwork.

The app bundles 173 public team records and six league records exported from the allowed 2024 team endpoints. NFL/NBA/MLB/NHL conference and All-Star teams are excluded. Team names use the app's existing aliases, preserving Library/Favorite identities. The local vocabulary fills gaps without inventing logos. MLS/Premier League membership is a 2024 reference, not a promise of current-season rosters. No historical games are included.

The app reads this small signed resource offline, derives current games from the existing cached TV guide, and downloads public PNG logos on demand from the API-SPORTS media host. ImageIO downsamples off the main actor; the disk cache is limited to 32 MB and memory to 200 decoded images. Neither artwork nor the public directory goes into iCloud. Saved teams, leagues, favorites, and feed preferences continue through the existing personal store.

## Refreshing the reference for a later app build

Run `python3 services/sports-reference/update.py --key-file /absolute/path/to/private-key-file` with a private key file outside the repository, or provide `API_SPORTS_KEY` through the environment. Do not put a key directly in command history, Swift, Info.plist, tests, fixtures, or logs. The script uses six league and six team reads and replaces the JSON only after all responses are valid. Verify supported seasons before changing the fixed seasons. Review and build the resulting public JSON; reference updates are delivered with app updates.

There is no hosted sports service or client API key in this version. Live scores, current-season external schedules and automatic roster refreshes remain unavailable. A future paid or alternate schedule provider can use the separate SportsGameMatcher, but must first pass authenticated coverage checks.
