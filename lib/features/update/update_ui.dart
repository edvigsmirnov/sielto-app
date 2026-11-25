import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/links.dart';
import 'package:sielto/core/ui/plain_markdown.dart';
import 'package:sielto/core/ui/plate.dart';
import 'package:sielto/core/update/update_service.dart';
import 'package:sielto/features/update/update_controller.dart';

/// Asks once whether to check; with checks on, shows a new version until
/// closed.
class UpdatePlate extends ConsumerWidget {
  const UpdatePlate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UpdateState update = ref.watch(updateProvider);
    final Release? available = ref.watch(availableUpdateProvider);
    final UpdateController controller = ref.read(updateProvider.notifier);

    if (update.enabled == null) {
      return Plate(
        icon: Icons.update,
        text: tr('update.askPlate'),
        action: TextButton(
          onPressed: () => controller.setEnabled(value: true),
          child: Text(tr('update.turnOn')),
        ),
        closeTooltip: tr('update.noThanks'),
        onClose: () => controller.setEnabled(value: false),
      );
    }
    if (available == null ||
        update.enabled != true ||
        available.version.toString() == update.dismissed) {
      return const SizedBox.shrink();
    }
    return Plate(
      icon: Icons.system_update_outlined,
      text: tr('update.available', args: <String>['${available.version}']),
      onTap: () => pushPage<void>(context, WhatsNewPage(release: available)),
      onClose: () => controller.dismiss(available),
    );
  }
}

/// About's status row and the start-check switch.
class UpdateSection extends ConsumerWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UpdateState update = ref.watch(updateProvider);
    final Release? available = ref.watch(availableUpdateProvider);
    final bool offline = ref.watch(offlineModeProvider);
    final UpdateController controller = ref.read(updateProvider.notifier);

    final String status = switch (update) {
      UpdateState(checking: true) => tr('update.checking'),
      _ when available != null => tr(
        'update.newVersion',
        args: <String>['${available.version}'],
      ),
      UpdateState(failed: true) => tr('update.failed'),
      UpdateState(lastCheck: DateTime()) => tr('update.upToDate'),
      _ => tr('update.notChecked'),
    };

    return Column(
      children: <Widget>[
        ListTile(
          leading: Icon(
            available == null
                ? Icons.check_circle_outline
                : Icons.system_update_outlined,
          ),
          title: Text(status),
          subtitle: offline ? Text(tr('update.offline')) : null,
          trailing: available == null
              ? TextButton(
                  onPressed: offline || update.checking
                      ? null
                      : controller.check,
                  child: Text(tr('update.checkNow')),
                )
              : const Icon(Icons.chevron_right),
          onTap: available == null
              ? null
              : () => pushPage<void>(context, WhatsNewPage(release: available)),
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.update),
          title: Text(tr('update.checks')),
          subtitle: Text(tr('update.checksHint')),
          value: update.enabled ?? false,
          onChanged: (bool value) => controller.setEnabled(value: value),
        ),
      ],
    );
  }
}

/// The release notes and the way to the new version.
class WhatsNewPage extends ConsumerWidget {
  const WhatsNewPage({required this.release, super.key});

  final Release release;

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!await ref.read(updateDownloadProvider.notifier).install(release)) {
      messenger.say(tr('update.downloadFailed'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double? progress = ref.watch(updateDownloadProvider);
    final bool inApp = installsInApp(release);

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(
        context,
        title: Text(
          tr('update.whatsNew', args: <String>['${release.version}']),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: release.notes.trim().isEmpty
                ? Center(child: Text(tr('update.noNotes')))
                : PlainMarkdown(release.notes),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(SageSpace.gutter),
              child: Readable(
                child: SizedBox(
                  width: double.infinity,
                  child: progress != null
                      ? _DownloadBar(progress: progress)
                      : FilledButton(
                          onPressed: inApp
                              ? () => _install(context, ref)
                              : () =>
                                    openLink(context, release.page.toString()),
                          child: Text(
                            tr(inApp ? 'update.install' : 'update.openPage'),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The install button while the download runs: the accent fills it from the
/// left, and the label reads on both the filled and the empty part.
class _DownloadBar extends StatelessWidget {
  const _DownloadBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final String label = tr(
      'update.downloading',
      args: <String>['${(progress * 100).round()}'],
    );

    Widget face(Color background, Color foreground) => FilledButton(
      onPressed: null,
      style: FilledButton.styleFrom(
        disabledBackgroundColor: background,
        disabledForegroundColor: foreground,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          face(sage.accentTint, sage.ink),
          Positioned.fill(
            child: ClipRect(
              clipper: _LeftShare(progress),
              child: face(sage.accent, sage.accentOn),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftShare extends CustomClipper<Rect> {
  const _LeftShare(this.share);

  final double share;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * share, size.height);

  @override
  bool shouldReclip(_LeftShare oldClipper) => oldClipper.share != share;
}
