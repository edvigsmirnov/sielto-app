import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/ui/dialogs.dart';

/// Asks, once per Space, whether to keep a shared Space that left the cloud.
class VanishedPrompt extends ConsumerStatefulWidget {
  const VanishedPrompt({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VanishedPrompt> createState() => _VanishedPromptState();
}

class _VanishedPromptState extends ConsumerState<VanishedPrompt> {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration _) => _next());
  }

  Future<void> _next() async {
    if (_asking || !mounted) return;
    final List<String> pending = ref.read(vanishedSpacesProvider);
    if (pending.isEmpty) return;
    _asking = true;
    final String id = pending.first;
    final Space? space = await ref.read(repositoriesProvider).spaces.byId(id);
    if (space != null && mounted) await _ask(space);
    await ref.read(vanishedSpacesProvider.notifier).remove(id);
    _asking = false;
    unawaited(_next());
  }

  Future<void> _ask(Space space) async {
    final bool? keep = await choiceDialog<bool>(
      context,
      title: tr(
        'vanished.title',
        namedArgs: <String, String>{'title': space.title},
      ),
      body: tr('vanished.body'),
      choices: <(String, bool)>[
        (tr('common.delete'), false),
        (tr('vanished.keep'), true),
      ],
      primaryLast: true,
      dismissible: false,
    );
    final Repositories repos = ref.read(repositoriesProvider);
    if (keep ?? true) {
      await repos.spaces.keepAsOwn(space.id, ref.read(userIdProvider));
      await ref.read(currentSpaceIdProvider.notifier).select(space.id);
    } else {
      await repos.spaces.deleteForever(space.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(vanishedSpacesProvider, (_, _) {
      unawaited(_next());
    });
    return widget.child;
  }
}
