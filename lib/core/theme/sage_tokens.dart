import 'package:flutter/material.dart';

/// Sage design tokens. Dark values are derived by role, not inverted.
/// Invariants are checked in test/core/theme/sage_theme_test.dart.
@immutable
class SageColors extends ThemeExtension<SageColors> {
  const SageColors({
    required this.canvas,
    required this.surface,
    required this.card,
    required this.cardRaised,
    required this.ink,
    required this.inkHeading,
    required this.inkSecondary,
    required this.inkLabel,
    required this.hairline,
    required this.border,
    required this.accent,
    required this.accentStrong,
    required this.accentFill,
    required this.accentOn,
    required this.accentTint,
    required this.accentTintAlt,
    required this.danger,
    required this.dangerTint,
    required this.warning,
    required this.warningAccent,
    required this.warningTint,
    required this.sand,
    required this.sandTint,
  });

  /// Outer canvas, sheet backdrop.
  final Color canvas;

  /// App background.
  final Color surface;

  /// Cards, inputs, rows.
  final Color card;

  /// Raised surface. Equals [card] on light.
  final Color cardRaised;

  /// Primary text.
  final Color ink;

  /// Section headings.
  final Color inkHeading;

  /// Secondary text.
  final Color inkSecondary;

  /// Field labels. 4.5:1 at 10px in both themes.
  final Color inkLabel;

  /// Row dividers.
  final Color hairline;

  /// Input and segment borders.
  final Color border;

  /// Solid fills: filled buttons, switches, FAB, selected segment, today.
  final Color accent;

  /// Positive figures, primary action text, green coverage dot.
  final Color accentStrong;

  /// Fill behind accent text. Pair with [accentOn] on light and [accentStrong] on
  /// dark.
  final Color accentFill;

  /// Foreground on [accent].
  final Color accentOn;

  /// Selected-card background.
  final Color accentTint;

  /// Icon chips, secondary tint.
  final Color accentTintAlt;

  /// Overspend, destructive actions, red coverage dot.
  final Color danger;

  /// Overdue section background.
  final Color dangerTint;

  /// Warning text.
  final Color warning;

  /// Orange coverage dot. Same in both themes.
  final Color warningAccent;

  /// Warning wash.
  final Color warningTint;

  /// Income-uncertainty band, neutral markers.
  final Color sand;

  /// Band fill.
  final Color sandTint;

