import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/leaf_loader.dart';
import 'package:sielto/features/members/invite_page.dart';
import 'package:sielto/features/members/member_page.dart';
import 'package:sielto/features/members/public_name.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// The people in a cloud Space; the owner manages them.
class MembersPage extends ConsumerStatefulWidget {
  const MembersPage({required this.spaceId, super.key});

  final String spaceId;

  @override
  ConsumerState<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends ConsumerState<MembersPage> {
  ({CloudResult result, List<Member> members})? _loaded;
  Map<String, MemberLabel> _labels = const <String, MemberLabel>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loaded = null);
    final SyncController sync = ref.read(syncProvider.notifier);
    final ({CloudResult result, List<Member> members}) loaded = await sync
        .members(widget.spaceId);
    final Map<String, MemberLabel> labels = await sync.labels(widget.spaceId);
    if (mounted) {
      setState(() {
        _loaded = loaded;
        _labels = labels;
      });
    }
  }

  Future<void> _invite() async {
    if (!await ensurePublicName(context, ref) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => InvitePage(spaceId: widget.spaceId),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _open(Member member, {required bool canManage}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => MemberPage(
          spaceId: widget.spaceId,
          member: member,
          label: _labels[member.userId],
          canManage: canManage,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ({CloudResult result, List<Member> members})? loaded = _loaded;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('members.title'))),
      body: switch (loaded) {
        null => const Center(child: LeafLoader()),
        (result: CloudResult.done, members: final List<Member> members) =>
          _list(members, _limit(), text),
        (result: final CloudResult result, members: _) => ListView(
          padding: scrollPadding(
            context,
            const EdgeInsets.all(SageSpace.formGutter),
          ),
          children: <Widget>[
            Text(
              tr(switch (result) {
                CloudResult.offlineMode => 'storage.offlineMode',
                CloudResult.unlinked => 'storage.unlinked',
                _ => 'storage.noNetwork',
              }),
              style: text.bodyLarge,
            ),
            const SizedBox(height: SageSpace.lg),
            FilledButton(onPressed: _load, child: Text(tr('devices.tryAgain'))),
          ],
        ),
      },
    );
  }

  /// The limit on this device, which the owner edits.
  int? _limit() => ref
      .watch(spaceListProvider)
      .value
      ?.where((Space s) => s.id == widget.spaceId)
      .firstOrNull
      ?.maxMembers;

  Widget _list(List<Member> members, int? limit, TextTheme text) {
    final bool owner = members.any((Member m) => m.me && m.owner);
    final int? max = limit == null ? null : math.max(limit, members.length);
    final bool room = max == null || members.length < max;
    return ListView(
      padding: scrollPadding(
        context,
        const EdgeInsets.symmetric(vertical: SageSpace.md),
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SageSpace.formGutter),
          child: Text(
            max == null
                ? plural('members.count', members.length)
                : tr(
                    'members.countOf',
                    args: <String>['${members.length}', '$max'],
                  ),
            style: text.bodyMedium,
          ),
        ),
        for (final Member member in members) _row(member, owner: owner),
        if (owner && room)
          Padding(
            padding: const EdgeInsets.all(SageSpace.formGutter),
            child: FilledButton(
              onPressed: _invite,
              child: Text(tr('members.invite')),
            ),
          ),
        if (owner && !room)
          Padding(
            padding: const EdgeInsets.all(SageSpace.formGutter),
            child: Text(tr('members.full'), style: text.bodySmall),
          ),
      ],
    );
  }

  Widget _row(Member member, {required bool owner}) {
    final MemberLabel? label = _labels[member.userId];
    final String shown = label?.name ?? member.name ?? tr('members.noName');
    final int? away = switch (member.lastSeen) {
      final DateTime at when !member.me => DateTime.now().difference(at).inDays,
      _ => null,
    };
    final List<String> details = <String>[
      if (member.owner) tr('members.owner'),
      if (label?.role case final String role) role,
      if (away != null && away > 30) plural('members.lastSeen', away),
    ];
    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(member.me ? tr('members.you', args: <String>[shown]) : shown),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: member.me ? null : const Icon(Icons.chevron_right),
      onTap: member.me ? null : () => _open(member, canManage: owner),
    );
  }
}
