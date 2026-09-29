import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// Money as an exact decimal string. SQL cannot sum it; aggregate in Dart.
class DecimalConverter extends TypeConverter<Decimal, String>
    with JsonTypeConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromSql(String fromDb) => Decimal.parse(fromDb);

  @override
  String toSql(Decimal value) => value.toString();
}

/// A calendar day as `YYYY-MM-DD`, sortable and comparable as text.
class CalendarDateConverter extends TypeConverter<CalendarDate, String>
    with JsonTypeConverter<CalendarDate, String> {
  const CalendarDateConverter();

  @override
  CalendarDate fromSql(String fromDb) => CalendarDate.parse(fromDb);

  @override
  String toSql(CalendarDate value) => value.toIso();
}
