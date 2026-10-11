import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/settings/local_settings.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/feed/feed_model.dart';
import 'package:sielto/features/feed/feed_row.dart';

void main() {
  final MoneyFormat money = MoneyFormat(locale: 'en', currencyCode: 'EUR');

  Future<void> pumpRow(
    WidgetTester tester, {
    required String amount,
    FeedDensity density = FeedDensity.standard,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: SageTheme.light,
          home: Scaffold(
            body: FeedRowTile(
              record: FeedRecord(
                id: 'a',
                date: const CalendarDate(2026, 3, 1),
                title: 'Groceries for the week',
                amount: Decimal.parse(amount),
                isIncome: false,
                isPaid: false,
                sortOrder: 0,
                expenseType: ExpenseType.variable,
              ),
              isCovered: true,
              density: density,
              money: money,
              category: null,
              onTap: () {},
              onTogglePaid: () {},
              onDelete: () {},
              onLongPress: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a short amount shares the title line', (WidgetTester t) async {
    await pumpRow(t, amount: '12.50');
    expect(
      t.getTopLeft(find.text('€12.50')).dy,
      closeTo(t.getTopLeft(find.text('Groceries for the week')).dy, 2),
    );
  });

  testWidgets('a long amount moves under the title', (WidgetTester t) async {
    await pumpRow(t, amount: '999999999999.99');
    expect(t.takeException(), isNull);
    final Finder amount = find.text('€999,999,999,999.99');
    expect(amount, findsOneWidget);
    expect(
      t.getTopLeft(amount).dy,
      greaterThan(t.getBottomLeft(find.text('Groceries for the week')).dy - 1),
    );
  });

  testWidgets('a row is one announcement; the paid circle is a button', (
    WidgetTester t,
  ) async {
    final SemanticsHandle handle = t.ensureSemantics();
    await pumpRow(t, amount: '12.50');
    final SemanticsData row = t
        .getSemantics(find.byType(FeedRowTile))
        .getSemanticsData();
    expect(row.label, startsWith('Groceries for the week. €12.50. '));
    expect(row.hasAction(SemanticsAction.tap), isTrue);
    expect(row.hasAction(SemanticsAction.longPress), isTrue);
    expect(find.bySemanticsLabel('feed.bulk.mark.paid'), findsOneWidget);
    final SemanticsData circle = t
        .getSemantics(find.bySemanticsLabel('feed.bulk.mark.paid'))
        .getSemanticsData();
    expect(circle.hasAction(SemanticsAction.tap), isTrue);
    expect(t.getSize(find.bySemanticsLabel('feed.bulk.mark.paid')).height, 48);
    handle.dispose();
  });
}
