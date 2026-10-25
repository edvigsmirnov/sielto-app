import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/format/money_format.dart';
import 'package:sielto/core/ui/form_fields.dart';

/// "Set current balance". Paid expenses dated on or before the snapshot day
/// are excluded from the walk.
Future<void> showBalanceSheet(
  BuildContext context,
  WidgetRef ref, {
  required Space space,
  required MoneyFormat money,
}) => showAmountSheet(
  context,
  title: tr('balance.sheetTitle'),
  body: tr('balance.sheetBody'),
  symbol: money.symbol,
  initial: space.manualBalance,
  onSave: (Decimal? value) =>
      ref.read(repositoriesProvider).spaces.setManualBalance(space.id, value!),
);
