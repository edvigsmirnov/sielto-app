import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:sielto/domain/value/calendar_date.dart';

/// Bundled public holidays, nationwide only. Must cover
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

  /// Null when not bundled.
  Future<List<CalendarDate>?> datesFor(String countryCode, int year) async {
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
    ];
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

  /// Null on any failure.
  Future<List<CalendarDate>?> fetch(String countryCode, int year) async {
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
              row['global'] == true &&
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
