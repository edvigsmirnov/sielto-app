import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/domain/value/calendar_date.dart';

/// The date range the Feed renders: three months either side of today,
/// widened at the ends.
@immutable
class FeedWindow {
  const FeedWindow({required this.from, required this.to});

  /// Months added per widening.
  static const int stepMonths = 3;

  final CalendarDate from;
  final CalendarDate to;

  bool contains(CalendarDate date) => !date.isBefore(from) && !date.isAfter(to);

  FeedWindow earlier() => FeedWindow(from: from.addMonths(-stepMonths), to: to);

  FeedWindow later() => FeedWindow(from: from, to: to.addMonths(stepMonths));

  static FeedWindow around(CalendarDate today) => FeedWindow(
    from: today.addMonths(-stepMonths),
    to: today.addMonths(stepMonths),
  );
}

class FeedWindowController extends Notifier<FeedWindow> {
  @override
  FeedWindow build() =>
      FeedWindow.around(ref.watch(spaceClockProvider).today());

  void extendBackwards() => state = state.earlier();

  void extendForwards() => state = state.later();
}

final NotifierProvider<FeedWindowController, FeedWindow> feedWindowProvider =
    NotifierProvider<FeedWindowController, FeedWindow>(
      FeedWindowController.new,
    );
