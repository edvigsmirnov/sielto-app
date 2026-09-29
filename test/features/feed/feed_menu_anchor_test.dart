import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/feed/feed_menu.dart';

/// The quick-add bubble opens above the FAB.
void main() {
  const int itemCount = 3;

  /// A Scaffold with a bottom-right FAB opening [itemCount] items through
  /// [quickAddAnchor].
  Future<Rect> openMenuAndMeasure(WidgetTester tester) async {
    final GlobalKey fabKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: Builder(
            builder: (BuildContext context) => FloatingActionButton(
              key: fabKey,
              onPressed: () => showMenu<int>(
                context: context,
                position: quickAddAnchor(context, fabKey, itemCount: itemCount),
                items: <PopupMenuEntry<int>>[
                  for (int i = 0; i < itemCount; i++)
                    PopupMenuItem<int>(
                      value: i,
                      height: quickAddItemHeight,
                      child: Text('item $i'),
                    ),
                ],
              ),
              child: const Icon(Icons.add),
            ),
          ),
          body: const SizedBox.expand(),
        ),
      ),
    );

    await tester.tap(find.byKey(fabKey));
    await tester.pumpAndSettle();

    expect(find.text('item 0'), findsOneWidget);

    // Item rects stand in for the bubble, whose own rect is animated.
    Rect bounds = tester.getRect(find.text('item 0'));
    for (int i = 1; i < itemCount; i++) {
      bounds = bounds.expandToInclude(tester.getRect(find.text('item $i')));
    }
    return bounds;
  }

  testWidgets('the bubble sits above the FAB, not at the top of the screen', (
    WidgetTester tester,
  ) async {
    final Rect menu = await openMenuAndMeasure(tester);
    final Rect fab = tester.getRect(find.byType(FloatingActionButton));
    final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(
      menu.bottom,
      lessThanOrEqualTo(fab.top),
      reason: 'the bubble must not overlap the button it opened from',
    );

    expect(
      menu.top,
      greaterThan(screen.height / 2),
      reason: 'the bubble belongs to a FAB in the bottom half of the screen',
    );
  });

  testWidgets('the bubble is right-aligned with the FAB', (
    WidgetTester tester,
  ) async {
    final Rect menu = await openMenuAndMeasure(tester);
    final Rect fab = tester.getRect(find.byType(FloatingActionButton));

    // Grows leftwards from a button near the right edge.
    expect(menu.right, lessThanOrEqualTo(fab.right));
    expect(menu.left, lessThan(fab.left));
  });
}
