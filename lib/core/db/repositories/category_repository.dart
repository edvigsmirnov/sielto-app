import 'package:drift/drift.dart';
import 'package:sielto/core/db/app_database.dart';
import 'package:sielto/core/db/repositories/payment_repository.dart';
import 'package:sielto/core/db/synced_repository.dart';
import 'package:sielto/domain/value/enums.dart';

/// A rename of a category that has visible payments.
class CategoryTitleFrozen implements Exception {
  const CategoryTitleFrozen(this.categoryId);

  final String categoryId;

  @override
  String toString() => 'CategoryTitleFrozen: $categoryId';
}

/// An active category in the Space already has this title, in any case.
class CategoryTitleTaken implements Exception {
  const CategoryTitleTaken(this.title);

  final String title;

  @override
  String toString() => 'CategoryTitleTaken: $title';
}

class CategoryRepository extends SyncedRepository<$CategoriesTable, Category> {
  CategoryRepository({
    required super.db,
    required super.clock,
    required super.userId,
    required this.payments,
  });

  final PaymentRepository payments;

  @override
  TableInfo<$CategoriesTable, Category> get table => db.categories;

  /// Active categories in drag order.
  Future<List<Category>> inSpace(String spaceId) =>
      _selectInSpace(spaceId).get();

  Stream<List<Category>> watchInSpace(String spaceId) =>
      _selectInSpace(spaceId).watch();

  SimpleSelectStatement<$CategoriesTable, Category> _selectInSpace(
    String spaceId,
  ) =>
      selectAliveInSpace(spaceId)
        ..orderBy(<OrderClauseGenerator<$CategoriesTable>>[
          ($CategoriesTable t) => OrderingTerm(expression: t.sortOrder),
          ($CategoriesTable t) => OrderingTerm(expression: t.title),
        ]);

  /// Includes soft-deleted categories.
  Future<List<Category>> allEverInSpace(String spaceId) =>
      _selectAllEver(spaceId).get();

  Stream<List<Category>> watchAllEverInSpace(String spaceId) =>
      _selectAllEver(spaceId).watch();

  SimpleSelectStatement<$CategoriesTable, Category> _selectAllEver(
    String spaceId,
  ) =>
      db.select(db.categories)
        ..where(($CategoriesTable t) => t.spaceId.equals(spaceId));

  Future<Category> create({
    required String spaceId,
    required String title,
    String? color,
    String? icon,
    ExpenseType expenseType = ExpenseType.variable,
    int? sortOrder,
  }) async {
    await _refuseIfTaken(spaceId, title);
    final ({String author, DateTime editedAt}) s = stamp();
    return db
        .into(db.categories)
        .insertReturning(
          CategoriesCompanion.insert(
            id: SyncedRepository.newId(),
            spaceId: spaceId,
            title: title.trim(),
            color: Value<String?>(color),
            icon: Value<String?>(icon),
            expenseType: Value<ExpenseType>(expenseType),
            sortOrder: Value<int>(sortOrder ?? await _nextSortOrder(spaceId)),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: s.editedAt,
            createdAt: s.editedAt,
          ),
        );
  }

  /// Writes the starter set in the given order. Titles come translated.
  Future<void> createStarterSet(
    String spaceId,
    List<
      ({
        String key,
        String title,
        String? icon,
        String? color,
        ExpenseType type,
      })
    >
    starters,
  ) {
    final ({String author, DateTime editedAt}) s = stamp();
    return db.batch((Batch b) {
      b.insertAll(db.categories, <CategoriesCompanion>[
        for (int i = 0; i < starters.length; i++)
          CategoriesCompanion.insert(
            id: SyncedRepository.newId(),
            spaceId: spaceId,
            title: starters[i].title.trim(),
            starterKey: Value<String?>(starters[i].key),
            icon: Value<String?>(starters[i].icon),
            color: Value<String?>(starters[i].color),
            expenseType: Value<ExpenseType>(starters[i].type),
            sortOrder: Value<int>(i * PaymentRepository.sortOrderGap),
            syncStatus: const Value<SyncStatus>(SyncStatus.pending),
            lastModifiedBy: Value<String?>(s.author),
            clientEditedAt: s.editedAt,
            createdAt: s.editedAt,
          ),
      ]);
    });
  }

  /// False once a visible payment uses the category. [rename] enforces it.
  Future<bool> canRename(String categoryId) async =>
      !await payments.anyVisibleInCategory(categoryId);

  Future<int> rename(String categoryId, String title) async {
    if (!await canRename(categoryId)) {
      throw CategoryTitleFrozen(categoryId);
    }
    final Category? row =
        await (selectAlive()
              ..where(($CategoriesTable t) => t.id.equals(categoryId)))
            .getSingleOrNull();
    if (row != null) {
      await _refuseIfTaken(row.spaceId, title, except: categoryId);
    }
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.categories,
    )..where(($CategoriesTable t) => t.id.equals(categoryId))).write(
      CategoriesCompanion(
        title: Value<String>(title.trim()),
        starterKey: const Value<String?>(null),
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  /// Existing payments keep their own `expense_type`.
  Future<int> updateAppearance(
    String categoryId, {
    Value<String?> color = const Value<String?>.absent(),
    Value<String?> icon = const Value<String?>.absent(),
    Value<ExpenseType> expenseType = const Value<ExpenseType>.absent(),
    Value<int> sortOrder = const Value<int>.absent(),
  }) {
    final ({String author, DateTime editedAt}) s = stamp();
    return (db.update(
      db.categories,
    )..where(($CategoriesTable t) => t.id.equals(categoryId))).write(
      CategoriesCompanion(
        color: color,
        icon: icon,
        expenseType: expenseType,
        sortOrder: sortOrder,
        syncStatus: const Value<SyncStatus>(SyncStatus.pending),
        lastModifiedBy: Value<String?>(s.author),
        clientEditedAt: Value<DateTime>(s.editedAt),
      ),
    );
  }

  Future<int> _nextSortOrder(String spaceId) async {
    final List<Category> rows = await inSpace(spaceId);
    if (rows.isEmpty) return 0;
    return rows.last.sortOrder + PaymentRepository.sortOrderGap;
  }

  /// Throws [CategoryTitleTaken]. Also guarded by a unique index.
  Future<void> _refuseIfTaken(
    String spaceId,
    String title, {
    String? except,
  }) async {
    final String key = title.trim().toLowerCase();
    final List<Category> same = await (selectAliveInSpace(
      spaceId,
    )..where(($CategoriesTable t) => t.title.lower().equals(key))).get();
    if (same.any((Category c) => c.id != except)) {
      throw CategoryTitleTaken(title.trim());
    }
  }
}
