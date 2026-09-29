import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/holidays/holiday_source.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/payments/recurrence.dart';

/// Bundled holidays, read through the real asset bundle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const HolidayBundle bundle = HolidayBundle();

  List<String> bundledCodes() {
    final Object? parsed = jsonDecode(
      File('assets/holidays/index.json').readAsStringSync(),
    );
    return <String>[
      for (final Object? c in parsed! as List<dynamic>) c! as String,
    ];
  }

  test('index.json lists a file for every code, and no extras', () {
    final List<String> codes = bundledCodes();
    expect(codes, isNotEmpty);
    for (final String code in codes) {
      expect(
        File('assets/holidays/$code.json').existsSync(),
        isTrue,
        reason: '$code is in index.json but has no dictionary file',
      );
    }

    final Set<String> onDisk = Directory('assets/holidays')
        .listSync()
        .map((FileSystemEntity e) => e.uri.pathSegments.last)
        .where((String n) => n.endsWith('.json'))
        .map((String n) => n.substring(0, n.length - 5))
        // Manifest and country-name files, not holiday data.
        .where((String n) => n != 'index' && !n.startsWith('countries'))
        .toSet();
    expect(onDisk, codes.toSet(), reason: 'index.json and the files disagree');
  });

  test('every bundled holiday has a name', () async {
    for (final String code in bundledCodes()) {
      final Map<CalendarDate, List<String>> names = await bundle.namesFor(code);
      final List<CalendarDate> dates = (await bundle.datesFor(code, 2026))!;
      for (final CalendarDate d in dates) {
        expect(names[d], isNotEmpty, reason: '$code $d has no name');
      }
    }
  });

  test('every bundled country loads through the asset bundle', () async {
    for (final String code in bundledCodes()) {
      final List<CalendarDate>? dates = await bundle.datesFor(code, 2026);
      expect(dates, isNotNull, reason: '$code did not load from assets');
      expect(dates, isNotEmpty, reason: '$code loaded but is empty');
    }
  });

  test(
    'a country outside the bundle returns null, not an empty list',
    () async {
      // Null, not empty: the caller then tries the network.
      expect(await bundle.datesFor('ZZ', 2026), isNull);
      expect(await bundle.datesFor('QQ', 2026), isNull);
    },
  );

  test('the bundled span stays ahead of the recurrence horizon', () async {
    // Bundled years must cover the recurrence horizon.
    final int needed =
        DateTime.now().year + (recurrenceHorizonMonths / 12).ceil();
    final List<CalendarDate>? dates = await bundle.datesFor('DE', needed);
    expect(
      dates,
      isNotNull,
      reason:
          'the bundle stops before $needed; regenerate it with '
          'tools/fetch_holidays.py --years',
    );
  });

  test('countries.json is a superset of the bundled codes', () async {
    final Object? parsed = jsonDecode(
      await rootBundle.loadString('assets/holidays/countries.json'),
    );
    final Set<String> offered = <String>{
      for (final Object? row in parsed! as List<dynamic>)
        (row! as Map<String, dynamic>)['code']! as String,
    };
    expect(offered, containsAll(bundledCodes()));
  });
}
