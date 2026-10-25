import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/features/members/public_name.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/sync/codes.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// Joins someone else's Space with the code they sent.
class JoinSpacePage extends ConsumerStatefulWidget {
  const JoinSpacePage({super.key});

  @override
  ConsumerState<JoinSpacePage> createState() => _JoinSpacePageState();
}

class _JoinSpacePageState extends ConsumerState<JoinSpacePage> {
  bool _busy = false;
  String? _problem;

  Future<void> _join(String code) async {
    if (!await ensurePublicName(context, ref) || !mounted) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final ({JoinResult result, String? spaceId}) joined = await ref
        .read(syncProvider.notifier)
        .joinSpace(code);
    if (!mounted) return;
    final String? spaceId = joined.spaceId;
    if (spaceId != null) {
      await ref.read(currentSpaceIdProvider.notifier).select(spaceId);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _problem = codeProblem(joined.result, wrongCode: 'members.wrongCode');
    });
  }

  @override
  Widget build(BuildContext context) => SetupPage(
    title: tr('members.joinTitle'),
    card: false,
    children: <Widget>[
      CodeEntry(
        body: tr('members.joinBody'),
        action: tr('members.join'),
        busyAction: tr('members.joining'),
        busy: _busy,
        problem: _problem,
        onSubmit: _join,
      ),
    ],
  );
}
