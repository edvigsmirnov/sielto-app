import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';

/// How far an amount change on one occurrence reaches.
enum IncomeScope {
  /// This occurrence only; the rule stays.
  thisOne,

  /// The rule and every unreceived occurrence.
  allFuture,

  cancelled,
}

Future<IncomeScope> askIncomeScope(BuildContext context) async {
  final IncomeScope? answer = await showDialog<IncomeScope>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      backgroundColor: context.sage.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SageRadius.card),
      ),
      title: Text(
        tr('incomeScope.title'),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            tr('incomeScope.body'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: SageSpace.lg),
          ChoiceGrid(
            choices: <(String, VoidCallback)>[
              (
                tr('incomeScope.thisOne'),
                () => Navigator.of(context).pop(IncomeScope.thisOne),
              ),
              (
                tr('incomeScope.allFuture'),
                () => Navigator.of(context).pop(IncomeScope.allFuture),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return answer ?? IncomeScope.cancelled;
}
