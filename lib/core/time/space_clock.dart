import 'package:sielto/domain/value/calendar_date.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// "Today" in a Space's timezone. Never call `DateTime.now()` directly.
/// The wall clock is injectable for tests.
class SpaceClock {
  SpaceClock({required String timezone, DateTime Function()? now})
    : _location = tz.getLocation(timezone),
      _now = now ?? DateTime.now;

  /// Loads the IANA database. Call once at startup.
  static void initialize() => tz_data.initializeTimeZones();

  static bool isKnownTimezone(String timezone) {
    try {
      tz.getLocation(timezone);
      return true;
    } on tz.LocationNotFoundException {
      return false;
    }
  }

  final tz.Location _location;
  final DateTime Function() _now;

  String get timezone => _location.name;

  DateTime nowUtc() => _now().toUtc();

  /// Same wall clock in another zone. Use this, not a new [SpaceClock], to keep
  /// an injected clock.
  SpaceClock inZone(String timezone) =>
      SpaceClock(timezone: timezone, now: _now);

  CalendarDate today() => dateOf(_now());

  CalendarDate dateOf(DateTime instant) =>
      CalendarDate.fromDateTime(tz.TZDateTime.from(instant, _location));

  /// Midnight of [date] in this Space, as UTC.
  DateTime startOfDayUtc(CalendarDate date) =>
      tz.TZDateTime(_location, date.year, date.month, date.day).toUtc();

  /// Start of the next day, for half-open ranges. Adds a calendar day, not 24
  /// hours.
  DateTime endOfDayUtc(CalendarDate date) => startOfDayUtc(date.addDays(1));
}
