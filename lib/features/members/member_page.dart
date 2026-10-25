import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/security/security_page.dart';
import 'package:sielto/features/sync/sync_controller.dart';

/// One member: their public name, the reader's private name and role for
/// them, and the creator's actions.
class MemberPage extends ConsumerStatefulWidget {
  const MemberPage({
    required this.spaceId,
    required this.member,
    required this.label,
    required this.canManage,
    super.key,
  });

  final String spaceId;
  final Member member;
  final MemberLabel? label;

  /// The reader created the Space.
  final bool canManage;

  @override
  ConsumerState<MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends ConsumerState<MemberPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.label?.name ?? '',
  );
  late final TextEditingController _role = TextEditingController(
    text: widget.label?.role ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    final String role = _role.text.trim();
    if (name == (widget.label?.name ?? '') &&
        role == (widget.label?.role ?? '')) {
      return;
    }
    await ref.read(syncProvider.notifier).setLabel(
      widget.spaceId,
      widget.member.userId,
      (name: name, role: role),
    );
  }

  Future<void> _act({required bool remove}) async {
    final SyncController sync = ref.read(syncProvider.notifier);
    final String name = widget.member.name ?? tr('members.noName');
    final bool confirmed = await confirmDialog(
      context,
      title: tr(
        remove ? 'members.removeTitle' : 'members.ownerTitle',
        namedArgs: <String, String>{'name': name},
      ),
      body: tr(remove ? 'members.removeBody' : 'members.ownerBody'),
      confirmLabel: tr(remove ? 'members.remove' : 'members.makeOwner'),
      isDestructive: remove,
    );
    if (!confirmed || !mounted) return;
    if (!await confirmIdentity(context, ref)) return;
    final bool done = remove
        ? await sync.removeMember(widget.spaceId, widget.member.userId)
        : await sync.transferOwnership(widget.spaceId, widget.member.userId);
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
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) _save();
      },
      child: Scaffold(
        backgroundColor: context.sage.surface,
        appBar: sageAppBar(
          context,
          title: Text(widget.member.name ?? tr('members.noName')),
        ),
        body: ListView(
          padding: scrollPadding(
            context,
            const EdgeInsets.all(SageSpace.formGutter),
          ),
          children: <Widget>[
            if (widget.member.owner) ...<Widget>[
              Text(tr('members.owner'), style: text.bodyMedium),
              const SizedBox(height: SageSpace.lg),
            ],
            LabelledField(
              label: tr('members.localName'),
              child: TextField(
                controller: _name,
                maxLength: TextLimits.name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: widget.member.name ?? tr('members.noName'),
                ),
                onSubmitted: (String _) => _save(),
              ),
            ),
            LabelledField(
              label: tr('members.localRole'),
              child: TextField(
                controller: _role,
                maxLength: TextLimits.name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: tr('members.localRoleHint'),
                ),
                onSubmitted: (String _) => _save(),
              ),
            ),
            Text(tr('members.labelsPrivate'), style: text.bodySmall),
            if (widget.canManage && !widget.member.me) ...<Widget>[
              const SizedBox(height: SageSpace.xl),
              OutlinedButton(
                onPressed: () => _act(remove: false),
                child: Text(tr('members.makeOwner')),
              ),
              const SizedBox(height: SageSpace.sm),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.sage.dangerTint,
                  foregroundColor: context.sage.danger,
                ),
                onPressed: () => _act(remove: true),
                child: Text(tr('members.remove')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
