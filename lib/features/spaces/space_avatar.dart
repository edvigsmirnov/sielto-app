import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

/// Disc with the Space's initial. Colour derived from the id.
class SpaceAvatar extends StatelessWidget {
  const SpaceAvatar({
    required this.spaceId,
    required this.title,
    this.size = 42,
    this.highlighted = false,
    super.key,
  });

  final String spaceId;
  final String title;
  final double size;

  /// The open Space gets a ring.
  final bool highlighted;

  static const List<Color> _palette = <Color>[
    Color(0xFF6F9A74),
    Color(0xFFCB8B52),
    Color(0xFF6E8FA8),
    Color(0xFF8A7BA8),
    Color(0xFF5F7D7A),
    Color(0xFFA8748A),
  ];

  /// Same colour on every platform and version, unlike `hashCode`.
  static Color colorOf(String spaceId) =>
      _palette[spaceId.codeUnits.fold(
            0,
            (int hash, int unit) => (hash * 31 + unit) & 0x7fffffff,
          ) %
          _palette.length];

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final String initial = title.trim().isEmpty
        ? '?'
        : title.trim().characters.first.toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorOf(spaceId),
        shape: BoxShape.circle,
        border: highlighted ? Border.all(color: sage.ink, width: 2) : null,
      ),
      child: Text(
        initial,
        style:
            (size >= 48
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.titleSmall)
                ?.copyWith(color: Colors.white),
      ),
    );
  }
}
