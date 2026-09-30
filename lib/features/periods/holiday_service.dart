import 'package:meta/meta.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/holiday_repository.dart';
import 'package:sielto/core/holidays/holiday_source.dart';
import 'package:sielto/domain/schedule/working_days.dart';
import 'package:sielto/domain/value/calendar_date.dart';

@immutable
class ResolvedCalendar {
  const ResolvedCalendar({
    required this.calendar,
    required this.missingYears,
    required this.countryCode,
  });

  final WorkingDayCalendar calendar;

  /// Years without holiday data. Non-empty: windows may still narrow.
  final Set<int> missingYears;

  /// Null when no country applies.
  final String? countryCode;

  bool get isComplete => missingYears.isEmpty;
}

/// The holiday cache row: the region when one is chosen, else the country.
String cacheKey(String countryCode, String? region) => region ?? countryCode;

/// Builds the working-day calendar. Holidays come from the cache, then the
/// bundle, then the network. Missing years are reported, not hidden.
class HolidayService {
  const HolidayService({
    required this.holidays,
    required this.customDays,
    this.bundle = const HolidayBundle(),
    this.api = const NagerHolidayApi(),
  });

  final HolidayRepository holidays;
  final CustomNonWorkingDayRepository customDays;
  final HolidayBundle bundle;
  final NagerHolidayApi api;

  /// Null [countryCode] skips holidays. [years] covers the materialisation span.
  /// [mayFetch] already combines consent and offline mode.
  Future<ResolvedCalendar> resolve({
    required String? countryCode,
    required Set<int> years,
    required bool mayFetch,
    String? region,
  }) async {
    final Set<CalendarDate> custom = <CalendarDate>{
      for (final CustomNonWorkingDay d in await customDays.forCountry(
        countryCode,
      ))
        d.date,
    };

    if (countryCode == null) {
      return ResolvedCalendar(
        calendar: WorkingDayCalendar(customNonWorkingDays: custom),
        missingYears: const <int>{},
        countryCode: null,
      );
    }

    final String key = cacheKey(countryCode, region);
    final Set<int> missing = <int>{};
    for (final int year in years) {
      if (await holidays.has(key, year)) continue;

      final List<CalendarDate>? bundled = await bundle.datesFor(
        countryCode,
        year,
        region: region,
      );
      if (bundled != null) {
        await holidays.store(key, year, bundled);
        continue;
      }

      if (!mayFetch) {
        missing.add(year);
        continue;
      }

      final List<CalendarDate>? fetched = await api.fetch(
        countryCode,
        year,
        region: region,
      );
      if (fetched == null) {
        missing.add(year);
        continue;
      }
      await holidays.store(key, year, fetched);
    }

    return ResolvedCalendar(
      calendar: WorkingDayCalendar(
        holidays: await holidays.allFor(key),
        customNonWorkingDays: custom,
      ),
      missingYears: missing,
      countryCode: countryCode,
    );
  }
}
