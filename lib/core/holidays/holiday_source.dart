import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:sielto/domain/value/calendar_date.dart';

/// Bundled public holidays: nationwide, plus a region's own. Must cover
/// `recurrenceHorizonMonths` ahead; regenerate with `tools/fetch_holidays.py`.
class HolidayBundle {
  const HolidayBundle();

  static const String _dir = 'assets/holidays';

  static Future<Set<String>>? _codes;

  /// Country codes from `index.json`, parsed once.
  Future<Set<String>> bundledCodes() => _codes ??= _loadCodes();

  static Future<Set<String>> _loadCodes() async {
    final Object? parsed = jsonDecode(
      await rootBundle.loadString('$_dir/index.json'),
    );
    if (parsed is! List<dynamic>) return const <String>{};
    return <String>{
      for (final Object? code in parsed)
        if (code is String) code.toUpperCase(),
    };
  }

  /// Null when not bundled. [region] adds that region's days.
  Future<List<CalendarDate>?> datesFor(
    String countryCode,
    int year, {
    String? region,
  }) async {
    final String code = countryCode.toUpperCase();
    if (!(await bundledCodes()).contains(code)) return null;

    final String raw;
    try {
      raw = await rootBundle.loadString('$_dir/$code.json');
    } on Object {
      // A missing asset throws FlutterError, an Error, not an Exception.
      return null;
    }

    final Object? parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) return null;
    final Object? dates = parsed['$year'];
    if (dates is! List<dynamic>) return null;
    return <CalendarDate>[
      for (final Object? d in dates)
        if (d is String) CalendarDate.parse(d),
      if (region != null) ...await _regionalDates(code, region, year),
    ];
  }

  Future<List<CalendarDate>> _regionalDates(
    String countryCode,
    String region,
    int year,
  ) async {
    final Object? dates = (await regionsOf(
      countryCode,
    ))[region.toUpperCase()]?['$year'];
    if (dates is! List<dynamic>) return const <CalendarDate>[];
    return <CalendarDate>[
      for (final Object? d in dates)
        if (d is String) CalendarDate.parse(d),
    ];
  }

  /// Region code to year to dates. Empty for a country without regional days.
  Future<Map<String, Map<String, dynamic>>> regionsOf(
    String countryCode,
  ) async {
    final String raw;
    try {
      raw = await rootBundle.loadString(
        '$_dir/regions/${countryCode.toUpperCase()}.json',
      );
    } on Object {
      return const <String, Map<String, dynamic>>{};
    }
    final Object? parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      return const <String, Map<String, dynamic>>{};
    }
    return <String, Map<String, dynamic>>{
      for (final MapEntry<String, dynamic> e in parsed.entries)
        if (e.value is Map<String, dynamic>)
          e.key: e.value as Map<String, dynamic>,
    };
  }

  /// Names per date: English, then local where different. Empty when none are
  /// bundled.
  Future<Map<CalendarDate, List<String>>> namesFor(String countryCode) async {
    final String raw;
    try {
      raw = await rootBundle.loadString(
        '$_dir/names/${countryCode.toUpperCase()}.json',
      );
    } on Object {
      return const <CalendarDate, List<String>>{};
    }
    final Object? parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) {
      return const <CalendarDate, List<String>>{};
    }
    return <CalendarDate, List<String>>{
      for (final MapEntry<String, dynamic> e in parsed.entries)
        if (e.value is List<dynamic>)
          CalendarDate.parse(e.key): <String>[
            for (final Object? n in e.value as List<dynamic>)
              if (n is String) n,
          ],
    };
  }
}

/// Public holidays from date.nager.at. Callers check consent and offline mode.
class NagerHolidayApi {
  const NagerHolidayApi({this.client});

  /// Null creates and closes a client per call.
  final http.Client? client;

  static const Duration _timeout = Duration(seconds: 10);

  /// Null on any failure. [region] adds that region's days.
  Future<List<CalendarDate>?> fetch(
    String countryCode,
    int year, {
    String? region,
  }) async {
    final Uri url = Uri.https(
      'date.nager.at',
      '/api/v3/PublicHolidays/$year/${countryCode.toUpperCase()}',
    );
    final http.Client c = client ?? http.Client();
    try {
      final http.Response response = await c.get(url).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final Object? parsed = jsonDecode(response.body);
      if (parsed is! List<dynamic>) return null;

      return <CalendarDate>[
        for (final Object? row in parsed)
          if (row is Map<String, dynamic> &&
              (row['global'] == true ||
                  (region != null &&
                      row['counties'] is List<dynamic> &&
                      (row['counties'] as List<dynamic>).contains(
                        region.toUpperCase(),
                      ))) &&
              row['date'] is String)
            CalendarDate.parse(row['date'] as String),
      ];
    } on Exception {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
