import 'dart:collection';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

const String repositoryUrl = 'https://github.com/edvigsmirnov/sielto-app';

final FutureProvider<PackageInfo> appVersionProvider =
    FutureProvider<PackageInfo>((Ref ref) => PackageInfo.fromPlatform());

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

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final TextTheme text = Theme.of(context).textTheme;
    final PackageInfo? info = ref.watch(appVersionProvider).value;

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: sageAppBar(context, title: Text(tr('about.title'))),
      body: ListView(
        padding: scrollPadding(
          context,
          const EdgeInsets.symmetric(vertical: SageSpace.lg),
        ),
        children: <Widget>[
          Center(
            child: Image.asset(
              'assets/brand/splash_icon.png',
              width: 96,
              height: 96,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: SageSpace.md),
          Text(
            'Sielto',
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(color: sage.ink),
          ),
          if (info != null)
            Text(
              tr(
                'about.version',
                args: <String>[info.version, info.buildNumber],
              ),
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: sage.inkSecondary),
            ),
          const SizedBox(height: SageSpace.lg),
          LinkTile(
            icon: Icons.code,
            title: tr('about.source'),
            subtitle: repositoryUrl.substring('https://'.length),
            onTap: () => openLink(context, repositoryUrl),
          ),
          LinkTile(
            icon: Icons.gavel_outlined,
            title: tr('about.licence'),
            subtitle: tr('about.licenceBody'),
            onTap: () => pushPage<void>(context, const _LicencePage()),
          ),
          LinkTile(
            icon: Icons.article_outlined,
            title: tr('about.thirdParty'),
            onTap: () => pushPage<void>(context, const _PackagesPage()),
          ),
        ],
      ),
    );
  }
}

final FutureProvider<String> _licenceProvider = FutureProvider<String>(
  (Ref ref) => rootBundle.loadString('LICENSE'),
);

/// The project's LICENSE, its hard-wrapped lines joined so it reflows.
class _LicencePage extends ConsumerWidget {
  const _LicencePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SageColors sage = context.sage;
    final String? licence = ref.watch(_licenceProvider).value;

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: sageAppBar(context, title: Text(tr('about.licence'))),
      body: licence == null
          ? const SizedBox.shrink()
          : SelectionArea(
              child: ListView(
                padding: scrollPadding(
                  context,
                  const EdgeInsets.all(SageSpace.gutter),
                ),
                children: <Widget>[
                  for (final String paragraph in reflow(licence))
                    Padding(
                      padding: const EdgeInsets.only(bottom: SageSpace.md),
                      child: Text(
                        paragraph,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: sage.ink),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Every bundled package's licences, by package name.
final FutureProvider<Map<String, List<LicenseEntry>>> _packagesProvider =
    FutureProvider<Map<String, List<LicenseEntry>>>((Ref ref) async {
      final Map<String, List<LicenseEntry>> packages =
          SplayTreeMap<String, List<LicenseEntry>>(
            (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
          );
      await for (final LicenseEntry entry in LicenseRegistry.licenses) {
        for (final String package in entry.packages) {
          (packages[package] ??= <LicenseEntry>[]).add(entry);
        }
      }
      return packages;
    });

class _PackagesPage extends ConsumerWidget {
  const _PackagesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, List<LicenseEntry>>? packages = ref
        .watch(_packagesProvider)
        .value;
    final List<String> names = packages?.keys.toList() ?? <String>[];

    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('about.thirdParty'))),
      body: ListView.builder(
        padding: scrollPadding(
          context,
          const EdgeInsets.symmetric(vertical: SageSpace.md),
        ),
        itemCount: names.length,
        itemBuilder: (BuildContext context, int index) => LinkTile(
          title: names[index],
          onTap: () => pushPage<void>(
            context,
            _PackagePage(name: names[index], entries: packages![names[index]]!),
          ),
        ),
      ),
    );
  }
}

class _PackagePage extends StatelessWidget {
  const _PackagePage({required this.name, required this.entries});

  final String name;
  final List<LicenseEntry> entries;

  @override
  Widget build(BuildContext context) {
    final SageColors sage = context.sage;
    final TextStyle? style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: sage.ink);

    return Scaffold(
      backgroundColor: sage.surface,
      appBar: sageAppBar(context, title: Text(name)),
      body: SelectionArea(
        child: ListView(
          padding: scrollPadding(
            context,
            const EdgeInsets.all(SageSpace.gutter),
          ),
          children: <Widget>[
            for (final (int i, LicenseEntry entry)
                in entries.indexed) ...<Widget>[
              if (i > 0) const Divider(height: SageSpace.xl),
              for (final LicenseParagraph paragraph in entry.paragraphs)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: SageSpace.sm,
                    left: paragraph.indent == LicenseParagraph.centeredIndent
                        ? 0
                        : paragraph.indent * SageSpace.md,
                  ),
                  child: Text(
                    paragraph.text,
                    style: style,
                    textAlign:
                        paragraph.indent == LicenseParagraph.centeredIndent
                        ? TextAlign.center
                        : TextAlign.start,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Paragraphs of [text] with their line breaks dropped, except before a
/// numbered item.
List<String> reflow(String text) => <String>[
  for (final String paragraph in text.trim().split(RegExp(r'\n\s*\n')))
    paragraph
        .split('\n')
        .map((String line) => line.trim())
        .join('\n')
        .replaceAll(RegExp(r'\n(?!\d+\. )'), ' '),
];
