import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/core/holidays/holiday_source.dart';

@immutable
class HolidayCountry {
  const HolidayCountry({required this.code, required this.name});

  final String code;

  /// CLDR name in the reading language; English when CLDR has none.
  final String name;
}

const String _dir = 'assets/holidays';

/// Bundled countries, named in [language]. Type inferred: `flutter_riverpod`
/// does not export `FutureProviderFamily`.
final holidayCountriesProvider =
    FutureProvider.family<List<HolidayCountry>, String>((
      Ref ref,
      String language,
    ) async {
      final Object? parsed = jsonDecode(
        await rootBundle.loadString('$_dir/countries.json'),
      );
      if (parsed is! List<dynamic>) return const <HolidayCountry>[];

      final Map<String, String> localized = await _namesFor(language);
      final List<HolidayCountry> countries = <HolidayCountry>[
        for (final Object? row in parsed)
          if (row is Map<String, dynamic> &&
              row['code'] is String &&
              row['name'] is String)
            HolidayCountry(
              code: row['code'] as String,
              name: localized[row['code'] as String] ?? row['name'] as String,
            ),
      ];

      // countries.json is sorted by English name.
      countries.sort(
        (HolidayCountry a, HolidayCountry b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return countries;
    });

/// Empty when no names are bundled for [language].
Future<Map<String, String>> _namesFor(String language) =>
    _json('countries.$language.json');

/// A flat string map from [file] under the holidays directory. Empty when the
/// file is missing.
Future<Map<String, String>> _json(String file) async {
  final String raw;
  try {
    raw = await rootBundle.loadString('$_dir/$file');
  } on Object {
    // A missing asset throws FlutterError, an Error, not an Exception.
    return const <String, String>{};
  }

  final Object? parsed = jsonDecode(raw);
  if (parsed is! Map<String, dynamic>) return const <String, String>{};
  return <String, String>{
    for (final MapEntry<String, dynamic> e in parsed.entries)
      if (e.value is String) e.key: e.value as String,
  };
}

/// Regions of [country] with their own holidays, named in [language], then in
/// English, then by code. Empty for a country without any.
final holidayRegionsProvider =
    FutureProvider.family<
      List<HolidayCountry>,
      ({String country, String language})
    >((Ref ref, ({String country, String language}) key) async {
      final Set<String> codes = (await const HolidayBundle().regionsOf(
        key.country,
      )).keys.toSet();
      if (codes.isEmpty) return const <HolidayCountry>[];

      final Map<String, String> english = await _json('regions.en.json');
      final Map<String, String> localized = key.language == 'en'
          ? english
          : await _json('regions.${key.language}.json');
      return <HolidayCountry>[
        for (final String code in codes)
          HolidayCountry(
            code: code,
            name: localized[code] ?? english[code] ?? code,
          ),
      ]..sort(
        (HolidayCountry a, HolidayCountry b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    });
