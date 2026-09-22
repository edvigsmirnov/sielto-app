import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';

void main() {
  test(
    'Back zooms out the way a tap zoomed in, and the switcher clears it',
    () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final CalendarViewController scales = c.read(
        calendarViewProvider.notifier,
      );

      scales.select(CalendarView.year);
      scales.open(CalendarView.month);
      scales.open(CalendarView.day);
      expect(scales.back(), isTrue);
      expect(c.read(calendarViewProvider), CalendarView.month);
      expect(scales.back(), isTrue);
      expect(c.read(calendarViewProvider), CalendarView.year);
      expect(scales.back(), isFalse);

      scales.open(CalendarView.month);
      scales.select(CalendarView.week);
      expect(scales.canGoBack(), isFalse);
    },
  );
}
