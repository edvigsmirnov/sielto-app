import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

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
        style: Theme.of(context).textTheme.titleMedium,
      ),
      content: Text(
        tr('incomeScope.body'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(IncomeScope.cancelled),
          child: Text(tr('common.cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(IncomeScope.thisOne),
          child: Text(tr('incomeScope.thisOne')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(IncomeScope.allFuture),
          child: Text(tr('incomeScope.allFuture')),
        ),
      ],
    ),
  );
  return answer ?? IncomeScope.cancelled;
}
