import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/calendar/day_marks.dart';

/// The high-load threshold (spec 8.1).
void main() {
  Decimal d(String v) => Decimal.parse(v);

  List<Decimal> of(List<String> values) => values.map(d).toList();

  test('too little history sets no threshold', () {
    // Better no mark than a mark derived from three figures.
    expect(highLoadThreshold(of(<String>['10', '20', '30'])), isNull);
    expect(highLoadThreshold(const <Decimal>[]), isNull);
  });

  test('an odd sample takes the middle figure', () {
    // Median 40, so the bar is 60.
    expect(
      highLoadThreshold(of(<String>['10', '20', '30', '40', '50', '60', '70'])),
      d('60'),
    );
  });

  test('an even sample averages the two middle figures', () {
    // 30 and 40 -> 35, so the bar is 52.50.
    expect(
      highLoadThreshold(of(<String>['10', '20', '30', '40', '50', '60'])),
      d('52.50'),
    );
  });

  test('order does not matter', () {
    expect(
      highLoadThreshold(of(<String>['70', '10', '50', '30', '20', '60', '40'])),
      d('60'),
    );
  });

  test('days with nothing spent are left out of the median', () {
    // The whole point: a Space that records on eight days a month has a
    // median of zero across the calendar, and every day would clear 1.5x zero.
    final List<Decimal> sparse = <Decimal>[
      ...of(<String>['10', '20', '30', '40', '50', '60']),
      ...List<Decimal>.filled(40, Decimal.zero),
    ];
    expect(highLoadThreshold(sparse), d('52.50'));
  });

  test('zeroes alone never clear the bar they would set', () {
    expect(highLoadThreshold(List<Decimal>.filled(30, Decimal.zero)), isNull);
  });

  test('the threshold is exact money, not a float', () {
    // 0.01 -> median 0.015 -> 0.0225, rounded to the cent rather than carried
    // as a binary fraction.
    expect(
      highLoadThreshold(
        of(<String>['0.01', '0.01', '0.01', '0.02', '0.02', '0.02']),
      ),
      d('0.02'),
    );
  });
}
