import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/launch/launch_curtain.dart';

/// First screen of a fresh install, on [SageBrand.night] in both themes. Leaves
/// gather onto the "i", then the name, motto and button fade in. A tap skips.
class WelcomePage extends StatefulWidget {
  const WelcomePage({required this.onStart, super.key});

  /// Receives the button centre, for the transition.
  final ValueChanged<Offset> onStart;

  static const Duration intro = Duration(milliseconds: 2600);

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: WelcomePage.intro,
  );

  @override
  void initState() {
    super.initState();
    LaunchCurtain.covering.addListener(_play);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion shows the finished screen.
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else {
      _play();
    }
  }

  /// Waits for the launch curtain.
  void _play() {
    if (LaunchCurtain.covering.value) return;
    if (_intro.value == 0 && !_intro.isAnimating) _intro.forward();
  }

  @override
  void dispose() {
    LaunchCurtain.covering.removeListener(_play);
    _intro.dispose();
    super.dispose();
  }

  void _skip() {
    if (_intro.isAnimating) _intro.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Without `systemNavigationBarContrastEnforced: false`, three-button
      // navigation draws a light scrim.
      value: SystemUiOverlayStyle.light.copyWith(
        systemNavigationBarColor: SageBrand.night,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: SageBrand.night,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final Rect mark = _Wordmark.rectIn(box.biggest);
                return AnimatedBuilder(
                  animation: _intro,
                  builder: (BuildContext context, Widget? _) {
                    final double t = _intro.value;
                    final double name = _phase(t, 0.44, 0.64);
                    final double motto = _phase(t, 0.62, 0.8);
                    final double button = _phase(t, 0.74, 0.94);
                    return Stack(
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: mark,
                          child: Opacity(
                            opacity: name,
                            child: Transform.scale(
                              scale: 0.96 + 0.04 * name,
                              child: const _Wordmark(),
                            ),
                          ),
                        ),
                        if (t < 0.7)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _GatheringLeaves(
                                progress: t,
                                target:
                                    mark.topLeft +
                                    Offset(
                                      mark.width * _Wordmark.leafAt.dx,
                                      mark.height * _Wordmark.leafAt.dy,
                                    ),
                                leafLength: mark.width * _Wordmark.leafSize,
                                // Fades as the wordmark's leaf appears.
                                fade: 1 - _phase(t, 0.5, 0.68),
                              ),
                            ),
                          ),
                        Positioned(
                          left: SageSpace.xl,
                          right: SageSpace.xl,
                          top: mark.bottom + SageSpace.lg,
                          child: Opacity(
                            opacity: motto,
                            child: Text(
                              tr('welcome.tagline'),
                              textAlign: TextAlign.center,
                              style: text.bodyLarge?.copyWith(
                                height: 1.6,
                                color: SageBrand.leaf.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: SageSpace.xl,
                          right: SageSpace.xl,
                          bottom: SageSpace.xl,
                          child: Opacity(
                            opacity: button,
                            child: Transform.translate(
                              offset: Offset(0, 16 * (1 - button)),
                              child: FilledButton(
                                onPressed: button > 0.5
                                    ? () => widget.onStart(
                                        Offset(
                                          box.maxWidth / 2,
                                          box.maxHeight -
                                              SageSpace.xl -
                                              _buttonHalf,
                                        ).translate(
                                          0,
                                          MediaQuery.paddingOf(context).top,
                                        ),
                                      )
                                    : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: SageBrand.leaf,
                                  foregroundColor: SageBrand.night,
                                ),
                                child: Text(tr('welcome.start')),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static const double _buttonHalf = 24;

  /// 0 before [from], 1 after [to], eased.
  static double _phase(double t, double from, double to) =>
      Curves.easeOutCubic.transform(((t - from) / (to - from)).clamp(0, 1));
}

/// Cut by `tools/make_icon.py`.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  /// Width over height.
  static const double aspect = 844 / 345;

  /// Centre of the "i" leaf, as a fraction of the crop.
  static const Offset leafAt = Offset(0.276, 0.229);

  /// Leaf length as a fraction of the crop width.
  static const double leafSize = 0.085;

  /// Centred at 40% height, at most 360 wide.
  static Rect rectIn(Size area) {
    final double width = math.min(area.width * 0.78, 360);
    final double height = width / aspect;
    return Rect.fromCenter(
      center: Offset(area.width / 2, area.height * 0.4),
      width: width,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/wordmark.png',
    semanticLabel: 'Sielto',
    filterQuality: FilterQuality.medium,
  );
}

/// Leaves flying in from every side onto one point.
class _GatheringLeaves extends CustomPainter {
  _GatheringLeaves({
    required this.progress,
    required this.target,
    required this.leafLength,
    required this.fade,
  });

  final double progress;
  final Offset target;
  final double leafLength;
  final double fade;

  static const int _count = 9;
  static final Path _leaf = leafPath();

  @override
  void paint(Canvas canvas, Size size) {
    // Starts just outside the screen.
    final double reach = size.longestSide * 0.62;
    final Paint paint = Paint()..isAntiAlias = true;

    for (int i = 0; i < _count; i++) {
      // Every leaf lands by 0.5.
      final double start = 0.12 * i / _count;
      final double t = ((progress - start) / (0.5 - start)).clamp(0.0, 1.0);
      if (t == 0) continue;
      final double eased = Curves.easeOutCubic.transform(t);

      final double from = i * 2 * math.pi / _count + 0.4;
      final double angle = from + (1 - eased) * 1.6;
      final double radius = reach * (1 - eased);
      final Offset at =
          target + Offset(math.cos(angle), math.sin(angle)) * radius;

      final double spin = (1 - eased) * (3 + i % 3) * math.pi;
      // Shrinks to the "i" leaf's size on landing.
      final double length = leafLength * (1 + 1.6 * (1 - eased));

      paint.color = Color.lerp(
        SageBrand.leaf,
        SageBrand.leaf.withValues(alpha: 0.5),
        1 - eased,
      )!.withValues(alpha: fade * math.min(1, t * 4));
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(0.5 + spin)
        ..scale(length)
        ..drawPath(_leaf, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_GatheringLeaves old) =>
      old.progress != progress || old.target != target || old.fade != fade;
}
