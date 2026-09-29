import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/features/analytics/analytics_parts.dart';

/// A fast right swipe pops the route; a left one does not.
void main() {
  Future<void> pumpPushed(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SageTheme.light,
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext _) =>
                    const SwipeBack(child: Center(child: Text('level 2'))),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a fast right swipe pops the route', (WidgetTester tester) async {
    await pumpPushed(tester);
    expect(find.text('level 2'), findsOneWidget);

    await tester.fling(find.text('level 2'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('level 2'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a left swipe does not pop', (WidgetTester tester) async {
    await pumpPushed(tester);

    await tester.fling(find.text('level 2'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('level 2'), findsOneWidget);
  });
}
