import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sielto/app/providers.dart';
import 'package:sielto/core/backup/backup_file.dart';
import 'package:sielto/core/backup/backup_service.dart';
import 'package:sielto/core/crypto/key_store.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/settings/settings_providers.dart';
import 'package:sielto/core/theme/sage_tokens.dart';
import 'package:sielto/core/ui/detail_host.dart';
import 'package:sielto/core/ui/dialogs.dart';
import 'package:sielto/core/ui/form_fields.dart';
import 'package:sielto/core/ui/layout.dart';
import 'package:sielto/core/ui/popover.dart';
import 'package:sielto/core/ui/sage_widgets.dart';
import 'package:sielto/features/backup/drive.dart';
import 'package:sielto/features/onboarding/onboarding_scaffold.dart';
import 'package:sielto/features/security/recovery_key.dart';

const MethodChannel _window = MethodChannel('sielto/window');

/// The Recovery Key and backups.
class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool keySet = ref.watch(recoveryKeySetProvider);
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('backup.title'))),
      body: ListView(
        padding: scrollPadding(
          context,
          const EdgeInsets.symmetric(vertical: SageSpace.md),
        ),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: Text(tr('recovery.title')),
            subtitle: Text(tr(keySet ? 'recovery.isSet' : 'recovery.notSet')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openRecoveryKeyPage(context),
          ),
          if (!keySet)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SageSpace.gutter,
                vertical: SageSpace.sm,
              ),
              child: Text(
                tr('recovery.notSetWarning'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (driveSupported) const _DriveSection(),
          SectionLabel(tr('backup.manual')),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: Text(tr('backup.export')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _export(context, ref),
          ),
          const _RestoreRow(),
        ],
      ),
    );
  }
}

Future<void> _openRecoveryKeyPage(BuildContext context) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const RecoveryKeyPage(),
      ),
    );

Future<void> _export(BuildContext context, WidgetRef ref) async {
  if (!ref.read(recoveryKeySetProvider)) {
    await _openRecoveryKeyPage(context);
    if (!ref.read(recoveryKeySetProvider) || !context.mounted) return;
  }
  final DatabaseKeyManager manager = ref.read(keyManagerProvider);
  String? recoveryKey = await manager.storedRecoveryKey();
  if (recoveryKey == null && context.mounted) {
    await showRecoveryKeyPrompt(
      context,
      onSubmit: (String typed) async {
        if (!await manager.checkRecoveryKey(typed)) return false;
        recoveryKey = typed;
        return true;
      },
    );
  }
  final String? key = recoveryKey;
  if (key == null || !context.mounted) return;

  final List<Space> spaces = ref.read(spaceListProvider).value ?? <Space>[];
  final Space? current = ref.read(currentSpaceProvider);
  Space? only;
  if (spaces.length > 1 && current != null) {
    final bool? all = await choiceDialog<bool>(
      context,
      title: tr('backup.exportWhat'),
      columns: 1,
      choices: <(String, bool)>[
        (plural('backup.exportAll', spaces.length), true),
        (tr('backup.exportOne', args: <String>[current.title]), false),
      ],
    );
    if (all == null || !context.mounted) return;
    if (!all) only = current;
  }

  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text(tr('recovery.working'))));
  final Uint8List bytes = await BackupFile.seal(
    await ref.read(repositoriesProvider).backup.export(spaceId: only?.id),
    key,
  );
  final String date = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final String name = 'sielto_$date.${BackupFile.extension}';
  messenger.hideCurrentSnackBar();

  if (Platform.isAndroid) {
    if (!context.mounted) return;
    final bool? toDevice = await choiceDialog<bool>(
      context,
      title: tr('backup.whereTo'),
      columns: 1,
      choices: <(String, bool)>[
        (tr('backup.toDevice'), true),
        (tr('backup.share'), false),
      ],
    );
    if (toDevice == null) return;
    if (toDevice) {
      final bool? saved = await _window.invokeMethod<bool>(
        'saveFile',
        <String, Object>{'name': name, 'bytes': bytes},
      );
      if (saved ?? false) {
        messenger.showSnackBar(SnackBar(content: Text(tr('backup.saved'))));
      }
      return;
    }
    final File file = File(p.join((await getTemporaryDirectory()).path, name))
      ..writeAsBytesSync(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path)],
        fileNameOverrides: <String>[name],
      ),
    );
    return;
  }
  final FileSaveLocation? target = await getSaveLocation(suggestedName: name);
  if (target == null) return;
  File(target.path).writeAsBytesSync(bytes, flush: true);
  messenger.showSnackBar(SnackBar(content: Text(tr('backup.saved'))));
}

