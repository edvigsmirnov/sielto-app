import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

const double sidebarBreakpoint = 960;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= sidebarBreakpoint;

const double readableWidth = 720;

/// [padding] plus the navigation bar, which an explicit ListView padding drops.
/// Below an app bar, so the status bar is left out.
EdgeInsets scrollPadding(BuildContext context, EdgeInsets padding) =>
    padding + MediaQuery.paddingOf(context).copyWith(top: 0);

/// Names a route whose page lays itself out across the whole window, wide.
const String fullWindowRoute = 'full-window';

/// Mouse and keyboard: copy says "click", right-click stands in for a long press.
bool get desktopInput => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.windows ||
  TargetPlatform.macOS => true,
  _ => false,
};

/// Centres [child] at most [maxWidth] wide.
class Readable extends StatelessWidget {
  const Readable({
    required this.child,
    this.maxWidth = readableWidth,
    super.key,
  });

  final Widget child;
  final double maxWidth;

  /// The Feed's list and totals, as rows and as a table.
  static const double feed = 960;
  static const double feedTable = 1280;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

const double columnsBreakpoint = 1200;

enum ShellMode { phone, sidebar, columns }

/// How the main shell lays its screens out, for the screens inside it.
class ShellLayout extends InheritedWidget {
  const ShellLayout({required this.mode, required super.child, super.key});

  final ShellMode mode;

  /// Outside the shell: by window width.
  static ShellMode of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellLayout>()?.mode ??
      (isWide(context) ? ShellMode.sidebar : ShellMode.phone);

  @override
  bool updateShouldNotify(ShellLayout old) => old.mode != mode;
}
