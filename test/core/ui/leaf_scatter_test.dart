import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sielto/core/ui/leaf_scatter.dart';

/// The scatter runs to its end and says so, whichever way the wind blows.
void main() {
  Future<ui.Image> blank() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFF213627), BlendMode.src);
    return recorder.endRecording().toImage(8, 8);
  }

  for (final Offset? origin in <Offset?>[null, const Offset(200, 500)]) {
    testWidgets('finishes and reports it, origin $origin', (
      WidgetTester tester,
    ) async {
      final ui.Image image = (await tester.runAsync(blank))!;
      int done = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LeafScatter(
            image: image,
            origin: origin,
            onDone: () => done++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(done, 0, reason: 'still in flight');
      await tester.pumpAndSettle();
      expect(done, 1);
      image.dispose();
    });
  }
}
