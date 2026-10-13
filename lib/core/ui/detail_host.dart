import 'package:flutter/material.dart';
import 'package:sielto/core/ui/layout.dart';

/// A navigator that pages opened anywhere under it go to. [builder] places
/// it; [root] is its first page, an empty one when null.
class DetailHost extends StatefulWidget {
  const DetailHost({
    required this.builder,
    this.root,
    this.observers = const <NavigatorObserver>[],
    super.key,
  });

  final List<NavigatorObserver> observers;

  /// Lays out [navigator]; [open] is true while a page is pushed on [root].
  final Widget Function(
    BuildContext context,
    Widget navigator, {
    required bool open,
  })
  builder;

  final Widget? root;

  /// Pushes [route] into the nearest host, replacing what it showed, or onto
  /// the caller's own navigator inside the host or without one.
  static Future<T?> push<T>(BuildContext context, Route<T> route) {
    final NavigatorState own = Navigator.of(context);
    final NavigatorState? host = context
        .getInheritedWidgetOfExactType<_Scope>()
        ?.navigator
        .currentState;
    if (host == null || identical(host, own)) return own.push(route);
    return host.pushAndRemoveUntil(route, (Route<dynamic> r) => r.isFirst);
  }

  /// Route arguments of the page open in the host; null when none is.
  static Object? openOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Scope>()?.notifier?.value;

  @override
  State<DetailHost> createState() => _DetailHostState();
}

class _DetailHostState extends State<DetailHost> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  final ValueNotifier<Object?> _open = ValueNotifier<Object?>(null);
  bool _shown = false;
  late final _Observer _observer = _Observer((Route<dynamic>? top) {
    if (!mounted) return;
    final bool shown = top != null && !top.isFirst;
    _open.value = shown ? top.settings.arguments : null;
    if (shown != _shown) setState(() => _shown = shown);
  });

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Scope(
    navigator: _navigator,
    notifier: _open,
    child: widget.builder(
      context,
      Navigator(
        key: _navigator,
        observers: <NavigatorObserver>[_observer, ...widget.observers],
        onGenerateRoute: (RouteSettings _) => PageRouteBuilder<void>(
          pageBuilder: (
            BuildContext _,
            Animation<double> _,
            Animation<double> _,
          ) => widget.root ?? const SizedBox.shrink(),
        ),
      ),
      open: _shown,
    ),
  );
}

/// A panel of [width] beside [child] that slides in while [open], on the
/// right, or the left when [start].
class SidePanel extends StatelessWidget {
  const SidePanel({
    required this.child,
    required this.panel,
    required this.open,
    required this.width,
    this.start = false,
    super.key,
  });

  final Widget child;
  final Widget panel;
  final bool open;
  final double width;
  final bool start;

  @override
  Widget build(BuildContext context) {
    final Widget box = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: open ? width + 1 : 0,
      decoration: BoxDecoration(
        border: Border(
          left: start
              ? BorderSide.none
              : BorderSide(color: Theme.of(context).dividerColor),
          right: start
              ? BorderSide(color: Theme.of(context).dividerColor)
              : BorderSide.none,
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: start ? Alignment.centerRight : Alignment.centerLeft,
          minWidth: width,
          maxWidth: width,
          child: ExcludeFocus(excluding: !open, child: panel),
        ),
      ),
    );
    return Row(
      children: start
          ? <Widget>[box, Expanded(child: child)]
          : <Widget>[Expanded(child: child), box],
    );
  }
}

class _Scope extends InheritedNotifier<ValueNotifier<Object?>> {
  const _Scope({
    required this.navigator,
    required super.notifier,
    required super.child,
  });

  final GlobalKey<NavigatorState> navigator;
}

class _Observer extends NavigatorObserver {
  _Observer(this.onTop);

  final ValueChanged<Route<dynamic>?> onTop;

  // After the frame: the navigator reports while it builds.
  void _report(Route<dynamic>? top) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => onTop(top));

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);
}

/// The pages of a column's navigator, bottom first, and the titles of those
/// covered by another page.
class ColumnRoutes extends NavigatorObserver with ChangeNotifier {
  final List<Route<dynamic>> stack = <Route<dynamic>>[];
  final Map<Route<dynamic>, String?> titles = <Route<dynamic>, String?>{};