/// Picks a backup and walks through the restore.
/// [fromDrive] skips asking where the backup is.
Future<void> restoreBackup(
  BuildContext context,
  WidgetRef ref, {
  bool? fromDrive,
  bool inSetup = false,
}) async {
  final Uint8List? bytes = await pickBackup(context, fromDrive: fromDrive);
  if (bytes == null || !context.mounted) return;
  final BackupService service = ref.read(repositoriesProvider).backup;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: inSetup ? const RouteSettings(name: fullWindowRoute) : null,
      builder: (BuildContext _) => RestorePage(
        inSetup: inSetup,
        bytes: bytes,
        conflictsOf: service.conflicts,
        onRestore:
            (
              BackupContents backup,
              String recoveryKey,
              Map<String, RestoreChoice> choices,
            ) async {
              final String date = DateFormat.MMMd(context.locale.toString())
                  .format(backup.createdAt.toLocal());
              await service.restore(
                backup,
                choices,
                copyTitle: (String title) =>
                    tr('backup.copyTitle', args: <String>[title, date]),
              );
              if (!ref.read(recoveryKeySetProvider)) {
                await ref
                    .read(recoveryKeySetProvider.notifier)
                    .set(recoveryKey);
              }
            },
      ),
    ),
  );
}

/// A file, or a Drive snapshot where Drive is available. Null when cancelled.
Future<Uint8List?> pickBackup(BuildContext context, {bool? fromDrive}) async {
  if (!driveSupported) return pickBackupFile(context);
  fromDrive ??= await showAdaptiveSheet<bool>(
    context,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(tr('backup.fromFile')),
            onTap: () => Navigator.of(context).pop(false),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: Text(tr('drive.fromDrive')),
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ),
  );
  if (fromDrive == null || !context.mounted) return null;
  if (!fromDrive) return pickBackupFile(context);
  if (ProviderScope.containerOf(context).read(offlineModeProvider)) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('storage.offlineMode'))));
    return null;
  }
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute<Uint8List>(
      builder: (BuildContext _) => const DriveSnapshotsPage(),
    ),
  );
}

/// Null when cancelled or when the file is not a backup, which says so.
Future<Uint8List?> pickBackupFile(BuildContext context) async {
  // Android cannot filter by an unknown extension; the signature decides.
  final XFile? file = await openFile(
    acceptedTypeGroups: <XTypeGroup>[
      if (!Platform.isAndroid)
        XTypeGroup(
          label: 'Sielto',
          extensions: const <String>[BackupFile.extension],
        ),
    ],
  );
  if (file == null) return null;
  final Uint8List bytes = await file.readAsBytes();
  if (BackupFile.looksLikeBackup(bytes)) return bytes;
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('backup.problem.notABackup'))));
  }
  return null;
}

typedef RestoreAction = Future<void> Function(
  BackupContents backup,
  String recoveryKey,
  Map<String, RestoreChoice> choices,
);

/// Recovery Key first, then a choice for every Space that exists here.
class RestorePage extends StatefulWidget {
  const RestorePage({
    required this.bytes,
    required this.conflictsOf,
    required this.onRestore,
    this.inSetup = false,
    super.key,
  });

  /// Opened from onboarding: wide, the setup card.
  final bool inSetup;

