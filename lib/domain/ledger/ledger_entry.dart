import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';

/// A payment or an income on the ledger.
@immutable
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.date,
    required this.amount,
    required this.isIncome,
    this.sortOrder = 0,
    this.expenseType,
    this.isPaid = false,
    this.title = '',
  });

  final String id;
  final CalendarDate date;

  /// Always positive; direction comes from [isIncome].
  final Decimal amount;

  final bool isIncome;

  /// Manual position within the day. Decides which entries fall past the cutoff.
  final int sortOrder;

  /// Null for incomes.
  final ExpenseType? expenseType;

  final bool isPaid;
  final String title;

  bool get isExpense => !isIncome;

  bool get isMandatory => expenseType == ExpenseType.mandatory;

  @override
  String toString() =>
      'LedgerEntry($date ${isIncome ? '+' : '-'}$amount $title)';
}

/// Date, then incomes before expenses, then manual order, then id.
int compareLedgerEntries(LedgerEntry a, LedgerEntry b) {
  final int byDate = a.date.compareTo(b.date);
  if (byDate != 0) return byDate;

  if (a.isIncome != b.isIncome) return a.isIncome ? -1 : 1;

  final int byOrder = a.sortOrder.compareTo(b.sortOrder);
  if (byOrder != 0) return byOrder;

  return a.id.compareTo(b.id);
}
