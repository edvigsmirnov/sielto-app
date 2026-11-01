import 'package:easy_localization/easy_localization.dart';
import 'package:sielto/core/db/repositories/category_repository.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/categories/category_colors.dart';

/// Categories written at Space creation, with icons, colours and default types.
List<StarterCategory> starterCategories() => <StarterCategory>[
  (
    key: 'rent',
    title: tr('starterCategory.rent'),
    icon: '🏠',
    color: categoryPalette[1],
    type: ExpenseType.mandatory,
  ),
  (
    key: 'loans',
    title: tr('starterCategory.loans'),
    icon: '💳',
    color: categoryPalette[5],
    type: ExpenseType.mandatory,
  ),
  (
    key: 'utilities',
    title: tr('starterCategory.utilities'),
    icon: '💡',
    color: categoryPalette[4],
    type: ExpenseType.mandatory,
  ),
  (
    key: 'internet',
    title: tr('starterCategory.internet'),
    icon: '📱',
    color: categoryPalette[8],
    type: ExpenseType.mandatory,
  ),
  (
    key: 'flexible',
    title: tr('starterCategory.flexible'),
    icon: '🛒',
    color: categoryPalette[0],
    type: ExpenseType.variable,
  ),
];
