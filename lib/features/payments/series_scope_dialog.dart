import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/domain/value/calendar_date.dart';

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
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: SageSpace.lg),
          ChoiceGrid(
            destructive: isDestructive,
            choices: <(String, VoidCallback)>[
              for (final SeriesScope scope in scopes)
                (
                  tr('series.${scope.name}'),
                  () => Navigator.of(context).pop(scope),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  return answer ?? SeriesScope.cancelled;
}

/// Which other dates of a series take the same paid or received status.
enum StatusScope { thisOne, earlier, later, all, cancelled }

extension StatusScopeReach on StatusScope {
  /// Whether an occurrence on [date] follows one changed on [pivot].
  bool reaches(CalendarDate date, CalendarDate pivot) => switch (this) {
    StatusScope.earlier => !date.isAfter(pivot),
    StatusScope.later => !date.isBefore(pivot),
    StatusScope.all => true,
    StatusScope.thisOne || StatusScope.cancelled => false,
  };
}

/// [titleKey] names the new status, such as `statusScope.paid`.
Future<StatusScope> askStatusScope(
  BuildContext context, {
  required String titleKey,
  String? bodyKey,
}) async {
  final StatusScope? answer = await showDialog<StatusScope>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: context.sage.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      title: Text(
        tr(titleKey),
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (bodyKey != null) ...<Widget>[
            Text(
              tr(bodyKey),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: SageSpace.lg),
          ],
          ChoiceGrid(
            choices: <(String, VoidCallback)>[
              for (final StatusScope scope in <StatusScope>[
                StatusScope.thisOne,
                StatusScope.earlier,
                StatusScope.later,
                StatusScope.all,
              ])
                (
                  tr('statusScope.${scope.name}'),
                  () => Navigator.of(context).pop(scope),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  return answer ?? StatusScope.cancelled;
}
