import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/settings_providers.dart';

/// The Feed table's columns besides the title, left to right.
enum FeedColumn {
  date(96),
  category(140),
  kind(100),
  note(170),
  amount(116),
  left(124);

  const FeedColumn(this.initialWidth);

  final double initialWidth;

  static const double minWidth = 56;
  static const double maxWidth = 420;

  /// Its edge to drag sits on the title's side.
  bool get dragsLeftEdge => this != FeedColumn.date;

  bool get endAligned => this == FeedColumn.amount || this == FeedColumn.left;
}

/// Widths and hidden columns, kept on this device.
@immutable
class FeedColumnLayout {
  const FeedColumnLayout({
    this.widths = const <FeedColumn, double>{},
    this.hidden = const <FeedColumn>{},
  });

  factory FeedColumnLayout.decode(String? stored) {
    if (stored == null) return const FeedColumnLayout();
    try {
      final Map<String, dynamic> json =
          jsonDecode(stored) as Map<String, dynamic>;
      final Map<String, dynamic> widths =
          json['widths'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final List<dynamic> hidden =
          json['hidden'] as List<dynamic>? ?? const <dynamic>[];
      return FeedColumnLayout(
        widths: <FeedColumn, double>{
          for (final FeedColumn c in FeedColumn.values)
            if (widths[c.name] case final num w) c: w.toDouble(),
        },
        hidden: <FeedColumn>{
          for (final FeedColumn c in FeedColumn.values)
            if (hidden.contains(c.name)) c,
        },
      );
    } on FormatException {
      return const FeedColumnLayout();
    } on TypeError {
      return const FeedColumnLayout();
    }
  }

  final Map<FeedColumn, double> widths;
  final Set<FeedColumn> hidden;

  double widthOf(FeedColumn c) => widths[c] ?? c.initialWidth;

  List<FeedColumn> get shown => <FeedColumn>[
    for (final FeedColumn c in FeedColumn.values)
      if (!hidden.contains(c)) c,
  ];

  /// The title keeps at least this much when columns are dropped.
  static const double titleMin = 160;

  /// What is left out first when the table is too narrow; never the amount.
  static const List<FeedColumn> _dropOrder = <FeedColumn>[
    FeedColumn.note,
    FeedColumn.category,
    FeedColumn.kind,
    FeedColumn.left,
    FeedColumn.date,
  ];

  /// The columns shown in [width], dropping in [_dropOrder] what does not
  /// fit beside the title.
  List<FeedColumn> shownIn(double width) {
    final List<FeedColumn> fit = shown;
    double need() =>
        titleMin +
        fit.fold<double>(0, (double sum, FeedColumn c) => sum + widthOf(c));
    for (final FeedColumn c in _dropOrder) {
      if (need() <= width) break;
      fit.remove(c);
    }
    return fit;
  }

  FeedColumnLayout withWidth(FeedColumn c, double width) => FeedColumnLayout(
    widths: <FeedColumn, double>{
      ...widths,
      c: width.clamp(FeedColumn.minWidth, FeedColumn.maxWidth),
    },
    hidden: hidden,
  );

  FeedColumnLayout toggled(FeedColumn c) => FeedColumnLayout(
    widths: widths,
    hidden: hidden.contains(c)
        ? (Set<FeedColumn>.of(hidden)..remove(c))
        : <FeedColumn>{...hidden, c},
  );

  String encode() => jsonEncode(<String, Object>{
    'widths': <String, double>{
      for (final MapEntry<FeedColumn, double> e in widths.entries)
        e.key.name: e.value,
    },
    'hidden': <String>[for (final FeedColumn c in hidden) c.name],
  });

  @override
  bool operator ==(Object other) =>
      other is FeedColumnLayout &&
      mapEquals(other.widths, widths) &&
      setEquals(other.hidden, hidden);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      widths.entries.map(
        (MapEntry<FeedColumn, double> e) => Object.hash(e.key, e.value),
      ),
    ),
    Object.hashAllUnordered(hidden),
  );
}

class FeedColumnsController extends Notifier<FeedColumnLayout> {
  @override
  FeedColumnLayout build() =>
      FeedColumnLayout.decode(ref.watch(localSettingsProvider).feedColumns);

  /// While dragging; [save] keeps it.
  void resize(FeedColumn c, double width) => state = state.withWidth(c, width);

  Future<void> toggle(FeedColumn c) async {
    state = state.toggled(c);
    await save();
  }

  Future<void> reset() async {
    state = const FeedColumnLayout();
    await save();
  }

  Future<void> save() =>
      ref.read(localSettingsProvider).setFeedColumns(state.encode());
}

final NotifierProvider<FeedColumnsController, FeedColumnLayout>
feedColumnsProvider = NotifierProvider<FeedColumnsController, FeedColumnLayout>(
  FeedColumnsController.new,
);
