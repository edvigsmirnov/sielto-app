import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/domain/period/freeze.dart';
import 'package:sielto/domain/value/calendar_date.dart';
import 'package:sielto/domain/value/enums.dart';
import 'package:supabase/supabase.dart';

enum ChangeKind { added, edited, paid, deleted }

/// How another member's later edit met this user's own, or how the server
/// refused it in a closed period.
enum ConflictKind {
  overwritten,
  deletedOverEdit,
  editOverDelete,
  refused,
  refusedDeletion,
}

/// A payment or income another member changed, as it arrived here.
typedef RemoteChange = ({
  String spaceId,
  bool income,
  ChangeKind kind,
  String title,
  Decimal? amount,
  CalendarDate date,
  String author,
  ConflictKind? conflict,
  DateTime? mine,
  DateTime theirs,
});

/// Uploads the pending rows of cloud Spaces, then downloads what changed on
/// the server. The later `client_edited_at` wins, here and on the server.
class SyncWorker {
  SyncWorker({
    required this.db,
    required this.client,
    this.deviceName,
    this.userId,
    this.onRemote,
  });

  final AppDatabase db;
  final SupabaseClient client;

  /// Changes by anyone else are collected in [changes].
  final String? userId;

  /// Fires before such a change is written.
  final void Function(String spaceId)? onRemote;

  /// What other members changed during the last [syncAll].
  final List<RemoteChange> changes = <RemoteChange>[];

  /// Edit times of the rows this run uploaded.
  final Map<String, DateTime> _pushed = <String, DateTime>{};

  /// Names this device on the server if it has no name yet.
  final Future<String?>? deviceName;

  /// Parents first.
  static const List<String> records = <String>[
    'categories',
    'budget_periods',
    'income_recurrence_rules',
    'incomes',
    'payments',
  ];

  static const Set<String> _localOnly = <String>{
    'sync_status',
    'storage_mode',
    'is_archived',
    'synced_until',
  };

  /// The server grants updates to these `spaces` columns only.
  static const List<String> _spaceEditable = <String>[
    'title',
    'space_type',
    'country_code',
    'timezone',
    'currency_code',
    'max_members',
    'manual_balance',
    'manual_balance_updated_at',
    'min_schema_version',
    'feed_order_mode',
    'client_edited_at',
  ];

  static const int _page = 1000;

  /// Rows committed out of order carry an earlier receipt time.
  static const Duration _overlap = Duration(minutes: 1);

  /// False when this device has been unlinked; nothing is synced then.
  Future<bool> syncAll() async {
    if (!await touch()) return false;
    changes.clear();
    _pushed.clear();
    final List<Map<String, dynamic>> remote = await client
        .from('spaces')
        .select();
    await _apply('spaces', remote);
    await _archiveVanished(<String>{
      for (final Map<String, dynamic> r in remote) r['id'] as String,
    });
    final List<Space> spaces =
        await (db.select(db.spaces)..where(
              ($SpacesTable t) =>
                  t.storageMode.equalsValue(StorageMode.cloud) &
                  t.isArchived.equals(false),
            ))
            .get();
    for (final Space space in spaces) {
      await syncSpace(space.id);
    }
    return true;
  }

  /// Marks this device active; false once it has been unlinked.
  Future<bool> touch() async => client.rpc<bool>(
    'touch_device',
    params: <String, String?>{'p_display_name': await deviceName},
  );

