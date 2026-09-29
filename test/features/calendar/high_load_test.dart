import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/calendar/day_marks.dart';

void main() {
  Decimal d(String v) => Decimal.parse(v);

  List<Decimal> of(List<String> values) => values.map(d).toList();

  test('too little history sets no threshold', () {
    expect(highLoadThreshold(of(<String>['10', '20', '30'])), isNull);
    expect(highLoadThreshold(const <Decimal>[]), isNull);
  });

  test('an odd sample takes the middle figure', () {
    // Median 40, threshold 60.
    expect(
      highLoadThreshold(of(<String>['10', '20', '30', '40', '50', '60', '70'])),
      d('60'),
    );
  });

  test('an even sample averages the two middle figures', () {
    // Median 35, threshold 52.50.
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
    // Only spending days count; the median over all days would be zero.
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
    // Median 0.015, threshold 0.0225, exact.
    expect(
      highLoadThreshold(
        of(<String>['0.01', '0.01', '0.01', '0.02', '0.02', '0.02']),
      ),
      d('0.02'),
    );
  });
}
