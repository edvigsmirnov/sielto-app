import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/theme/sage_theme.dart';
import 'package:sielto/core/ui/action_sheet.dart';
import 'package:sielto/core/ui/focus_ring.dart';

void main() {
  testWidgets('rings the focused control only under the keyboard', (
    WidgetTester tester,
  ) async {
    trackPointer();
    await tester.pumpWidget(
      MaterialApp(
        theme: SageTheme.light,
        builder: (BuildContext context, Widget? child) =>
            FocusRing(child: child!),
        home: Scaffold(
          body: Center(
            child: TextButton(onPressed: () {}, child: const Text('Go')),
          ),
        ),
      ),
    );
    final Finder layer = find
        .descendant(
          of: find.byType(FocusRing),
          matching: find.byType(CustomPaint),
        )
        .first;
    void ring(Canvas canvas) => tester
        .widget<CustomPaint>(layer)
        .foregroundPainter!
        .paint(canvas, const Size(800, 600));
    expect(ring, isNot(paints..rrect()));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ring, paints..rrect());

    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(ring, isNot(paints..rrect()));
  });
}
