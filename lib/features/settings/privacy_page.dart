import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/plain_markdown.dart';

/// `PRIVACY.md` in English, `assets/privacy/<code>.md` otherwise.
final _policyProvider = FutureProvider.family<String, String>((
  Ref ref,
  String language,
) async {
  if (language == 'en') return rootBundle.loadString('PRIVACY.md');
  try {
    return await rootBundle.loadString('assets/privacy/$language.md');
  } on FlutterError {
    return rootBundle.loadString('PRIVACY.md');
  }
});

class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? policy = ref
        .watch(_policyProvider(context.locale.languageCode))
        .value;

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('about.privacy'))),
      body: policy == null ? const SizedBox.shrink() : PlainMarkdown(policy),
    );
  }
}
