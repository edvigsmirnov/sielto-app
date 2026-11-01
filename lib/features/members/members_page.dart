import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/features/members/invite_page.dart';
import 'package:sielto/features/members/member_page.dart';
import 'package:sielto/features/members/members_data.dart';
import 'package:sielto/features/members/public_name.dart';
import 'package:sielto/features/sync/cloud_body.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// The people in a cloud Space; the owner manages them.
class MembersPage extends ConsumerWidget {
  const MembersPage({required this.spaceId, super.key});

  final String spaceId;

  void _reload(WidgetRef ref) => ref.invalidate(membersProvider(spaceId));

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    if (!await ensurePublicName(context, ref) || !context.mounted) return;
    await pushPage<void>(context, InvitePage(spaceId: spaceId));
    if (context.mounted) _reload(ref);
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    MemberList list,
    Member member,
  ) async {
    await pushPage<void>(
      context,
      MemberPage(
        spaceId: spaceId,
        member: member,
        label: list.labels[member.userId],
        canManage: list.members.any((Member m) => m.me && m.owner),
      ),
    );
    if (context.mounted) _reload(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MemberList> state = ref.watch(membersProvider(spaceId));
    final MemberList? list = state.isLoading ? null : state.value;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('members.title'))),
      body: CloudBody(
        result: list?.result,
        onRetry: () => _reload(ref),
        builder: (BuildContext context) => _list(context, ref, list!),
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, MemberList list) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Member> members = list.members;
    final int? limit = ref.watch(spaceByIdProvider(spaceId))?.maxMembers;
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
        for (final Member member in members) _row(context, ref, list, member),
        if (owner && room)
          Padding(
            padding: const EdgeInsets.all(SageSpace.formGutter),
            child: FilledButton(
              onPressed: () => _invite(context, ref),
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

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    MemberList list,
    Member member,
  ) {
    final String shown = list.nameOf(member);
    final int? away = switch (member.lastSeen) {
      final DateTime at when !member.me => DateTime.now().difference(at).inDays,
      _ => null,
    };
    final List<String> details = <String>[
      if (member.owner) tr('members.owner'),
      if (list.labels[member.userId]?.role case final String role) role,
      if (away != null && away > 30) plural('members.lastSeen', away),
    ];
    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(member.me ? tr('members.you', args: <String>[shown]) : shown),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: member.me ? null : const Icon(Icons.chevron_right),
      onTap: member.me ? null : () => _open(context, ref, list, member),
    );
  }
}
