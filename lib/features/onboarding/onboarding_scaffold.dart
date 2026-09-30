import 'package:flutter/material.dart';
import 'package:sielto/core/theme/sage_tokens.dart';

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

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SageSpace.formGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ProgressBar(step: step, stepCount: stepCount),
            const SizedBox(height: SageSpace.xl),
            Text(title, style: text.titleMedium),
            const SizedBox(height: SageSpace.sm),
            Text(body, style: text.bodySmall),
            const SizedBox(height: SageSpace.lg),
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: children),
            ),
            const SizedBox(height: SageSpace.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
            ),
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
          ],
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