  /// [onChange] fires for every server change to a row this user can read.
  RealtimeChannel watchRemote(void Function() onChange) {
    RealtimeChannel channel = client.channel('sync');
    for (final String table in <String>['spaces', ...records]) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (PostgresChangePayload _) => onChange(),
      );
    }
    return channel.subscribe();
  }

  /// True when a cloud Space here is gone from the server.
  Future<bool> anyVanished() async {
    final List<Map<String, dynamic>> remote = await client
        .from('spaces')
        .select('id');
    final Set<String> onServer = <String>{
      for (final Map<String, dynamic> r in remote) r['id'] as String,
    };
    final List<Space> here =
        await (db.select(db.spaces)..where(
              ($SpacesTable t) =>
                  t.storageMode.equalsValue(StorageMode.cloud) &
                  t.serverReceivedAt.isNotNull(),
            ))
            .get();
    return here.any((Space s) => !onServer.contains(s.id));
  }

  /// Spaces the last [syncAll] archived.
  final List<String> vanished = <String>[];

  /// Cloud Spaces gone from the server become local archives.
  Future<void> _archiveVanished(Set<String> onServer) async {
    vanished.clear();
    final List<Space> gone =
        await (db.select(db.spaces)..where(
              ($SpacesTable t) =>
                  t.storageMode.equalsValue(StorageMode.cloud) &
                  t.serverReceivedAt.isNotNull() &
                  t.id.isNotIn(onServer),
            ))
            .get();
    for (final Space space in gone) {
      await (db.update(
        db.spaces,
      )..where(($SpacesTable t) => t.id.equals(space.id))).write(
        const SpacesCompanion(
          storageMode: Value<StorageMode>(StorageMode.local),
          isArchived: Value<bool>(true),
          syncStatus: Value<SyncStatus>(SyncStatus.none),
          serverReceivedAt: Value<DateTime?>(null),
          syncedUntil: Value<DateTime?>(null),
        ),
      );
      vanished.add(space.id);
    }
  }

  Future<void> syncSpace(String spaceId) async {
    await _pushSpace(spaceId);
    for (final String table in records) {
      await _push(table, spaceId);
    }
    await _pull(spaceId);
  }

  Future<void> _pushSpace(String spaceId) async {
    final List<QueryRow> rows = await _pending('spaces', 'id', spaceId);
    if (rows.isEmpty) return;
    final Map<String, Object?> json = _toServer('spaces', rows.single);
    json['client_edited_at'] ??= json['created_at'];

    final List<Map<String, dynamic>> updated = await client
        .from('spaces')
        .update(<String, Object?>{
          for (final String c in _spaceEditable) c: json[c],
        })
        .eq('id', spaceId)
        .select('id');
    if (updated.isEmpty) {
      try {
        await client.from('spaces').insert(json);
      } on PostgrestException catch (e) {
        // The row exists and holds a later edit.
        if (e.code != '23505') rethrow;
      }
    }
    await _mark('spaces', rows, SyncStatus.synced);
  }

  /// Rows the app filled in by itself are insert-only: they never overwrite.
  Future<void> _push(String table, String spaceId) async {
    final List<QueryRow> rows = await _pending(table, 'space_id', spaceId);
    final List<QueryRow> sent = <QueryRow>[];
    final List<QueryRow> rejected = <QueryRow>[];
    for (final bool generated in <bool>[false, true]) {
      final List<QueryRow> group = <QueryRow>[
        for (final QueryRow r in rows)
          if (_isGenerated(r) == generated) r,
      ];
      for (int i = 0; i < group.length; i += _page) {
        final List<QueryRow> chunk = group.sublist(
          i,
          i + _page > group.length ? group.length : i + _page,
        );
        try {
          await client.from(table).upsert(<Map<String, Object?>>[
            for (final QueryRow r in chunk) _toServer(table, r),
          ], ignoreDuplicates: generated);
          sent.addAll(chunk);
        } on PostgrestException {
          // One refused row must not hold back the rest.
          for (final QueryRow r in chunk) {
            try {
              await client
                  .from(table)
                  .upsert(_toServer(table, r), ignoreDuplicates: generated);
              sent.add(r);
            } on PostgrestException catch (e) {
              if (e.message == 'period_frozen') rejected.add(r);
            }
          }
        }
      }
    }
    for (final QueryRow r in sent) {
      if (_editedAt(r.data['client_edited_at']) case final DateTime at) {
        _pushed[r.data['id'] as String] = at;
      }
    }
    await _mark(table, sent, SyncStatus.synced);
    await _mark(table, rejected, SyncStatus.rejected);
    for (final QueryRow r in rejected) {
      final bool deletion = r.read<bool>('is_deleted');
      changes.add(_refusal(table, r, deletion: deletion));
      // A deleted entry shows no row that could carry the mark.
      if (deletion) await takeServer(table, r.data['id'] as String);
    }
  }

  RemoteChange _refusal(String table, QueryRow r, {required bool deletion}) {
    final bool income = table == 'incomes';
    final String? amount = r.data['amount'] as String?;
    return (
      spaceId: r.data['space_id'] as String,
      income: income,
      kind: deletion ? ChangeKind.deleted : ChangeKind.edited,
      title: r.data['title'] as String,
      amount: amount == null ? null : Decimal.parse(amount),
      date: CalendarDate.parse(
        (income
                ? r.data['actual_date'] ?? r.data['expected_date']
                : r.data['due_date'])
            as String,
      ),
      author: userId ?? '',
      conflict: deletion ? ConflictKind.refusedDeletion : ConflictKind.refused,
      mine: _editedAt(r.data['client_edited_at']),
      theirs: _editedAt(r.data['client_edited_at']) ?? DateTime.now(),
    );
  }

  /// Replaces a refused row with the server's version. With [note], that text
  /// is appended to the server's note and uploaded. False when unreachable.
  Future<bool> takeServer(
    String table,
    String id, {
    String? note,
    CalendarDate? on,
  }) async {
    final Map<String, dynamic>? remote = await client
        .from(table)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (remote == null) return false;
    await db.customUpdate(
      "UPDATE $table SET sync_status = 'synced' WHERE id = ?",
      variables: <Variable<Object>>[Variable<String>(id)],
    );
    await _apply(table, <Map<String, dynamic>>[remote]);
    if (note != null && on != null) {
      await db.customUpdate(
        'UPDATE $table SET notes = ?, client_edited_at = ?, '
        "sync_status = 'pending' WHERE id = ?",
        variables: <Variable<Object>>[
          Variable<String>(
            FreezeEvaluator.appendNote(remote['notes'] as String?, note, on),
          ),
          Variable<DateTime>(DateTime.now().toUtc()),
          Variable<String>(id),
        ],
        updates: <TableInfo<Table, dynamic>>{_table(table)},
      );
    }
    return true;
  }

  bool _isGenerated(QueryRow row) =>
      _editedAt(row.data['client_edited_at']) == SyncedRepository.generated;

  DateTime? _editedAt(Object? raw) =>
      db.typeMapping.read(DriftSqlType.dateTime, raw);

  Future<void> _pull(String spaceId) async {
    final Space space = await (db.select(
      db.spaces,
    )..where(($SpacesTable t) => t.id.equals(spaceId))).getSingle();
    final DateTime? since = space.syncedUntil?.subtract(_overlap);
    // The first download is everything, not news.
    final bool notice = since != null;
    DateTime? newest = space.syncedUntil;

    for (final String table in records) {
      for (int from = 0; ; from += _page) {
        PostgrestFilterBuilder<List<Map<String, dynamic>>> query = client
            .from(table)
            .select()
            .eq('space_id', spaceId);
        if (since != null) {
          query = query.gt(
            'server_received_at',
            since.toUtc().toIso8601String(),
          );
        }
        final List<Map<String, dynamic>> rows = await query
            .order('server_received_at', ascending: true)
            .order('id', ascending: true)
            .range(from, from + _page - 1);
        await _apply(table, rows, notice: notice);
        for (final Map<String, dynamic> r in rows) {
          final DateTime received = DateTime.parse(
            r['server_received_at'] as String,
          );
          if (newest == null || received.isAfter(newest)) newest = received;
        }
        if (rows.length < _page) break;
      }
    }

    if (newest != space.syncedUntil) {
      await (db.update(db.spaces)
            ..where(($SpacesTable t) => t.id.equals(spaceId)))
          .write(SpacesCompanion(syncedUntil: Value<DateTime?>(newest)));
    }
  }

  /// Writes [rows] unless the local row is pending with a later edit.
  Future<void> _apply(
    String table,
    List<Map<String, dynamic>> rows, {
    bool notice = false,
  }) => db.transaction(() async {
    final TableInfo<Table, dynamic> info = _table(table);
    for (final Map<String, dynamic> remote in rows) {
      final QueryRow? local = await db
          .customSelect(
            'SELECT * FROM $table WHERE id = ?',
            variables: <Variable<Object>>[
              Variable<String>(remote['id'] as String),
            ],
          )
          .getSingleOrNull();
      if (local?.read<String>('sync_status') == 'rejected') continue;
      if (local != null && local.read<String>('sync_status') == 'pending') {
        final DateTime? mine = local.readNullable<DateTime>('client_edited_at');
        final DateTime theirs = DateTime.parse(
          remote['client_edited_at'] as String,
        );
        if (mine != null && mine.isAfter(theirs)) continue;
      }
      if (notice && (table == 'payments' || table == 'incomes')) {
        if (_changeOf(table, remote, local) case final RemoteChange change) {
          onRemote?.call(change.spaceId);
          changes.add(change);
        }
      }

      final List<GeneratedColumn<Object>> columns = <GeneratedColumn<Object>>[
        for (final GeneratedColumn<Object> c in info.$columns)
          if (remote.containsKey(c.name) && !_localOnly.contains(c.name)) c,
      ];
      final List<String> names = <String>[
        for (final GeneratedColumn<Object> c in columns) c.name,
        'sync_status',
        if (table == 'spaces') 'storage_mode',
      ];
      await db.customInsert(
        'INSERT INTO $table (${names.join(', ')}) '
        'VALUES (${List<String>.filled(names.length, '?').join(', ')}) '
        'ON CONFLICT (id) DO UPDATE SET '
        '${names.where((String n) => n != 'storage_mode').map((String n) => '$n = excluded.$n').join(', ')}',
        variables: <Variable<Object>>[
          for (final GeneratedColumn<Object> c in columns)
            _decode(c, remote[c.name]),
          const Variable<String>('synced'),
          if (table == 'spaces') const Variable<String>('cloud'),
        ],
        updates: <TableInfo<Table, dynamic>>{info},
      );
    }
  });

  /// Null for this user's own edits, rows the app filled in by itself and
  /// rows already here as they are.
  RemoteChange? _changeOf(
    String table,
    Map<String, dynamic> remote,
    QueryRow? local,
  ) {
    final String? author = remote['last_modified_by'] as String?;
    final DateTime theirs = DateTime.parse(
      remote['client_edited_at'] as String,
    );
    if (userId == null || author == null || author == userId) return null;
    if (theirs == SyncedRepository.generated) return null;
    final DateTime? before = _editedAt(local?.data['client_edited_at']);
    if (before == theirs) return null;

    final bool gone = remote['is_deleted'] as bool;
    final bool wasGone = local != null && local.read<bool>('is_deleted');
    final bool paid = remote['is_paid'] as bool;
    final bool wasPaid = local != null && local.read<bool>('is_paid');
    if (gone && (local == null || wasGone)) return null;
    final ChangeKind kind = local == null || wasGone
        ? ChangeKind.added
        : gone
        ? ChangeKind.deleted
        : paid && !wasPaid
        ? ChangeKind.paid
        : ChangeKind.edited;

    final String id = remote['id'] as String;
    final DateTime? mine =
        _pushed[id] ??
        (local?.read<String>('sync_status') == 'pending' ? before : null);
    final bool clash = mine != null && theirs.isAfter(mine);
    final bool income = table == 'incomes';
    final String? amount = remote['amount'] as String?;
    return (
      spaceId: remote['space_id'] as String,
      income: income,
      kind: kind,
      title: remote['title'] as String,
      amount: amount == null ? null : Decimal.parse(amount),
      date: CalendarDate.parse(
        (income
                ? remote['actual_date'] ?? remote['expected_date']
                : remote['due_date'])
            as String,
      ),
      author: author,
      conflict: !clash
          ? null
          : gone
          ? ConflictKind.deletedOverEdit
          : wasGone
          ? ConflictKind.editOverDelete
          : ConflictKind.overwritten,
      mine: clash ? mine : null,
      theirs: theirs,
    );
  }

  Future<List<QueryRow>> _pending(
    String table,
    String column,
    String spaceId,
  ) => db
      .customSelect(
        "SELECT * FROM $table WHERE $column = ? AND sync_status = 'pending'",
        variables: <Variable<Object>>[Variable<String>(spaceId)],
      )
      .get();

  /// Skips a row edited again since it was read.
  Future<void> _mark(
    String table,
    List<QueryRow> rows,
    SyncStatus status,
  ) => db.transaction(() async {
    for (final QueryRow r in rows) {
      await db.customUpdate(
        'UPDATE $table SET sync_status = ? '
        "WHERE id = ? AND client_edited_at IS ? AND sync_status = 'pending'",
        variables: <Variable<Object>>[
          Variable<String>(status.name),
          Variable<String>(r.data['id'] as String),
          Variable<Object>(r.data['client_edited_at']),
        ],
        updates: <TableInfo<Table, dynamic>>{_table(table)},
      );
    }
  });

  TableInfo<Table, dynamic> _table(String name) => db.allTables.firstWhere(
    (TableInfo<Table, dynamic> t) => t.actualTableName == name,
  );

  Map<String, Object?> _toServer(
    String table,
    QueryRow row,
  ) => <String, Object?>{
    for (final GeneratedColumn<Object> c in _table(table).$columns)
      if (!_localOnly.contains(c.name)) c.name: _encode(c, row.data[c.name]),
  };

  Object? _encode(GeneratedColumn<Object> column, Object? raw) {
    if (raw == null) return null;
    return switch (column.type) {
      DriftSqlType.bool => db.typeMapping.read(DriftSqlType.bool, raw),
      DriftSqlType.dateTime =>
        db.typeMapping
            .read(DriftSqlType.dateTime, raw)!
            .toUtc()
            .toIso8601String(),
      _ => raw,
    };
  }

  Variable<Object> _decode(GeneratedColumn<Object> column, Object? value) {
    if (value == null) return const Variable<Object>(null);
    return switch (column.type) {
      DriftSqlType.bool => Variable<bool>(value as bool),
      DriftSqlType.dateTime => Variable<DateTime>(
        DateTime.parse(value as String),
      ),
      _ => Variable<Object>(value),
    };
  }
}
