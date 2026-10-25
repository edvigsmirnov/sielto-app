import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/sage_widgets.dart';

class SheetAction<T> {
  const SheetAction(
    this.icon,
    this.label,
    this.value, {
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final T value;
  final bool destructive;
}

Offset? _lastPointer;

/// Where the pointer last went down; null before any.
Offset? get lastPointer => _lastPointer;
bool get _keyed => keyboardDriven.value;

/// True after a key press, false after a click or touch.
final ValueNotifier<bool> keyboardDriven = ValueNotifier<bool>(false);

/// Where a context menu opens: the last click, or the focused control.
Offset _menuOrigin() {
  final FocusNode? focus = FocusManager.instance.primaryFocus;
  if ((_keyed || _lastPointer == null) &&
      focus != null &&
      focus.rect.isFinite) {
    return focus.rect.center;
  }
  return _lastPointer ?? Offset.zero;
}

/// Actions in groups, divided by a hairline. Null when dismissed. On
/// desktop, a context menu.
Future<T?> showActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<List<SheetAction<T>>> groups,
}) => desktopInput
    ? _showMenu(context, title: title, groups: groups)
    : showModalBottomSheet<T>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: context.sage.card,
        builder: (BuildContext sheet) {
          final List<List<SheetAction<T>>> shown = <List<SheetAction<T>>>[
            for (final List<SheetAction<T>> g in groups)
              if (g.isNotEmpty) g,
          ];
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: SageSpace.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SageSpace.gutter,
                      0,
                      SageSpace.gutter,
                      SageSpace.sm,
                    ),
                    child: SheetTitle(title),
                  ),
                  for (int i = 0; i < shown.length; i++) ...<Widget>[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: SageSpace.gutter,
                          vertical: SageSpace.xs,
                        ),
                        child: Hairline(),
                      ),
                    for (final SheetAction<T> action in shown[i])
                      _ActionRow<T>(action: action),
                  ],
                ],
              ),
            ),
          );
        },
      );

class _ActionRow<T> extends StatelessWidget {
  const _ActionRow({required this.action});

  final SheetAction<T> action;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final Color ink = action.destructive ? sage.danger : sage.accentStrong;
    return InkWell(
      onTap: () => Navigator.of(context).pop(action.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SageSpace.gutter,
          vertical: SageSpace.sm,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: action.destructive ? sage.dangerTint : sage.accentTint,
                shape: BoxShape.circle,
              ),
              child: Icon(action.icon, size: 20, color: ink),
            ),
            const SizedBox(width: SageSpace.md),
            Expanded(
              child: Text(
                action.label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: action.destructive ? sage.danger : sage.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Remembers where the pointer last went down, and whether a key came after.
/// On desktop, Backspace goes back.
void trackPointer() {
  GestureBinding.instance.pointerRouter.addGlobalRoute((PointerEvent e) {
    if (e is! PointerDownEvent) return;
    _lastPointer = e.position;
    keyboardDriven.value = false;
    // Closing a menu with a right-click opens the next one there.
    if (_menusOpen > 0 && e.buttons == kSecondaryMouseButton) {
      _replay = e;
      // The barrier closes a menu on a primary click only.
      final NavigatorState? menu = _menuNavigator;
      scheduleMicrotask(() {
        // Only the menu itself, if it is still on top.
        bool popped = false;
        menu?.popUntil((Route<dynamic> r) {
          if (popped || r is! PopupRoute) return true;
          return !(popped = true);
        });
      });
    }
  });
  HardwareKeyboard.instance.addHandler((KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    keyboardDriven.value = true;
    if (desktopInput && e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
    }
    return false;
  });
}

/// The innermost navigator around the focus that has somewhere to go back
/// to: a panel's page, a dialog, an onboarding step. Not while typing.
Future<void> _back() async {
  final BuildContext? at = FocusManager.instance.primaryFocus?.context;
  if (at == null || at.findAncestorWidgetOfExactType<EditableText>() != null) {
    return;
  }
  final List<NavigatorState> outward = <NavigatorState>[];
  for (
    NavigatorState? n = Navigator.maybeOf(at);
    n != null;
    n = n.context.findAncestorStateOfType<NavigatorState>()
  ) {
    outward.add(n);
  }
  for (final NavigatorState n in outward) {
    if (n.mounted && await n.maybePop()) return;
  }
}

int _menusOpen = 0;
NavigatorState? _menuNavigator;
PointerDownEvent? _replay;

/// Sends the right-click that closed a menu again, once the menu is gone.
void _maybeReplay() {
  final PointerDownEvent? down = _replay;
  if (down == null || _menusOpen > 0) return;
  _replay = null;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    const int pointer = 1 << 30;
    GestureBinding.instance
      ..handlePointerEvent(
        PointerDownEvent(
          pointer: pointer,
          kind: down.kind,
          device: down.device,
          position: down.position,
          buttons: kSecondaryMouseButton,
        ),
      )
      ..handlePointerEvent(
        PointerUpEvent(
          pointer: pointer,
          kind: down.kind,
          device: down.device,
          position: down.position,
        ),
      );
  });
}

Future<T?> _showMenu<T>(
  BuildContext context, {
  required String title,
  required List<List<SheetAction<T>>> groups,
}) async {
  _menusOpen++;
  _menuNavigator = Navigator.of(context, rootNavigator: true);
  try {
    return await _openMenu(context, title: title, groups: groups);
  } finally {
    if (--_menusOpen == 0) _menuNavigator = null;
    _maybeReplay();
  }
}

Future<T?> _openMenu<T>(
  BuildContext context, {
  required String title,
  required List<List<SheetAction<T>>> groups,
}) {
  final SageColors sage = context.sage;
  final TextTheme text = Theme.of(context).textTheme;
  final Offset at = _menuOrigin();
  final List<List<SheetAction<T>>> shown = <List<SheetAction<T>>>[
    for (final List<SheetAction<T>> g in groups)
      if (g.isNotEmpty) g,
  ];
  return showMenu<T>(
    context: context,
    popUpAnimationStyle: AnimationStyle.noAnimation,
    // The position is global; a column's own navigator is offset.
    useRootNavigator: true,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    color: sage.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SageRadius.button),
      side: BorderSide(color: sage.border),
    ),
    items: <PopupMenuEntry<T>>[
      PopupMenuItem<T>(
        enabled: false,
        height: 32,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelMedium?.copyWith(color: sage.inkSecondary),
        ),
      ),
      for (int i = 0; i < shown.length; i++) ...<PopupMenuEntry<T>>[
        if (i > 0) const PopupMenuDivider(),
        for (final SheetAction<T> action in shown[i])
          PopupMenuItem<T>(
            value: action.value,
            child: Row(
              children: <Widget>[
                Icon(
                  action.icon,
                  size: 18,
                  color: action.destructive ? sage.danger : sage.accentStrong,
                ),
                const SizedBox(width: SageSpace.md),
                Text(
                  action.label,
                  style: text.bodyMedium?.copyWith(
                    color: action.destructive ? sage.danger : sage.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    ],
  );
}
