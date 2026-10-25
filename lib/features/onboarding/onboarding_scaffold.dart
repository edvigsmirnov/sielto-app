import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';

/// Onboarding step frame: heading, explanation, fields, pinned primary action.
class OnboardingScaffold extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    final bool wide = isWide(context);
    final TextAlign align = wide ? TextAlign.center : TextAlign.start;
    final Widget steps = Column(
      // Wide, the card fits its content up to the window's height.
      mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ProgressBar(step: step, stepCount: stepCount),
        const SizedBox(height: SageSpace.xl),
        Semantics(
          container: true,
          header: true,
          child: Text(title, style: text.titleMedium, textAlign: align),
        ),
        const SizedBox(height: SageSpace.sm),
        Semantics(
          container: true,
          child: Text(body, style: text.bodySmall, textAlign: align),
        ),
        const SizedBox(height: SageSpace.lg),
        Flexible(
          fit: wide ? FlexFit.loose : FlexFit.tight,
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: wide,
            children: children,
          ),
        ),
        const SizedBox(height: SageSpace.md),
        FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
        if (secondaryLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: SageSpace.sm),
            child: Center(
              child: TextButton(
                onPressed: onSecondary,
                style: TextButton.styleFrom(foregroundColor: sage.inkLabel),
                child: Text(secondaryLabel!),
              ),
            ),
          ),
        ?footer,
      ],
    );
    if (!wide) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SageSpace.formGutter),
          child: steps,
        ),
      );
    }
    return SetupCard(child: steps);
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
