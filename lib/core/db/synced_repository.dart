import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/time/space_clock.dart';
import 'package:uuid/uuid.dart';

/// Base for repositories over syncable tables. Reads exclude soft-deleted
/// rows; writes stamp `client_edited_at` and mark the row pending.
abstract class SyncedRepository<T extends Table, D extends DataClass> {
  SyncedRepository({
    required this.db,
    required this.clock,
    required this.userId,
  });

  static const Uuid _uuid = Uuid();

  final AppDatabase db;
  final SpaceClock clock;

  /// Local user id, generated at first install. Author of each edit.
  final String userId;

  TableInfo<T, D> get table;

  static String newId() => _uuid.v4();

  /// Edit time of rows the app fills in by itself, so any real edit wins.
  static final DateTime generated = DateTime.utc(2000);

  /// The same id on every device for the same [slot].
  static String slotId(String slot) =>
      _uuid.v5(Namespace.url.value, 'sielto:$slot');

  // Every syncable table mixes in `SyncColumns`; schema_test checks it.
  GeneratedColumn<bool> get _isDeleted =>
      table.columnsByName['is_deleted']! as GeneratedColumn<bool>;

  GeneratedColumn<String> get _id =>
      table.columnsByName['id']! as GeneratedColumn<String>;

  GeneratedColumn<String> get _spaceId =>
      table.columnsByName['space_id']! as GeneratedColumn<String>;

  Expression<bool> get notDeleted => _isDeleted.equals(false);

  SimpleSelectStatement<T, D> selectAlive() =>
      db.select(table)..where((T _) => notDeleted);

  SimpleSelectStatement<T, D> selectAliveInSpace(String spaceId) =>
      db.select(table)..where((T _) => notDeleted & _spaceId.equals(spaceId));

  ({DateTime editedAt, String author}) stamp() =>
      (editedAt: clock.nowUtc(), author: userId);

  /// [values] marked as this user's pending edit, made now.
  Insertable<D> stamped(Insertable<D> values) {
    final ({String author, DateTime editedAt}) s = stamp();
    return RawValuesInsertable<D>(<String, Expression<Object>>{
      ...values.toColumns(true),
      'sync_status': const Constant<String>('pending'),
      'client_edited_at': Variable<DateTime>(s.editedAt),
      'last_modified_by': Variable<String>(s.author),
    });
  }

  /// Soft delete; the row stays so the deletion syncs.
  Future<int> softDelete(String id) => _setDeleted(id, deleted: true);

  Future<int> restore(String id) => _setDeleted(id, deleted: false);

  Future<int> _setDeleted(String id, {required bool deleted}) =>
      (db.update(table)..where((T _) => _id.equals(id))).write(
        stamped(
          RawValuesInsertable<D>(<String, Expression<Object>>{
            'is_deleted': Constant<bool>(deleted),
          }),
        ),
      );
}
