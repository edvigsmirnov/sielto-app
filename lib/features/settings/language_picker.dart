import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:sielto/core/l10n/app_locales.dart';
import 'package:sielto/core/ui/choice_field.dart';

/// Language sheet. Each language is listed under its own name.
Future<void> showLanguagePicker(BuildContext context) async {
  final (AppLocale,)? picked = await pickChoice<AppLocale>(
    context,
    title: tr('settings.language'),
    options: AppLocales.offered,
    value: AppLocales.resolve(context.locale),
    labelOf: (AppLocale language) => language.name,
  );
  if (picked == null || !context.mounted) return;
  await context.setLocale(picked.$1.locale);
}
