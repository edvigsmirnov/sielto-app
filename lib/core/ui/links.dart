import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser, or copies it when none opens.
Future<void> openLink(BuildContext context, String url) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  bool opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } on PlatformException {
    opened = false;
  }
  if (opened) return;
  await Clipboard.setData(ClipboardData(text: url));
  messenger.say(tr('about.linkCopied'));
}
