import 'package:flutter/widgets.dart';

/// Offered category icons. Any short string is allowed.
const List<String> categoryIconChoices = <String>[
  '🛒',
  '🏠',
  '💡',
  '💳',
  '🚌',
  '🍽️',
  '💊',
  '👕',
  '🎬',
  '📱',
  '🎓',
  '🎁',
  '✈️',
  '🐾',
  '🔧',
  '💧',
];

/// Colour emoji on Linux. Emoji-only text: it has spaces too.
const List<String> emojiFonts = <String>['Noto Color Emoji'];

/// Null when the stored icon is not drawable.
String? sanitiseCategoryIcon(String? icon) {
  final String? trimmed = icon?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  // At most two grapheme clusters.
  return trimmed.characters.length > 2 ? null : trimmed;
}
