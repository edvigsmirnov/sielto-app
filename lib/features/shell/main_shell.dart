import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/features/calendar/calendar_page.dart';
import 'package:sielto/features/calendar/calendar_scope.dart';
import 'package:sielto/features/dashboard/dashboard_page.dart';
import 'package:sielto/features/feed/feed_page.dart';
import 'package:sielto/features/shell/shell_tab.dart';

/// The three main screens and the two ways to move between them: the bottom
/// bar and a horizontal swipe, both live at once (spec 4.1).
///
/// Settings is deliberately not a fourth tab — it is reached from the header
/// (spec 4.2).
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _show(int index) {
    setState(() => _index = index);
    ref.read(shellTabProvider.notifier).show(index);
  }

  void _goTo(int index) {
    final int distance = (index - _index).abs();
    _show(index);
    // Sliding past a tab lays it out mid-flight for nothing; a tap two away
    // lands straight on its target.
    if (distance > 1) {
      _controller.jumpToPage(index);
      return;
    }
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  /// A newly opened Space starts on its Dashboard.
  ///
  /// The shell outlives the Space, so without this a switch lands on whichever
  /// tab the previous Space was left on — and a Space created from the Feed
  /// opened straight into an empty Feed.
  void _resetOnSpaceChange() {
    ref.listen<String?>(currentSpaceIdProvider, (
      String? previous,
      String? next,
    ) {
      if (previous == next || _index == 0) return;
      // Jumped, not animated: a switch is a change of subject, and after a
      // frame, because the notification can arrive mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _show(0);
        if (_controller.hasClients) _controller.jumpToPage(0);
      });
    });
  }

  static const int _calendarTab = 2;

  /// System Back steps back inside the app before it leaves it: out of a Day
  /// or Month the Calendar zoomed into, then to the Dashboard.
  void _back() {
    if (_index == _calendarTab &&
        ref.read(calendarViewProvider.notifier).back()) {
      return;
    }
    if (_index != 0) _goTo(0);
  }

  @override
  Widget build(BuildContext context) {
    _resetOnSpaceChange();
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: context.sage.surface,
        body: PageView(
          controller: _controller,
          onPageChanged: _show,
          children: const <Widget>[
            _KeepAlive(child: DashboardPage()),
            _KeepAlive(child: FeedPage()),
            _KeepAlive(child: CalendarPage()),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.donut_small_outlined),
              selectedIcon: const Icon(Icons.donut_small),
              label: tr('nav.dashboard'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.list_alt_outlined),
              selectedIcon: const Icon(Icons.list_alt),
              label: tr('nav.feed'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
              label: tr('nav.calendar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a tab built while another one is shown.
///
/// A PageView drops pages that scroll out of view, so every return to the
/// Feed rebuilt the whole list and lost its scroll position.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin<_KeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
