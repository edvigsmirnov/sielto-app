import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/categories/category_icons.dart';

/// Category colours, stored as `#rrggbb`. Not theme tokens.
const List<String> categoryPalette = <String>[
  '#8FB996',
  '#4C7A52',
  '#A34B3A',
  '#E29A5C',
  '#CBB98F',
  '#6E8FA8',
  '#8A6EA8',
  '#A86E8F',
  '#5F7D7A',
  '#9A9A6E',
];

/// Colour disc with the category icon.
class CategoryMark extends StatelessWidget {
  const CategoryMark({
    required this.color,
    required this.icon,
    this.size = 34,
    super.key,
  });

  final String? color;
  final String? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color ground = parseCategoryColor(color) ?? context.sage.sand;
    final String? glyph = sanitiseCategoryIcon(icon);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ground, shape: BoxShape.circle),
      child: glyph == null
          ? null
          : Text(glyph, style: TextStyle(fontSize: size * 0.45)),
    );
  }
}

/// Null on invalid input.
Color? parseCategoryColor(String? hex) {
  if (hex == null) return null;
  final String digits = hex.replaceFirst('#', '');
  if (digits.length != 6) return null;
  final int? value = int.tryParse(digits, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
