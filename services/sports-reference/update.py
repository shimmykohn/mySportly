#!/usr/bin/env python3
"""Export public team/logo references. Never include the API key or game schedules."""
import argparse
import datetime
import json
import os
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

CATALOGS = [
    ('american-football', 'v1.american-football.api-sports.io', 1, 'NFL', '2024', {'NFC', 'AFC'}),
    ('basketball', 'v1.basketball.api-sports.io', 12, 'NBA', '2024-2025', {'Candace’s Rising Stars', 'Chuck’s Global Stars', 'Kenny’s Young Stars', 'Shaq’s OGs'}),
    ('baseball', 'v1.baseball.api-sports.io', 1, 'MLB', '2024', {'American League', 'National League'}),
    ('hockey', 'v1.hockey.api-sports.io', 57, 'NHL', '2024', set()),
    ('football', 'v3.football.api-sports.io', 253, 'MLS', '2024', set()),
    ('football', 'v3.football.api-sports.io', 39, 'Premier League', '2024', set()),
]


def fetch(host, endpoint, params, key):
    url = f'https://{host}/{endpoint}?' + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={'x-apisports-key': key})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(4_000_001)
    if len(data) > 4_000_000:
        raise ValueError('Oversized reference response')
    value = json.loads(data)
    if value.get('errors') or not value.get('response'):
        # Do not replace a good bundle with an empty response or a plan error.
        raise ValueError(f'{host}/{endpoint}: reference unavailable; existing file retained')
    return value['response']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key-file', type=Path, help='Private local key file; otherwise use API_SPORTS_KEY')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[2] / 'mySportly/Sports/sports-reference.json')
    args = parser.parse_args()
    key = args.key_file.read_text().strip() if args.key_file else os.environ.get('API_SPORTS_KEY', '').strip()
    if not key:
        parser.error('Supply API_SPORTS_KEY or --key-file. Do not commit a key.')
    leagues, teams = [], []
    for sport, host, league_id, name, season, excluded in CATALOGS:
        rows = fetch(host, 'leagues', {'id': league_id}, key)
        raw_league = next(x.get('league', x) for x in rows if x.get('league', x)['id'] == league_id)
        identity = f'apisports.{sport}.{league_id}'
        leagues.append({'id': identity, 'name': name, 'logo': raw_league.get('logo')})
        for raw in fetch(host, 'teams', {'league': league_id, 'season': season}, key):
            team = raw.get('team', raw)
            if team['name'] in excluded:
                continue
            teams.append({'id': f'apisports.{sport}.team.{team["id"]}', 'name': team['name'], 'leagueID': identity, 'logo': team.get('logo')})
    if len({x['id'] for x in teams}) != len(teams):
        raise ValueError('Duplicate team identities; existing file retained')
    result = {
        'version': 1, 'fetchedAt': datetime.datetime.now(datetime.timezone.utc).timestamp(),
        'leagues': leagues, 'teams': teams, 'games': [],
        'issues': {'Reference data': 'Team and logo references use the free plan’s available 2024 data. Current games come from your TV guide. Some newer teams or competitions may have no logo.'},
    }
    output = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if key in output:
        raise ValueError('Unexpected credential in response; existing file retained')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    staging = args.output.with_suffix('.json.pending')
    staging.write_text(output)
    staging.replace(args.output)
    print(f'Exported {len(leagues)} leagues and {len(teams)} teams. No games or credentials exported.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, urllib.error.URLError) as error:
        # Never dump request headers, response bodies, or environment variables.
        raise SystemExit(f'Reference update failed ({type(error).__name__}); existing bundle retained.')
