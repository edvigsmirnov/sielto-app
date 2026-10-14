import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/features/feed/feed_columns.dart';

void main() {
  test('widths and hidden columns survive a round trip', () {
    final FeedColumnLayout layout = const FeedColumnLayout()
        .withWidth(FeedColumn.note, 260)
        .toggled(FeedColumn.kind);
    final FeedColumnLayout back = FeedColumnLayout.decode(layout.encode());
    expect(back, layout);
    expect(back.widthOf(FeedColumn.note), 260);
    expect(back.widthOf(FeedColumn.date), FeedColumn.date.initialWidth);
    expect(back.shown, isNot(contains(FeedColumn.kind)));
  });

  test('widths stay within bounds', () {
    final FeedColumnLayout layout = const FeedColumnLayout()
        .withWidth(FeedColumn.note, 4)
        .withWidth(FeedColumn.amount, 9000);
    expect(layout.widthOf(FeedColumn.note), FeedColumn.minWidth);
    expect(layout.widthOf(FeedColumn.amount), FeedColumn.maxWidth);
  });

  test('a damaged setting falls back to the defaults', () {
    expect(FeedColumnLayout.decode('{"widths": 3'), const FeedColumnLayout());
    expect(FeedColumnLayout.decode('[1]'), const FeedColumnLayout());
  });

  test('a column fits only the room beside the others', () {
    const FeedColumnLayout layout = FeedColumnLayout();
    const double width = 1000;
    final double room = layout.roomFor(FeedColumn.note, width);
    final FeedColumnLayout wider = layout.withWidth(FeedColumn.note, room);
    expect(wider.shownIn(width), layout.shownIn(width));
    expect(
      layout
          .withWidth(FeedColumn.note, room + 1)
          .shownIn(width)
          .contains(FeedColumn.note),
      isFalse,
    );
  });
}
