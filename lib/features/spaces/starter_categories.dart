import 'package:easy_localization/easy_localization.dart';
import 'package:meta/meta.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/category_colors.dart';

@immutable
class StarterCategory {
  const StarterCategory({
    required this.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.expenseType,
  });

  /// Stable across languages; see `Category.shownTitle`.
  final String key;
  final String title;
  final String icon;
  final String color;
  final ExpenseType expenseType;
}

/// Categories written at Space creation, with icons, colours and default types.
List<StarterCategory> starterCategories() => <StarterCategory>[
  StarterCategory(
    key: 'rent',
    title: tr('starterCategory.rent'),
    icon: '🏠',
    color: categoryPalette[1],
    expenseType: ExpenseType.mandatory,
  ),
  StarterCategory(
    key: 'loans',
    title: tr('starterCategory.loans'),
    icon: '💳',
    color: categoryPalette[5],
    expenseType: ExpenseType.mandatory,
  ),
  StarterCategory(
    key: 'utilities',
    title: tr('starterCategory.utilities'),
    icon: '💡',
    color: categoryPalette[4],
    expenseType: ExpenseType.mandatory,
  ),
  StarterCategory(
    key: 'internet',
    title: tr('starterCategory.internet'),
    icon: '📱',
    color: categoryPalette[8],
    expenseType: ExpenseType.mandatory,
  ),
  StarterCategory(
    key: 'flexible',
    title: tr('starterCategory.flexible'),
    icon: '🛒',
    color: categoryPalette[0],
    expenseType: ExpenseType.variable,
  ),
];
