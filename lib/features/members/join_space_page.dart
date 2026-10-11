import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/members/public_name.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// Joins someone else's Space with the code they sent.
class JoinSpacePage extends ConsumerStatefulWidget {
  const JoinSpacePage({super.key});

  @override
  ConsumerState<JoinSpacePage> createState() => _JoinSpacePageState();
}

class _JoinSpacePageState extends ConsumerState<JoinSpacePage> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _ready => !_busy && _code.text.trim().length == 8;

  Future<void> _join() async {
    if (!await ensurePublicName(context, ref) || !mounted) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final ({JoinResult result, String? spaceId}) joined = await ref
        .read(syncProvider.notifier)
        .joinSpace(_code.text);
    if (!mounted) return;
    final String? spaceId = joined.spaceId;
    if (spaceId != null) {
      await ref.read(currentSpaceIdProvider.notifier).select(spaceId);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _problem = tr(switch (joined.result) {
        JoinResult.offlineMode => 'storage.offlineMode',
        JoinResult.noNetwork => 'storage.noNetwork',
        JoinResult.tooManyAttempts => 'devices.tooManyAttempts',
        JoinResult.spaceFull => 'members.joinFull',
        JoinResult.unlinked => 'storage.unlinked',
        _ => 'members.wrongCode',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: AppBar(title: Text(tr('members.joinTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(SageSpace.formGutter),
        children: <Widget>[
          Text(tr('members.joinBody'), style: text.bodyMedium),
          const SizedBox(height: SageSpace.lg),
          LabelledField(
            label: tr('devices.codeField'),
            child: TextField(
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (String _) => _ready ? _join() : null,
            ),
          ),
          if (_problem case final String problem) ...<Widget>[
            const SizedBox(height: SageSpace.sm),
            Text(problem, style: text.bodyMedium),
          ],
          const SizedBox(height: SageSpace.lg),
          FilledButton(
            onPressed: _ready ? _join : null,
            child: Text(tr(_busy ? 'members.joining' : 'members.join')),
          ),
        ],
      ),
    );
  }
}
