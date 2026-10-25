import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/ui/dialogs.dart';

/// How far an amount change on one occurrence reaches.
enum IncomeScope {
  /// This occurrence only; the rule stays.
  thisOne,

  /// The rule and every unreceived occurrence.
  allFuture,

  cancelled,
}

Future<IncomeScope> askIncomeScope(BuildContext context) async =>
    await choiceDialog<IncomeScope>(
      context,
      title: tr('incomeScope.title'),
      body: tr('incomeScope.body'),
      choices: <(String, IncomeScope)>[
        for (final IncomeScope scope in <IncomeScope>[
          IncomeScope.thisOne,
          IncomeScope.allFuture,
        ])
          (tr('incomeScope.${scope.name}'), scope),
      ],
    ) ??
    IncomeScope.cancelled;
