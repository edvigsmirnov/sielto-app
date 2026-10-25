import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/sync/codes.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// A one-time code that lets someone join this Space.
class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({required this.spaceId, super.key});

  final String spaceId;

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  static const Duration _life = Duration(minutes: 15);

  ({CloudResult result, String? code, bool full})? _invite;
  DateTime _expires = DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() => _invite = null);
    final ({CloudResult result, String? code, bool full}) invite = await ref
        .read(syncProvider.notifier)
        .createInvite(widget.spaceId);
    if (!mounted) return;
    setState(() {
      _invite = invite;
      _expires = DateTime.now().add(_life);
    });
  }

  Future<void> _revoke() async {
    final bool done = await ref
        .read(syncProvider.notifier)
        .revokeInvites(widget.spaceId);
    if (!mounted) return;
    if (done) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).say(tr('storage.noNetwork'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool expired = !DateTime.now().isBefore(_expires);
    return SetupPage(
      title: tr('members.inviteTitle'),
      card: false,
      children: <Widget>[
        switch (_invite) {
          null => const Center(child: LeafLoader()),
          (code: final String code, result: _, full: _) when !expired => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(tr('members.inviteBody'), style: text.bodyMedium),
              const SizedBox(height: SageSpace.xl),
              CodeCard(
                code: code,
                expires: _expires,
                onExpired: () => setState(() {}),
              ),
              const SizedBox(height: SageSpace.xl),
              TextButton(onPressed: _revoke, child: Text(tr('members.revoke'))),
            ],
          ),
          (full: true, result: _, code: _) => Text(
            tr('members.full'),
            style: text.bodyLarge,
          ),
          (result: final CloudResult result, code: _, full: _) => CodeRetry(
            message: tr(
              result == CloudResult.done
                  ? 'devices.expired'
                  : 'storage.${result.name}',
            ),
            onRetry: _start,
          ),
        },
      ],
    );
  }
}
