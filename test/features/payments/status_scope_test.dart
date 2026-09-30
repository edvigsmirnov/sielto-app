import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/features/payments/series_scope_dialog.dart';

void main() {
  test('each status scope reaches its side of the edited date', () {
    const CalendarDate pivot = CalendarDate(2026, 5, 1);
    const List<CalendarDate> dates = <CalendarDate>[
      CalendarDate(2026, 4, 1),
      pivot,
      CalendarDate(2026, 6, 1),
    ];
    List<bool> reach(StatusScope s) => <bool>[
      for (final CalendarDate d in dates) s.reaches(d, pivot),
    ];
    expect(reach(StatusScope.thisOne), <bool>[false, false, false]);
    expect(reach(StatusScope.earlier), <bool>[true, true, false]);
    expect(reach(StatusScope.later), <bool>[false, true, true]);
    expect(reach(StatusScope.all), <bool>[true, true, true]);
  });
}
