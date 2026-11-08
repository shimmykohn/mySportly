# Free sports API comparison

Researched October 18, 2026 from the providers' current documentation. The initial comparison preceded signup. The user subsequently selected API-SPORTS Free and completed the account setup. Authenticated checks rejected every tested 2026 schedule (NFL, NBA, baseball, hockey, basketball and football), returning a plan error limiting access to 2022–2024. Endpoint availability did not establish current-season coverage.

The app needs team and league identities, logo URLs, scheduled opponents and start times. Local rules will match those events to the user's channel names and EPG; no external sports API establishes which private playlist URL carries a game. AI remains outside this implementation pass.

## Candidates

| Provider | Free access | Fit and limitation |
| --- | --- | --- |
| API-SPORTS | 100 requests per day per API, all endpoints advertised, no credit card required | Best first candidate for broad sports coverage plus logos. Quota belongs to the developer account. Available data and seasons must be verified using a free key; endpoint access alone does not establish current-season access. |
| TheSportsDB | Shared free key, 30 requests/minute, team/league lookups and artwork | Daily schedules return at most three events; next-team schedule returns one home event. Free usage cannot support an App Store publication under its current terms. |
| BALLDONTLIE | NBA, NFL and MLB teams and games at 5 requests/minute | Good alternative for those three leagues. NHL games require a paid tier. The documented NBA/NFL team payloads do not include logo URLs, so artwork requires another source. |
| football-data.org | 12 soccer competitions, 10 calls/minute, delayed scores and schedules | Useful soccer supplement; does not replace a US multisport provider. |
| OpenLigaDB | Community data, no authentication, ODbL | Open-data option strongest in German football; not an established replacement for the app's US league directory. |

SportsDataIO's free Discovery Lab access supplies last season's data. Its integration trial uses scrambled data, making it unsuitable for matching real upcoming games in this build.

TheSportsDB's paid Single Developer plan currently costs $9/month and advertises 100 requests/minute and two-minute scores for soccer, NFL, NBA, MLB and NHL. This is a possible later choice, not an approved purchase. Its subscription and third-party image rights are separate.

## Selected free implementation

The user selected current games from the TV guide with API-SPORTS team names and logos where available. The authenticated 2024 reference endpoints returned 173 usable team records across NFL, NBA, MLB, NHL, MLS and Premier League, after excluding conference and All-Star teams. The app bundles only public reference records, derives current broadcast matchups locally from cached EPG, and caches artwork on each device. The directory is updated with app builds; it is not a current-roster service. No historical fixtures are shown as live. No paid plan, hosted sports backend, or runtime client API key was enabled.

See [the export and caching design](../../services/sports-reference/README.md). Device validation is recorded in build-progress.md.

## Original recommendation and acceptance criteria

Validate API-SPORTS first against current NFL, NBA, MLB and NHL schedules and representative team/league logos. Verify free-plan availability for each intended league and season before selecting it. If current coverage fails, reassess BALLDONTLIE for NBA/NFL/MLB and a separate NHL source rather than silently upgrading.

Use a shared, budgeted server cache to protect the developer key and reuse requests across users. Keep metadata and bounded logo caches on each device so launch and navigation never await the provider. Refresh reference records infrequently and schedules within the free quota; do not promise continuously fresh scores. Preserve cached records on provider failure and display freshness honestly. App users should not need sports-provider accounts.

Validate game matching, offline launch, stale responses, rate limiting and physical-device responsiveness separately from successful API authentication. Retain independent team/league identities so changing providers preserves Library and Favorites. Both TheSportsDB and API-SPORTS distinguish access to images from rights to publish third-party logos.

## Primary sources

- [API-SPORTS plans and coverage](https://api-sports.io/)
- [API-SPORTS NFL guide: identities, schedules, caching and quota](https://www.api-football.com/news/post/how-to-get-started-with-api-nfl-the-complete-beginners-guide)
- [API-SPORTS terms: free data limits and visual assets](https://www.api-football.com/terms)
- [API-FOOTBALL season limits](https://www.api-football.com/pricing)
- [TheSportsDB documentation](https://www.thesportsdb.com/documentation), [pricing](https://www.thesportsdb.com/pricing), [terms](https://www.thesportsdb.com/docs_terms_of_use.php)
- [BALLDONTLIE NBA](https://nba.balldontlie.io/), [NFL](https://nfl.balldontlie.io/), [MLB](https://mlb.balldontlie.io/), [NHL](https://nhl.balldontlie.io/), [permitted data use](https://www.balldontlie.io/terms.html)
- [football-data.org pricing](https://www.football-data.org/pricing)
- [OpenLigaDB](https://openligadb.de/)
- [SportsDataIO developer access](https://sportsdata.io/developers)
