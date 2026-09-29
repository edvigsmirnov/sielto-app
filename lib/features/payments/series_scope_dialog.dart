import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// How far an edit to one occurrence of a series reaches.
enum SeriesScope {
  /// This occurrence only.
  thisOne,

  /// This and every later occurrence, except paid ones.
  allFuture,

  /// Every occurrence, except paid ones.
  wholeSeries,

  cancelled,
}

Future<SeriesScope> askSeriesScope(BuildContext context) =>
    _askScope(context, title: tr('series.title'), body: tr('series.body'));

/// Whole series or from this occurrence on. Single-occurrence delete is in the
/// app bar.
Future<SeriesScope> askSeriesDeleteScope(BuildContext context) => _askScope(
  context,
  title: tr('series.deleteTitle'),
  body: tr('series.deleteBody'),
  scopes: const <SeriesScope>[SeriesScope.allFuture, SeriesScope.wholeSeries],
  isDestructive: true,
);

Future<SeriesScope> _askScope(
  BuildContext context, {
  required String title,
  required String body,
  List<SeriesScope> scopes = const <SeriesScope>[
    SeriesScope.thisOne,
    SeriesScope.allFuture,
    SeriesScope.wholeSeries,
  ],
  bool isDestructive = false,
}) async {
  final SeriesScope? answer = await showDialog<SeriesScope>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: context.sage.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      content: Text(body, style: Theme.of(context).textTheme.bodyMedium),
      actions: <Widget>[
        for (final SeriesScope scope in scopes)
          TextButton(
            onPressed: () => Navigator.of(context).pop(scope),
            style: isDestructive
                ? TextButton.styleFrom(foregroundColor: context.sage.danger)
                : null,
            child: Text(tr('series.${scope.name}')),
          ),
      ],
    ),
  );
  return answer ?? SeriesScope.cancelled;
}
