import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/sage_widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SageTheme.light,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }

  Widget choice(List<String> labels) => SegmentedChoice<String>(
    values: labels,
    selected: labels.first,
    labelOf: (String l) => l,
    onChanged: (_) {},
  );

  testWidgets('short labels sit in one row', (WidgetTester t) async {
    await pump(t, choice(<String>['One', 'Two', 'Three']));
    expect(
      t.getTopLeft(find.text('One')).dy,
      t.getTopLeft(find.text('Two')).dy,
    );
  });

  testWidgets('labels too long for a row stack', (WidgetTester t) async {
    await pump(
      t,
      choice(<String>['По дате', 'Текущий период', 'Следующий период']),
    );
    expect(
      t.getTopLeft(find.text('Следующий период')).dy,
      greaterThan(t.getTopLeft(find.text('Текущий период')).dy),
    );
  });

  testWidgets('an amount stops at 12 whole digits', (WidgetTester t) async {
    final TextEditingController c = TextEditingController();
    addTearDown(c.dispose);
    await pump(t, MoneyField(controller: c, symbol: '€'));
    await t.enterText(find.byType(TextField), '123 456 789 012,34');
    expect(c.text, '123 456 789 012,34');
    await t.enterText(find.byType(TextField), '1234567890123');
    expect(c.text, '123 456 789 012,34');
  });
}
