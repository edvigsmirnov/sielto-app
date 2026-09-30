import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Device-local holiday cache. Not synced; rows are kept indefinitely.
class HolidayRepository {
  HolidayRepository({required this.db, required this.clock});

  final AppDatabase db;
  final SpaceClock clock;

  /// Null when nothing is cached; empty is a valid cached result.
  Future<List<CalendarDate>?> cached(String countryCode, int year) async {
    final HolidayCacheData? row = await _row(countryCode, year);
    if (row == null) return null;
    return _decode(row.holidayDates);
  }

  Future<bool> has(String countryCode, int year) async =>
      await _row(countryCode, year) != null;

  /// Upserts on `(country, year)`.
  Future<void> store(
    String countryCode,
    int year,
    List<CalendarDate> dates,
  ) async {
    final String code = countryCode.toUpperCase();
    final String encoded = jsonEncode(<String>[
      for (final CalendarDate d in dates) d.toIso(),
    ]);
    final HolidayCacheData? existing = await _row(code, year);

    if (existing == null) {
      await db
          .into(db.holidayCache)
          .insert(
            HolidayCacheCompanion.insert(
              id: SyncedRepository.newId(),
              countryCode: code,
              year: year,
              holidayDates: encoded,
              fetchedAt: clock.nowUtc(),
            ),
          );
      return;
    }

    await (db.update(
      db.holidayCache,
    )..where(($HolidayCacheTable t) => t.id.equals(existing.id))).write(
      HolidayCacheCompanion(
        holidayDates: Value<String>(encoded),
        fetchedAt: Value<DateTime>(clock.nowUtc()),
      ),
    );
  }

  /// Every cached year for one country.
  Future<Set<CalendarDate>> allFor(String countryCode) async {
    final List<HolidayCacheData> rows =
        await (db.select(db.holidayCache)..where(
              ($HolidayCacheTable t) =>
                  t.countryCode.equals(countryCode.toUpperCase()),
            ))
            .get();
    return <CalendarDate>{
      for (final HolidayCacheData row in rows) ..._decode(row.holidayDates),
    };
  }

  Future<HolidayCacheData?> _row(String countryCode, int year) =>
      (db.select(db.holidayCache)..where(
            ($HolidayCacheTable t) =>
                t.countryCode.equals(countryCode.toUpperCase()) &
                t.year.equals(year),
          ))
          .getSingleOrNull();

  /// A malformed row reads as empty.
  List<CalendarDate> _decode(String raw) {
    final Object? parsed = jsonDecode(raw);
    if (parsed is! List<dynamic>) return const <CalendarDate>[];
    return <CalendarDate>[
      for (final Object? d in parsed)
        if (d is String) CalendarDate.parse(d),
    ];
  }
}

/// User-added non-working days, per device.
class CustomNonWorkingDayRepository {
  CustomNonWorkingDayRepository({required this.db, required this.clock});

  final AppDatabase db;
  final SpaceClock clock;

  /// Oldest first. Days without a country apply to every country.
  Future<List<CustomNonWorkingDay>> forCountry(String? countryCode) async {
    final List<CustomNonWorkingDay> rows = await all();
    return rows
        .where(
          (CustomNonWorkingDay d) =>
              d.countryCode == null ||
              (countryCode != null &&
                  d.countryCode!.toUpperCase() == countryCode.toUpperCase()),
        )
        .toList();
  }

  Future<List<CustomNonWorkingDay>> all() =>
      (db.select(db.customNonWorkingDays)
            ..orderBy(<OrderClauseGenerator<$CustomNonWorkingDaysTable>>[
              ($CustomNonWorkingDaysTable t) =>
                  OrderingTerm(expression: t.date),
            ]))
          .get();

  Stream<List<CustomNonWorkingDay>> watchAll() =>
      (db.select(db.customNonWorkingDays)
            ..orderBy(<OrderClauseGenerator<$CustomNonWorkingDaysTable>>[
              ($CustomNonWorkingDaysTable t) =>
                  OrderingTerm(expression: t.date),
            ]))
          .watch();

  /// Returns the existing row for the same date and country.
  Future<CustomNonWorkingDay> add({
    required CalendarDate date,
    String? title,
    String? countryCode,
  }) async {
    final String? code = countryCode?.toUpperCase();
    final CustomNonWorkingDay? existing = await _on(date, code);
    if (existing != null) return existing;

    return db
        .into(db.customNonWorkingDays)
        .insertReturning(
          CustomNonWorkingDaysCompanion.insert(
            id: SyncedRepository.newId(),
            date: date,
            title: Value<String?>(title?.trim().isEmpty ?? true ? null : title),
            countryCode: Value<String?>(code),
            createdAt: clock.nowUtc(),
          ),
        );
  }

  /// Hard delete: the table is not synced.
  Future<int> remove(String id) => (db.delete(
    db.customNonWorkingDays,
  )..where(($CustomNonWorkingDaysTable t) => t.id.equals(id))).go();

  Future<CustomNonWorkingDay?> _on(CalendarDate date, String? countryCode) =>
      (db.select(db.customNonWorkingDays)..where(
            ($CustomNonWorkingDaysTable t) => countryCode == null
                ? t.date.equals(date.toIso()) & t.countryCode.isNull()
                : t.date.equals(date.toIso()) &
                      t.countryCode.equals(countryCode),
          ))
          .getSingleOrNull();
}