  static const SageColors light = SageColors(
    canvas: Color(0xFFEEF1EA),
    surface: Color(0xFFF5F7F1),
    card: Color(0xFFFFFFFF),
    cardRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF2B2F28),
    inkHeading: Color(0xFF243226),
    inkSecondary: Color(0xC72B2F28), // ink @ .78 -> 6.20:1 on canvas
    inkLabel: Color(0xAC2B2F28), // ink @ .675 -> 4.55:1 on canvas
    hairline: Color(0x142B2F28), // ink @ .08
    border: Color(0x262B2F28), // ink @ .15
    accent: SageBrand.night,
    accentStrong: Color(0xFF4C7A52),
    accentFill: SageBrand.night,
    accentOn: SageBrand.leaf,
    accentTint: Color(0xFFEEF5EC),
    accentTintAlt: Color(0xFFE6ECDF),
    danger: Color(0xFFA34B3A),
    dangerTint: Color(0xFFF7E3DE),
    warning: Color(0xFFA35A1F),
    warningAccent: Color(0xFFE29A5C),
    warningTint: Color(0xFFF7EBDD),
    sand: Color(0xFFCBB98F),
    sandTint: Color(0xFFD8C9A8),
  );

  static const SageColors dark = SageColors(
    canvas: Color(0xFF131813),
    surface: Color(0xFF171D18),
    card: Color(0xFF1E251F),
    cardRaised: Color(0xFF252D26),
    ink: Color(0xFFE3EAE0),
    inkHeading: Color(0xFFEEF3EC),
    inkSecondary: Color(0xFFA9B5A6),
    inkLabel: Color(0xFF8B9889),
    hairline: Color(0x17E3EAE0), // paper @ .09
    border: Color(0x29E3EAE0), // paper @ .16
    accent: SageBrand.leaf,
    accentStrong: Color(0xFFA8CFAD),
    accentFill: Color(0xFF2F5434),
    accentOn: SageBrand.night,
    accentTint: Color(0xFF26362A),
    accentTintAlt: Color(0xFF2B382C),
    danger: Color(0xFFDD9B8C),
    dangerTint: Color(0xFF33231E),
    warning: Color(0xFFDFA570),
    warningAccent: Color(0xFFE29A5C),
    warningTint: Color(0xFF322517),
    sand: Color(0xFFC4B189),
    sandTint: Color(0xFF2E2A1F),
  );

  @override
  SageColors copyWith({
    Color? canvas,
    Color? surface,
    Color? card,
    Color? cardRaised,
    Color? ink,
    Color? inkHeading,
    Color? inkSecondary,
    Color? inkLabel,
    Color? hairline,
    Color? border,
    Color? accent,
    Color? accentStrong,
    Color? accentFill,
    Color? accentOn,
    Color? accentTint,
    Color? accentTintAlt,
    Color? danger,
    Color? dangerTint,
    Color? warning,
    Color? warningAccent,
    Color? warningTint,
    Color? sand,
    Color? sandTint,
  }) {
    return SageColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      cardRaised: cardRaised ?? this.cardRaised,
      ink: ink ?? this.ink,
      inkHeading: inkHeading ?? this.inkHeading,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkLabel: inkLabel ?? this.inkLabel,
      hairline: hairline ?? this.hairline,
      border: border ?? this.border,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentFill: accentFill ?? this.accentFill,
      accentOn: accentOn ?? this.accentOn,
      accentTint: accentTint ?? this.accentTint,
      accentTintAlt: accentTintAlt ?? this.accentTintAlt,
      danger: danger ?? this.danger,
      dangerTint: dangerTint ?? this.dangerTint,
      warning: warning ?? this.warning,
      warningAccent: warningAccent ?? this.warningAccent,
      warningTint: warningTint ?? this.warningTint,
      sand: sand ?? this.sand,
      sandTint: sandTint ?? this.sandTint,
    );
  }

  @override
  SageColors lerp(ThemeExtension<SageColors>? other, double t) {
    if (other is! SageColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SageColors(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      card: c(card, other.card),
      cardRaised: c(cardRaised, other.cardRaised),
      ink: c(ink, other.ink),
      inkHeading: c(inkHeading, other.inkHeading),
      inkSecondary: c(inkSecondary, other.inkSecondary),
      inkLabel: c(inkLabel, other.inkLabel),
      hairline: c(hairline, other.hairline),
      border: c(border, other.border),
      accent: c(accent, other.accent),
      accentStrong: c(accentStrong, other.accentStrong),
      accentFill: c(accentFill, other.accentFill),
      accentOn: c(accentOn, other.accentOn),
      accentTint: c(accentTint, other.accentTint),
      accentTintAlt: c(accentTintAlt, other.accentTintAlt),
      danger: c(danger, other.danger),
      dangerTint: c(dangerTint, other.dangerTint),
      warning: c(warning, other.warning),
      warningAccent: c(warningAccent, other.warningAccent),
      warningTint: c(warningTint, other.warningTint),
      sand: c(sand, other.sand),
      sandTint: c(sandTint, other.sandTint),
    );
  }
}

/// Wordmark colours. Theme-independent.
abstract final class SageBrand {
  /// Wordmark background; Android `splash_background`.
  static const Color night = Color(0xFF213627);

  /// Wordmark letters.
  static const Color leaf = Color(0xFFBDC9A7);

  /// Space avatars, picked by id; the same in light and dark.
  static const List<Color> avatars = <Color>[
    Color(0xFF6F9A74),
    Color(0xFFCB8B52),
    Color(0xFF6E8FA8),
    Color(0xFF8A7BA8),
    Color(0xFF5F7D7A),
    Color(0xFFA8748A),
  ];
}

abstract final class SageRadius {
  static const double card = 14;
  static const double input = 11;
  static const double button = 12;
  static const double chip = 9;
  static const double pill = 100;
  static const double sheet = 30;
}

abstract final class SageSpace {
  /// Vertical padding of a list row.
  static const double row = 9;

  /// Horizontal content gutter.
  static const double gutter = 16;

  /// Horizontal gutter inside forms.
  static const double formGutter = 18;

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;
  static const double xl = 28;
}

extension SageColorsX on BuildContext {
  SageColors get sage => Theme.of(this).extension<SageColors>()!;
}
