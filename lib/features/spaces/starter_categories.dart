import 'package:easy_localization/easy_localization.dart';
import 'package:meta/meta.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/category_colors.dart';

/// One of the categories a new Space starts with.
@immutable
class StarterCategory {
  const StarterCategory({
    required this.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.expenseType,
  });

  /// Stable across languages; the title is shown from it until a rename.
  final String key;
  final String title;
  final String icon;
  final String color;
  final ExpenseType expenseType;
}

/// The category set written at Space creation (spec 7).
///
/// Each carries its key, and is shown in the reader's language until it is
/// renamed; the stored title is the creation-language fallback. A renamed
/// category is user data and shows exactly as typed.
///
/// They arrive with an icon, a colour and a default type rather than as bare
/// names — a starter set exists to show what a filled-in category looks like,
/// and five identical grey rows teach nothing.
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
