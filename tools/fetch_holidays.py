#!/usr/bin/env python3
"""Regenerate assets/holidays/ from date.nager.at.

Nationwide entries (`global: true`) go to <CODE>.json. Entries observed only
in some regions go to regions/<CODE>.json, keyed by region code (`DE-BY`), so
a regional holiday shifts a pay date only for someone who chose that region.

    python tools/fetch_holidays.py .                 # default year span
    python tools/fetch_holidays.py . --years 2026 2031
    python tools/fetch_holidays.py . --codes RU DE US

Writes one <CODE>.json per bundled country, regions/<CODE>.json where it has
regional days, names/<CODE>.json with the names of all those days, index.json
listing the codes, countries.json listing every country the API knows, and
regions.<locale>.json with region names from CLDR.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

API = 'https://date.nager.at/api/v3'

# Country names per language, from Unicode's own data. Only the names live
# here; the code list stays in countries.json, so a locale file is an overlay
# and not a second source of truth about which countries exist.
CLDR = ('https://raw.githubusercontent.com/unicode-org/cldr-json/main'
        '/cldr-json/cldr-localenames-full/main')

TIMEOUT = 30
RETRIES = 3

# Kept in sync with index.json; used only when index.json is absent.
DEFAULT_CODES = [
    'AT', 'CA', 'CH', 'CZ', 'DE', 'ES', 'FI', 'FR', 'GB', 'IE',
    'IT', 'KZ', 'NL', 'NO', 'PL', 'PT', 'RU', 'SE', 'UA', 'US',
]


def get(url: str) -> object:
    for attempt in range(1, RETRIES + 1):
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
                return json.load(response)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
            if attempt == RETRIES:
                raise
            time.sleep(2 * attempt)
    raise AssertionError('unreachable')


# Subdivision names per language, from CLDR's XML: cldr-json has none.
CLDR_SUBDIVISIONS = ('https://raw.githubusercontent.com/unicode-org/cldr/main'
                     '/common/subdivisions')


def _joined(names: dict[str, list[list[str]]]) -> dict[str, list[str]]:
    """Date -> [English name, local name]; the local one only when it differs.

    Two holidays on one date are joined into one name.
    """
    out: dict[str, list[str]] = {}
    for date, pairs in sorted(names.items()):
        english = ' / '.join(dict.fromkeys(p[0] for p in pairs if p[0]))
        local = ' / '.join(dict.fromkeys(p[1] for p in pairs if p[1]))
        out[date] = [english] if not local or local == english else [
            english, local]
    return out


def holidays(code: str, year: int) -> tuple[
        dict[str, list[str]], dict[str, list[str]], dict[str, list[str]]]:
    """Nationwide names, region -> dates, and regional names, by date."""
    entries = get(f'{API}/PublicHolidays/{year}/{code}')
    if not isinstance(entries, list):
        raise ValueError(f'{code} {year}: unexpected payload')
    national: dict[str, list[list[str]]] = {}
    regional: dict[str, list[list[str]]] = {}
    regions: dict[str, list[str]] = {}
    for e in entries:
        if not (isinstance(e, dict) and e.get('date')):
            continue
        pair = [e.get('name') or '', e.get('localName') or '']
        if e.get('global') is True:
            national.setdefault(e['date'], []).append(pair)
            continue
        counties = e.get('counties')
        if not isinstance(counties, list) or not counties:
            continue
        regional.setdefault(e['date'], []).append(pair)
        for county in counties:
            if isinstance(county, str):
                regions.setdefault(county.upper(), []).append(e['date'])
    return (_joined(national),
            {r: sorted(set(d)) for r, d in regions.items()},
            _joined(regional))


def write_region_names(out: pathlib.Path, locales: list[str],
                       codes: set[str]) -> None:
    """One `regions.<locale>.json` per locale: `DE-BY` -> localized name."""
    for locale in locales:
        try:
            with urllib.request.urlopen(
                    f'{CLDR_SUBDIVISIONS}/{locale}.xml',
                    timeout=TIMEOUT) as response:
                root = ET.fromstring(response.read())
        except (urllib.error.URLError, ET.ParseError):
            print(f'{locale}: no CLDR subdivisions, skipped', file=sys.stderr)
            continue
        # CLDR writes `deby` for `DE-BY`.
        by_cldr = {c.replace('-', '').lower(): c for c in codes}
        localized = {
            by_cldr[s.get('type', '')]: s.text
            for s in root.iter('subdivision')
            if s.get('type') in by_cldr and s.text
        }
        path = out / f'regions.{locale}.json'
        path.write_text(
            json.dumps(dict(sorted(localized.items())), ensure_ascii=False,
                       indent=2) + '\n',
            encoding='utf-8')
        missing = len(codes) - len(localized)
        note = f', {missing} without a name' if missing else ''
        print(f'regions.{locale}.json: {len(localized)} names{note}')


def write_country_names(out: pathlib.Path, locales: list[str],
                        codes: set[str]) -> None:
    """One `countries.<locale>.json` per locale: code -> localized name.

    Names are not put in the app dictionaries on purpose. Two hundred country
    names in every dictionary is one identical block per language, and the
    parity test would demand all of them.
    """
    for locale in locales:
        payload = get(f'{CLDR}/{locale}/territories.json')
        try:
            names = (payload['main'][locale]  # type: ignore[index]
                     ['localeDisplayNames']['territories'])
        except (KeyError, TypeError):
            print(f'{locale}: no CLDR territories, skipped', file=sys.stderr)
            continue

        # Two-letter codes only: CLDR also carries numeric regions ("150" for
        # Europe) and `-alt-` variants, none of which are countries here.
        localized = {
            code: name
            for code, name in names.items()
            if len(code) == 2 and code.isalpha() and code in codes
        }
        path = out / f'countries.{locale}.json'
        path.write_text(
            json.dumps(dict(sorted(localized.items())), ensure_ascii=False,
                       indent=2) + '\n',
            encoding='utf-8')
        missing = len(codes) - len(localized)
        note = f', {missing} without a name' if missing else ''
        print(f'countries.{locale}.json: {len(localized)} names{note}')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=pathlib.Path, help='repository root')
    parser.add_argument('--years', type=int, nargs=2, metavar=('FIRST', 'LAST'),
                        default=[2026, 2031])
    parser.add_argument('--codes', nargs='+', metavar='CC')
    parser.add_argument('--all', action='store_true',
                        help='every country in countries.json')
    parser.add_argument('--names', nargs='*', metavar='LOCALE',
                        default=['en', 'ru'],
                        help='locales to write country names for; '
                             'pass with no values to skip')
    parser.add_argument('--names-only', action='store_true',
                        help='refresh country names, leaving holidays alone')
    args = parser.parse_args()

    out = args.root / 'assets' / 'holidays'
    if not out.is_dir():
        print(f'not a holidays directory: {out}', file=sys.stderr)
        return 1

    if args.names_only:
        existing = json.loads(
            (out / 'countries.json').read_text(encoding='utf-8'))
        write_country_names(
            out, args.names, {r['code'] for r in existing})
        return 0

    index = out / 'index.json'
    if args.all:
        countries = get(f'{API}/AvailableCountries')
        codes = sorted(
            c['countryCode'].upper()
            for c in countries  # type: ignore[union-attr]
            if isinstance(c, dict) and c.get('countryCode')
        )
    elif args.codes:
        codes = [c.upper() for c in args.codes]
    elif index.exists():
        codes = json.loads(index.read_text(encoding='utf-8'))
    else:
        codes = DEFAULT_CODES

    first, last = args.years
    years = list(range(first, last + 1))

    names_dir = out / 'names'
    names_dir.mkdir(exist_ok=True)
    regions_dir = out / 'regions'
    regions_dir.mkdir(exist_ok=True)
    written: list[str] = []
    all_regions: set[str] = set()
    for code in codes:
        by_year: dict[str, list[str]] = {}
        by_region: dict[str, dict[str, list[str]]] = {}
        names: dict[str, list[str]] = {}
        for year in years:
            days, regions, regional_names = holidays(code, year)
            if days:
                by_year[str(year)] = list(days)
                names.update(days)
            for region, dates in regions.items():
                by_region.setdefault(region, {})[str(year)] = dates
            for date, name in regional_names.items():
                names.setdefault(date, name)
            time.sleep(0.2)
        if not by_year:
            print(f'{code}: no nationwide days in {first}-{last}, skipped',
                  file=sys.stderr)
            continue
        path = out / f'{code}.json'
        path.write_text(json.dumps(by_year, indent=2) + '\n', encoding='utf-8')
        (names_dir / f'{code}.json').write_text(
            json.dumps(dict(sorted(names.items())), ensure_ascii=False,
                       indent=2) + '\n',
            encoding='utf-8')
        region_path = regions_dir / f'{code}.json'
        if by_region:
            region_path.write_text(
                json.dumps(dict(sorted(by_region.items())), indent=2) + '\n',
                encoding='utf-8')
            all_regions.update(by_region)
        elif region_path.exists():
            region_path.unlink()
        written.append(code)
        total = sum(len(v) for v in by_year.values())
        print(f'{code}: {total} days across {len(by_year)} years')

    # index.json lists what was actually written, never what was asked for: a
    # country with no nationwide days gets no file, and the app asserts the two
    # agree. Files for codes that dropped out are removed for the same reason.
    index.write_text(json.dumps(sorted(written), indent=2) + '\n',
                     encoding='utf-8')
    keep = {f'{c}.json' for c in written} | {'index.json', 'countries.json'}
    for stale in sorted(p for p in out.glob('*.json') if p.name not in keep):
        stale.unlink()
        print(f'removed stale {stale.name}', file=sys.stderr)
    for stale in sorted(p for d in (names_dir, regions_dir)
                        for p in d.glob('*.json') if p.stem not in written):
        stale.unlink()
        print(f'removed stale names/{stale.name}', file=sys.stderr)

    countries = get(f'{API}/AvailableCountries')
    if isinstance(countries, list):
        rows = sorted(
            ({'code': c['countryCode'], 'name': c['name']}
             for c in countries
             if isinstance(c, dict) and c.get('countryCode') and c.get('name')),
            key=lambda r: r['name'],
        )
        (out / 'countries.json').write_text(
            json.dumps(rows, indent=2) + '\n', encoding='utf-8')
        print(f'countries.json: {len(rows)} countries')

        if args.names:
            write_country_names(out, args.names,
                                {r['code'] for r in rows})
    if args.names:
        write_region_names(out, args.names, all_regions)

    print(f'years {first}-{last}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