  /// A navigator rebuilt after a layout change leaves its old pages behind.
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack
      ..removeWhere((Route<dynamic> r) => !r.isActive && r != route)
      ..add(route);
    if (previousRoute != null && !previousRoute.isFirst) {
      _remember(previousRoute);
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _other?._close(_titleOf(route)),
    );
  }

  ColumnRoutes? _other;

  /// Pairs two columns: a screen is open in one of them at a time, the
  /// latest.
  set other(ColumnRoutes value) {
    _other = value;
    value._other = this;
  }

  void _close(String? title) {
    final List<Route<dynamic>> open = stack
        .where((Route<dynamic> r) => r.isActive)
        .toList();
    final int at = open.indexWhere(
      (Route<dynamic> r) => !r.isFirst && _titleOf(r) == title,
    );
    if (title == null || at <= 0) return;
    navigator?.popUntil((Route<dynamic> r) => r == open[at - 1]);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.remove(route);
    titles.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.remove(route);
    titles.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final int at = oldRoute == null ? -1 : stack.indexOf(oldRoute);
    if (at >= 0 && newRoute != null) stack[at] = newRoute;
  }

  // Its elements can be read only outside a build.
  void _remember(Route<dynamic> route) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        titles[route] = _titleOf(route);
        notifyListeners();
      });
}

/// Names a column's own screen and tracks its pages, so back buttons can
/// name the previous screen.
class ColumnHome extends InheritedNotifier<ColumnRoutes> {
  const ColumnHome({
    required this.label,
    required ColumnRoutes routes,
    required super.child,
    super.key,
  }) : super(notifier: routes);

  final String label;

  @override
  bool updateShouldNotify(ColumnHome oldWidget) =>
      oldWidget.label != label || super.updateShouldNotify(oldWidget);
}

/// "‹ Settings": the screen below this one in a column. Null outside a
/// column, for the usual back arrow.
Widget? columnBack(BuildContext context) {
  final String? label = _backLabel(context);
  if (label == null) return null;
  return Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.chevron_left),
      label: Text(label, overflow: TextOverflow.ellipsis),
    ),
  );
}

String? _backLabel(BuildContext context) {
  final ColumnHome? home = context
      .dependOnInheritedWidgetOfExactType<ColumnHome>();
  final ModalRoute<Object?>? route = ModalRoute.of(context);
  if (home == null || route == null) return null;
  final ColumnRoutes routes = home.notifier!;
  final int at = routes.stack.indexOf(route);
  if (at <= 0) return null;
  if (at == 1) return home.label;
  return routes.titles[routes.stack[at - 1]];
}

/// The text title of the first app bar on [route].
String? _titleOf(Route<dynamic> route) {
  final BuildContext? root = route is ModalRoute ? route.subtreeContext : null;
  if (root == null) return null;
  String? found;
  void visit(Element e) {
    if (found != null) return;
    final Widget w = e.widget;
    if (w is _PageTitle) {
      found = _textOf(w.child);
      return;
    }
    if (w is AppBar && w.title is! _BackSlot) {
      found = _textOf(w.title);
      return;
    }
    e.visitChildElements(visit);
  }

  root.visitChildElements(visit);
  return found;
}

String? _textOf(Widget? w) => switch (w) {
  final Text t => t.data,
  final Semantics s => _textOf(s.child),
  _ => null,
};

/// The app bar for pushed pages. In a column the back button gets its own
/// row and the title sits centred under it.
PreferredSizeWidget sageAppBar(
  BuildContext context, {
  Widget? title,
  List<Widget>? actions,
  Color? backgroundColor,
  bool automaticallyImplyLeading = true,
  PreferredSizeWidget? bottom,
}) {
  final Widget? back = columnBack(context);
  if (back == null) {
    return AppBar(
      title: title,
      // Desktop titles are centred.
      centerTitle: isWide(context) ? true : null,
      actions: actions,
      backgroundColor: backgroundColor,
      automaticallyImplyLeading: automaticallyImplyLeading,
      bottom: bottom,
    );
  }
  const double titleRow = 44;
  return AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: backgroundColor,
    toolbarHeight: 48,
    titleSpacing: 8,
    centerTitle: false,
    title: _BackSlot(child: back),
    actions: actions,
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(
        titleRow + (bottom?.preferredSize.height ?? 0),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: titleRow,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: Semantics(
                    header: true,
                    child: _PageTitle(child: title ?? const SizedBox()),
                  ),
                ),
              ),
            ),
          ),
          ?bottom,
        ],
      ),
    ),
  );
}

/// The title under a column's back row, found by the next page's back label.
class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The back button sitting in an app bar's title slot.
class _BackSlot extends StatelessWidget {
  const _BackSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
