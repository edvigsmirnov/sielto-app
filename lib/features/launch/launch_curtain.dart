import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/core/ui/leaf_scatter.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:sielto/features/incomes/income_rules_page.dart';
import 'package:sielto/features/space/budget_ledger.dart';
import 'package:sielto/features/space/period_ledger.dart';
import 'package:sielto/features/space/space_ledger.dart';

/// True once the first screen has content: welcome, or a loaded Dashboard.
final Provider<bool> launchReadyProvider = Provider<bool>((Ref ref) {
  final AsyncValue<Space?> resolved = ref.watch(resolvedSpaceProvider);
  if (resolved.hasError) return true;
  if (!resolved.hasValue) return false;
  final Space? space = resolved.value;
  if (space == null) return true;
  bool settled(AsyncValue<Object?> v) => v.hasValue || v.hasError;
  return switch (space.budgetMode) {
    BudgetMode.flow => settled(ref.watch(flowLedgerProvider)),
    BudgetMode.budget => settled(ref.watch(budgetLedgerProvider)),
    BudgetMode.incomeDriven => () {
      final AsyncValue<List<IncomeRecurrenceRule>> rules = ref.watch(
        incomeRulesProvider,
      );
      if (!settled(rules)) return false;
      final bool anchored = (rules.value ?? const <IncomeRecurrenceRule>[]).any(
        (IncomeRecurrenceRule r) => r.isAnchor,
      );
      return !anchored || settled(ref.watch(periodLedgerProvider));
    }(),
  };
});

/// Continues the Android splash until the first screen is ready. Cold start
/// only.
class LaunchCurtain extends ConsumerStatefulWidget {
  const LaunchCurtain({required this.child, super.key});

  final Widget child;

  /// Set by [arm]. Tests do not call it and get no curtain.
  static bool armed = false;

  /// Android 12+ splash icon diameter for an adaptive icon.
  static const double iconSize = 192;

  static ui.Image? _icon;

  static bool _held = false;

  /// True while the curtain is up.
  static final ValueNotifier<bool> covering = ValueNotifier<bool>(false);

  static void _release() {
    if (!_held) return;
    _held = false;
    WidgetsBinding.instance.allowFirstFrame();
  }

  /// Defers the first frame until the curtain builds: EasyLocalization's empty
  /// first frame would end the system splash.
  static Future<void> arm() async {
    WidgetsBinding.instance.deferFirstFrame();
    _held = true;
    // Releases the frame even if the curtain never builds.
    Timer(const Duration(seconds: 2), _release);
    final ByteData data = await rootBundle.load('assets/brand/splash_icon.png');
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
    );
    _icon = (await codec.getNextFrame()).image;
    armed = true;
  }

  @override
  ConsumerState<LaunchCurtain> createState() => _LaunchCurtainState();
}

enum _Phase { covering, fading, scattering, done }

class _LaunchCurtainState extends ConsumerState<LaunchCurtain> {
  final GlobalKey _curtain = GlobalKey();
  _Phase _phase = LaunchCurtain.armed ? _Phase.covering : _Phase.done;
  bool _loading = false;
  ui.Image? _snapshot;
  ProviderSubscription<bool>? _ready;
  final List<Timer> _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    if (_phase == _Phase.done) return;
    LaunchCurtain.armed = false;
    LaunchCurtain.covering.value = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => LaunchCurtain._release(),
    );
    _timers
      // Loader only for loads over 300 ms.
      ..add(
        Timer(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _loading = true);
        }),
      )
      // Reveals after 6 s at the latest.
      ..add(Timer(const Duration(seconds: 6), _reveal));
    _ready = ref.listenManual<bool>(launchReadyProvider, (bool? _, bool ready) {
      if (ready) _reveal();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _stopWatching();
    _snapshot?.dispose();
    super.dispose();
  }

  void _stopWatching() {
    for (final Timer t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _ready?.close();
    _ready = null;
  }

  Future<void> _reveal() async {
    if (_phase != _Phase.covering) return;
    _stopWatching();
    final bool firstRun = ref.read(currentSpaceProvider) == null;
    // Lets the screen underneath paint.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (firstRun) {
      setState(() => _phase = _Phase.fading);
      LaunchCurtain.covering.value = false;
      return;
    }
    final ui.Image? image = await snapshotOf(_curtain);
    if (!mounted) return;
    LaunchCurtain.covering.value = false;
    if (image == null) {
      setState(() => _phase = _Phase.fading);
      return;
    }
    setState(() {
      _snapshot = image;
      _phase = _Phase.scattering;
    });
  }

  void _finish() {
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
    _snapshot?.dispose();
    _snapshot = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.done) return widget.child;
    final ui.Image? image = _snapshot;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (_phase == _Phase.scattering && image != null)
          LeafScatter(image: image, onDone: _finish)
        else
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.light.copyWith(
              systemNavigationBarColor: SageBrand.night,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 1,
                end: _phase == _Phase.fading ? 0 : 1,
              ),
              duration: const Duration(milliseconds: 260),
              onEnd: _phase == _Phase.fading ? _finish : null,
              builder: (BuildContext context, double opacity, Widget? child) =>
                  IgnorePointer(
                    ignoring: _phase == _Phase.fading,
                    child: Opacity(opacity: opacity, child: child),
                  ),
              child: RepaintBoundary(
                key: _curtain,
                child: _Curtain(loading: _loading),
              ),
            ),
          ),
      ],
    );
  }
}

class _Curtain extends StatelessWidget {
  const _Curtain({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: SageBrand.night,
    child: Center(
      child: SizedBox.square(
        dimension: LaunchCurtain.iconSize,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: loading
              ? const LeafLoader(
                  key: ValueKey<String>('loader'),
                  size: 120,
                  onBrand: true,
                )
              : RawImage(
                  key: const ValueKey<String>('icon'),
                  image: LaunchCurtain._icon,
                  filterQuality: FilterQuality.medium,
                ),
        ),
      ),
    ),
  );
}
