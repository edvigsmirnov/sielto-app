import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sielto/core/format/date_format.dart';
import 'package:sielto/domain/value/calendar_date.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  const CalendarDate from = CalendarDate(2026, 10, 5);
  const CalendarDate to = CalendarDate(2026, 10, 14);

  test('a range within one month follows the locale order', () {
    expect(DateLabels('en').range(from, to), 'October 5 – 14');
    expect(DateLabels('ru').range(from, to), '5 – 14 октября');
  });

  test('another year goes after the last day', () {
    expect(
      DateLabels('en')
          .range(from, to, reference: const CalendarDate(2025, 1, 1)),
      'October 5 – 14, 2026',
    );
  });

  test('a range across months names both', () {
    expect(
      DateLabels('en').range(from, const CalendarDate(2026, 11, 2)),
      'October 5 – November 2',
    );
  });
}