  final Uint8List bytes;
  final Future<Set<String>> Function(BackupContents backup) conflictsOf;
  final RestoreAction onRestore;

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  final TextEditingController _key = TextEditingController();
  BackupContents? _backup;
  Set<String> _conflicts = <String>{};
  final Map<String, RestoreChoice> _choices = <String, RestoreChoice>{};
  BackupFileProblem? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_key.text.isEmpty) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final BackupContents backup = BackupContents(
        await BackupFile.open(widget.bytes, _key.text),
      );
      final Set<String> conflicts = await widget.conflictsOf(backup);
      setState(() {
        _backup = backup;
        _conflicts = conflicts;
        for (final String id in conflicts) {
          _choices[id] = RestoreChoice.skip;
        }
      });
    } on BackupFileException catch (e) {
      setState(() => _problem = e.problem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupContents backup) async {
    setState(() => _busy = true);
    await widget.onRestore(backup, _key.text, _choices);
    if (!mounted) return;
    final int count = backup.spaces
        .where(
          (({String id, String title}) s) =>
              _choices[s.id] != RestoreChoice.skip,
        )
        .length;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(plural('backup.restored', count))));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final BackupContents? backup = _backup;
    final Widget action = backup == null
        ? ListenableBuilder(
            listenable: _key,
            builder: (BuildContext context, Widget? _) => FilledButton(
              onPressed: _busy || _key.text.isEmpty ? null : _open,
              child: Text(tr(_busy ? 'recovery.working' : 'common.continue')),
            ),
          )
        : FilledButton(
            onPressed: _busy ? null : () => _restore(backup),
            child: Text(
              tr(_busy ? 'recovery.working' : 'backup.restoreAction'),
            ),
          );
    final List<Widget> content = <Widget>[
      if (backup == null) ...<Widget>[
        Text(tr('backup.keyWhy'), style: text.bodyMedium),
        const SizedBox(height: SageSpace.lg),
        LabelledField(
          label: tr('recovery.title'),
          child: SecretField(
            controller: _key,
            autofocus: true,
            errorText: _problem == null
                ? null
                : tr('backup.problem.${_problem!.name}'),
            onSubmitted: (_) => _open(),
          ),
        ),
      ] else ...<Widget>[
        Text(
          tr(
            'backup.madeOn',
            args: <String>[
              DateFormat.yMMMd(context.locale.toString())
                  .add_Hm()
                  .format(backup.createdAt.toLocal()),
            ],
          ),
          style: text.bodySmall,
        ),
        const SizedBox(height: SageSpace.md),
        for (final ({String id, String title}) space in backup.spaces)
          Padding(
            padding: const EdgeInsets.only(bottom: SageSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(space.title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  tr(
                    _conflicts.contains(space.id)
                        ? 'backup.alreadyHere'
                        : 'backup.willAdd',
                  ),
                  style: text.bodySmall,
                ),
                if (_conflicts.contains(space.id)) ...<Widget>[
                  const SizedBox(height: SageSpace.sm),
                  SegmentedChoice<RestoreChoice>(
                    values: RestoreChoice.values,
                    selected: _choices[space.id]!,
                    labelOf: (RestoreChoice c) => tr('backup.choice.${c.name}'),
                    onChanged: (RestoreChoice c) =>
                        setState(() => _choices[space.id] = c),
                  ),
                ],
              ],
            ),
          ),
      ],
    ];
    if (widget.inSetup && isWide(context)) {
      return Scaffold(
        backgroundColor: context.sage.surface,
        body: SetupCard(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const BackButton(),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        tr('backup.restore'),
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                    ),
                  ),
                  const SizedBox(width: kMinInteractiveDimension),
                ],
              ),
              const SizedBox(height: SageSpace.md),
              ...content,
              const SizedBox(height: SageSpace.lg),
              action,
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: context.sage.surface,
      appBar: sageAppBar(context, title: Text(tr('backup.restore'))),
      bottomNavigationBar: FormActionBar(child: action),
      body: ListView(
        padding: scrollPadding(
          context,
          const EdgeInsets.all(SageSpace.formGutter),
        ),
        children: content,
      ),
    );
  }
}

