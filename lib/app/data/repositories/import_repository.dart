import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/debt_entry.dart';
import '../models/enums.dart';
import '../models/pending_item.dart';
import '../models/transaction_record.dart';

/// Thrown when approving an item whose pending row is already gone (a double
/// tap or a stale list): it was handled before, so nothing is written.
class PendingItemGoneException implements Exception {
  const PendingItemGoneException();
}

/// Pending imported items, what was last chosen for each shop or payee (a
/// category, or a debt person) and the device-local SMS scan point.
class ImportRepository {
  ImportRepository(this._database);

  final DatabaseService _database;

  static const _pending = 'pending_items';
  static const _learned = 'learned_categories';
  static const _learnedPeople = 'learned_people';
  static const _state = 'device_state';

  // ---- Scan point ----

  Future<DateTime?> scanPoint() async {
    final rows = await _database.db.query(_state, columns: ['last_sms_scan_at']);
    final value = rows.isEmpty ? null : rows.first['last_sms_scan_at'] as int?;
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// Moves the scan point forward; an earlier [at] is ignored.
  Future<void> setScanPoint(DateTime at) async {
    await _database.db.rawUpdate(
      'UPDATE $_state SET last_sms_scan_at = ? WHERE id = 1 '
      'AND (last_sms_scan_at IS NULL OR last_sms_scan_at < ?)',
      [at.millisecondsSinceEpoch, at.millisecondsSinceEpoch],
    );
  }

  // ---- Pending items ----

  /// Stores [items]; returns them with their new ids.
  Future<List<PendingItem>> addPending(List<PendingItem> items) async {
    if (items.isEmpty) return const [];
    final saved = await _database.db.transaction((txn) async {
      final saved = <PendingItem>[];
      for (final item in items) {
        final id = await txn.insert(_pending, item.toMap()..remove('id'));
        saved.add(item.withId(id));
      }
      return saved;
    });
    _database.notifyChanged();
    return saved;
  }

  /// Adds [items] and moves the scan point forward to [scanPoint] in one
  /// transaction, so a scan interrupted half-way never re-imports items.
  /// An earlier [scanPoint] is ignored, as in [setScanPoint].
  Future<void> addPendingAndAdvance(
      List<PendingItem> items, DateTime scanPoint) async {
    await _database.db.transaction((txn) async {
      for (final item in items) {
        await txn.insert(_pending, item.toMap()..remove('id'));
      }
      final at = scanPoint.millisecondsSinceEpoch;
      await txn.rawUpdate(
        'UPDATE $_state SET last_sms_scan_at = ? WHERE id = 1 '
        'AND (last_sms_scan_at IS NULL OR last_sms_scan_at < ?)',
        [at, at],
      );
    });
    if (items.isNotEmpty) _database.notifyChanged();
  }

  Future<List<PendingItem>> getPending() async {
    final rows =
        await _database.db.query(_pending, orderBy: 'occurred_at DESC, id DESC');
    return rows.map(PendingItem.fromMap).toList();
  }

  Future<int> pendingCount() async {
    final rows = await _database.db.rawQuery('SELECT COUNT(*) AS c FROM $_pending');
    return rows.first['c'] as int;
  }

  Future<void> dismiss(int id) async {
    await _database.db.delete(_pending, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Re-inserts a dismissed [item] under its original id (for Undo).
  Future<void> restore(PendingItem item) async {
    await _database.db.insert(_pending, item.toMap());
    _database.notifyChanged();
  }

  Future<void> update(PendingItem item) async {
    await _database.db.update(_pending, item.toMap()..remove('id'),
        where: 'id = ?', whereArgs: [item.id]);
    _database.notifyChanged();
  }

  // ---- Learned categories ----

  /// The remembered category for [key], if it is a [kind] category and not
  /// archived (a CliQ name may be learned from an incoming transfer and then
  /// seen in an outgoing one).
  Future<int?> learnedCategory(String key, TransactionKind kind) async {
    final rows = await _database.db.rawQuery(
      'SELECT l.category_id AS category_id FROM $_learned l '
      'JOIN categories c ON c.id = l.category_id '
      'WHERE l.name_key = ? AND c.kind = ? AND c.is_archived = 0',
      [key, kind.name],
    );
    return rows.isEmpty ? null : rows.first['category_id'] as int;
  }

  /// The debt person [key] was last approved for, if any.
  Future<int?> learnedPerson(String key) async {
    final rows = await _database.db.query(_learnedPeople,
        columns: ['person_id'], where: 'name_key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['person_id'] as int;
  }

  // ---- Approval ----

  /// Deletes [item]'s pending row inside [txn]; throws
  /// [PendingItemGoneException] (rolling the transaction back) when it was
  /// already gone.
  Future<void> _takePending(Transaction txn, PendingItem item) async {
    final deleted =
        await txn.delete(_pending, where: 'id = ?', whereArgs: [item.id]);
    if (deleted != 1) throw const PendingItemGoneException();
  }

  /// Writes [record] and removes [item] in one transaction. Throws
  /// [PendingItemGoneException] when [item] is no longer pending.
  Future<TransactionRecord> approveAsTransaction(
      PendingItem item, TransactionRecord record) async {
    final id = await _database.db.transaction((txn) async {
      await _takePending(txn, item);
      final id = await txn.insert('transactions', record.toMap()..remove('id'));
      final key = item.learnKey;
      if (key != null) {
        // The last choice wins: a category replaces a remembered person.
        await txn.delete(_learnedPeople,
            where: 'name_key = ?', whereArgs: [key]);
        await txn.insert(
          _learned,
          {'name_key': key, 'category_id': record.categoryId},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return id;
    });
    _database.notifyChanged();
    return record.withId(id);
  }

  /// Writes [entry] and removes [item] in one transaction. Throws
  /// [PendingItemGoneException] when [item] is no longer pending.
  Future<DebtEntry> approveAsDebt(PendingItem item, DebtEntry entry) async {
    final id = await _database.db.transaction((txn) async {
      await _takePending(txn, item);
      final id =
          await txn.insert('debt_entries', entry.toMap()..remove('id'));
      final key = item.learnKey;
      if (key != null) {
        // The last choice wins: a person replaces a remembered category.
        await txn.delete(_learned, where: 'name_key = ?', whereArgs: [key]);
        await txn.insert(
          _learnedPeople,
          {'name_key': key, 'person_id': entry.personId},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return id;
    });
    _database.notifyChanged();
    return entry.withId(id);
  }
}
