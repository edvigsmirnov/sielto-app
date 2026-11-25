import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';

/// Onboarding step frame: heading, explanation, fields, then the primary
/// action at the end of the content.
class OnboardingScaffold extends StatefulWidget {
  const OnboardingScaffold({
    required this.step,
    required this.stepCount,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.children = const <Widget>[],
    this.secondaryLabel,
    this.onSecondary,
    this.footer,
    super.key,
  });

  /// One-based.
  final int step;
  final int stepCount;

  final String title;
  final String body;
  final List<Widget> children;

  final String primaryLabel;

  /// Null disables the button.
  final VoidCallback? onPrimary;

  /// "Skip", where the step is optional.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Under the secondary action, such as choices it opens.
  final Widget? footer;

  @override
  State<OnboardingScaffold> createState() => _OnboardingScaffoldState();
}

class _OnboardingScaffoldState extends State<OnboardingScaffold>
    with WidgetsBindingObserver {
  final GlobalKey _primary = GlobalKey();
  double _keyboard = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final double keyboard = View.of(context).viewInsets.bottom;
    if (keyboard > _keyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealPrimary());
    }
    _keyboard = keyboard;
  }

  /// With the keyboard up, the primary action scrolls into view as well when
  /// the focused field still fits above it.
  void _revealPrimary() {
    final BuildContext? button = _primary.currentContext;
    final BuildContext? field = FocusManager.instance.primaryFocus?.context;
    final ScrollableState? scroll = button == null
        ? null
        : Scrollable.maybeOf(button);
    if (!mounted || button == null || field == null || scroll == null) return;
    final RenderBox buttonBox = button.findRenderObject()! as RenderBox;
    final RenderBox fieldBox = field.findRenderObject()! as RenderBox;
    final double fieldTop = fieldBox.localToGlobal(Offset.zero).dy;
    final double buttonBottom = buttonBox
        .localToGlobal(buttonBox.size.bottomLeft(Offset.zero))
        .dy;
    final double viewport = scroll.position.viewportDimension;
    if (buttonBottom - fieldTop > viewport) return;
    Scrollable.ensureVisible(
      button,
      alignment: 1,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    final bool wide = isWide(context);
    final TextAlign align = wide ? TextAlign.center : TextAlign.start;
    final List<Widget> heading = <Widget>[
      _ProgressBar(step: widget.step, stepCount: widget.stepCount),
      const SizedBox(height: SageSpace.xl),
      Semantics(
        container: true,
        header: true,
        child: Text(widget.title, style: text.titleMedium, textAlign: align),
      ),
      const SizedBox(height: SageSpace.sm),
      Semantics(
        container: true,
        child: Text(widget.body, style: text.bodySmall, textAlign: align),
      ),
      const SizedBox(height: SageSpace.lg),
    ];
    final List<Widget> actions = <Widget>[
      const SizedBox(height: SageSpace.md),
      FilledButton(
        key: _primary,
        onPressed: widget.onPrimary,
        child: Text(widget.primaryLabel),
      ),
      if (widget.secondaryLabel case final String label)
        Padding(
          padding: const EdgeInsets.only(top: SageSpace.sm),
          child: Center(
            child: TextButton(
              onPressed: widget.onSecondary,
              style: TextButton.styleFrom(foregroundColor: sage.inkLabel),
              child: Text(label),
            ),
          ),
        ),
      ?widget.footer,
    ];

    if (!wide) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SageSpace.formGutter),
          children: <Widget>[...heading, ...widget.children, ...actions],
        ),
      );
    }
    // Wide, the card fits its content up to the window's height.
    return SetupCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...heading,
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: widget.children,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A pushed setup screen: the setup card when [card], otherwise a page with
/// [action] in the bottom bar.
class SetupPage extends StatelessWidget {
  const SetupPage({
    required this.title,
    required this.card,
    required this.children,
    this.action,
    super.key,
  });

  final String title;
  final bool card;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    if (!card) {
      return Scaffold(
        backgroundColor: context.sage.surface,
        appBar: sageAppBar(context, title: Text(title)),
        bottomNavigationBar: action == null
            ? null
            : FormActionBar(child: action!),
        body: ListView(
          padding: scrollPadding(
            context,
            const EdgeInsets.all(SageSpace.formGutter),
          ),
          children: children,
        ),
      );
    }
    return Scaffold(
      backgroundColor: context.sage.surface,
      body: SetupCard(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          children: <Widget>[
            Row(
              children: <Widget>[
                const BackButton(),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(width: kMinInteractiveDimension),
              ],
            ),
            const SizedBox(height: SageSpace.md),
            ...children,
            if (action != null) ...<Widget>[
              const SizedBox(height: SageSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Wide, setup sits in a card in the middle of the window, as tall as its
/// content allows.
class SetupCard extends StatelessWidget {
  const SetupCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(SageSpace.lg),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: sage.card,
              borderRadius: BorderRadius.circular(SageRadius.card),
              border: Border.all(color: sage.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(SageSpace.xl),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A scrolling [SetupCard] wide; narrow, a column at most 420 wide.
class SetupFrame extends StatelessWidget {
  const SetupFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool wide = isWide(context);
    return Center(
      child: SingleChildScrollView(
        padding: wide ? EdgeInsets.zero : const EdgeInsets.all(SageSpace.xl),
        child: wide
            ? SetupCard(child: child)
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: child,
              ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step, required this.stepCount});

  final int step;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: step / stepCount),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double value, Widget? _) =>
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: sage.hairline,
                valueColor: AlwaysStoppedAnimation<Color>(sage.accent),
              ),
            ),
      ),
    );
  }
}
