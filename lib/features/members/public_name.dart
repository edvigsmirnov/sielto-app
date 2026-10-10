import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/ui/dialogs.dart';

/// People who share a Space see each other's name, so it cannot be empty.
/// False when the reader cancels.
Future<bool> ensurePublicName(BuildContext context, WidgetRef ref) async {
  final String? current = ref.read(nameProvider)?.trim();
  if (current != null && current.isNotEmpty) return true;
  final String? typed = (await textDialog(
    context,
    title: tr('members.nameTitle'),
    hint: tr('members.nameHint'),
    maxLength: 40,
  ))?.trim();
  if (typed == null || typed.isEmpty) return false;
  await ref.read(nameProvider.notifier).set(typed);
  return true;
}