class _DriveSection extends ConsumerWidget {
  const _DriveSection();

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    if (!ref.read(recoveryKeySetProvider)) {
      await _openRecoveryKeyPage(context);
      if (!ref.read(recoveryKeySetProvider)) return;
    }
    final bool connected = await ref.read(driveProvider.notifier).connect();
    if (!connected && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('drive.failed'))));
    }
  }

  Future<void> _backUpNow(BuildContext context, WidgetRef ref) async {
    final bool done = await ref
        .read(driveProvider.notifier)
        .backUp(interactive: true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(done ? 'drive.done' : 'drive.failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DriveState drive = ref.watch(driveProvider);
    final String? email = drive.email;
    final DateTime? last = drive.lastBackup;
    final bool offline = ref.watch(offlineModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(tr('drive.section')),
        if (email == null)
          ListTile(
            leading: const Icon(Icons.add_to_drive_outlined),
            title: Text(tr('drive.connect')),
            subtitle: Text(
              tr(offline ? 'common.blockedByOffline' : 'drive.connectHint'),
            ),
            enabled: !offline,
            onTap: () => _connect(context, ref),
          )
        else ...<Widget>[
          ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: const Text('Google Drive'),
            subtitle: Text(email),
            trailing: TextButton(
              onPressed: drive.busy || offline
                  ? null
                  : () => ref.read(driveProvider.notifier).disconnect(),
              child: Text(tr('drive.disconnect')),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(tr('drive.lastBackup')),
            subtitle: Text(
              last == null
                  ? tr('drive.never')
                  : DateFormat.yMMMd(context.locale.toString())
                        .add_Hm()
                        .format(last.toLocal()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: Text(tr(drive.busy ? 'recovery.working' : 'drive.now')),
            subtitle: offline ? Text(tr('common.blockedByOffline')) : null,
            enabled: !drive.busy && !offline,
            onTap: () => _backUpNow(context, ref),
          ),
        ],
      ],
    );
  }
}

/// Wide, the row opens the two sources under itself; a second click closes
/// them.
class _RestoreRow extends ConsumerStatefulWidget {
  const _RestoreRow();

  @override
  ConsumerState<_RestoreRow> createState() => _RestoreRowState();
}

class _RestoreRowState extends ConsumerState<_RestoreRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bool inline = isWide(context) && driveSupported;
    return Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.settings_backup_restore_outlined),
          title: Text(tr('backup.restore')),
          trailing: Icon(
            inline && _open ? Icons.expand_less : Icons.chevron_right,
          ),
          onTap: inline
              ? () => setState(() => _open = !_open)
              : () => restoreBackup(context, ref),
        ),
        if (inline) RestoreOptions(open: _open, indent: true),
      ],
    );
  }
}

/// The two places a backup can come from, sliding open under their button.
class RestoreOptions extends ConsumerWidget {
  const RestoreOptions({
    required this.open,
    this.indent = false,
    this.inSetup = false,
    super.key,
  });

  final bool open;
  final bool inSetup;

  /// As list rows in line with a row's title; otherwise two buttons.
  final bool indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnimatedSize(
    duration: MediaQuery.disableAnimationsOf(context)
        ? const Duration(milliseconds: 1)
        : const Duration(milliseconds: 150),
    alignment: Alignment.topCenter,
    child: !open
        ? const SizedBox(width: double.infinity)
        : indent
        ? Padding(
            padding: const EdgeInsets.only(left: SageSpace.xl),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(tr('backup.fromFile')),
                  onTap: () => restoreBackup(
                    context,
                    ref,
                    fromDrive: false,
                    inSetup: inSetup,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(tr('drive.fromDrive')),
                  onTap: () => restoreBackup(
                    context,
                    ref,
                    fromDrive: true,
                    inSetup: inSetup,
                  ),
                ),
              ],
            ),
          )
        // Two equal buttons, under a centred one.
        : Padding(
            padding: const EdgeInsets.only(top: SageSpace.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(tr('backup.fromFile')),
                    onPressed: () => restoreBackup(
                      context,
                      ref,
                      fromDrive: false,
                      inSetup: inSetup,
                    ),
                  ),
                ),
                const SizedBox(width: SageSpace.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text(tr('drive.fromDrive')),
                    onPressed: () => restoreBackup(
                      context,
                      ref,
                      fromDrive: true,
                      inSetup: inSetup,
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}
