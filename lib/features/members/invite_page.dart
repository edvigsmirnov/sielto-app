import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/devices/code_card.dart';
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
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
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
    _tick?.cancel();
    if (invite.code != null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (Timer _) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _revoke() async {
    final bool done = await ref
        .read(syncProvider.notifier)
        .revokeInvites(widget.spaceId);
    if (!mounted) return;
    if (done) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('storage.noNetwork'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ({CloudResult result, String? code, bool full})? invite = _invite;
    final Duration left = _expires.difference(DateTime.now());
    final bool expired = left.isNegative;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('members.inviteTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(SageSpace.formGutter),
        children: <Widget>[
          switch (invite) {
            null => const Center(child: LeafLoader()),
            (code: final String code, result: _, full: _) when !expired =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(tr('members.inviteBody'), style: text.bodyMedium),
                  const SizedBox(height: SageSpace.xl),
                  CodeCard(code: code, left: left),
                  const SizedBox(height: SageSpace.xl),
                  TextButton(
                    onPressed: _revoke,
                    child: Text(tr('members.revoke')),
                  ),
                ],
              ),
            (full: true, result: _, code: _) => Text(
              tr('members.full'),
              style: text.bodyLarge,
            ),
            (result: final CloudResult result, code: _, full: _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  tr(switch (result) {
                    CloudResult.offlineMode => 'storage.offlineMode',
                    CloudResult.unlinked => 'storage.unlinked',
                    CloudResult.done => 'devices.expired',
                    CloudResult.noNetwork => 'storage.noNetwork',
                  }),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: SageSpace.lg),
                FilledButton(
                  onPressed: _start,
                  child: Text(tr('devices.newCode')),
                ),
              ],
            ),
          },
        ],
      ),
    );
  }
}
