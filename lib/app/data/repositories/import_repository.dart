import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/debt_entry.dart';
import '../models/pending_item.dart';
import '../models/transaction_record.dart';

/// Pending imported items, the learned shop/payee -> category memory and the
/// device-local SMS scan point.
class ImportRepository {
  ImportRepository(this._database);

  final DatabaseService _database;

  static const _pending = 'pending_items';
  static const _learned = 'learned_categories';
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

  Future<void> addPending(List<PendingItem> items) async {
    if (items.isEmpty) return;
    await _database.db.transaction((txn) async {
      for (final item in items) {
        await txn.insert(_pending, item.toMap()..remove('id'));
      }
    });
    _database.notifyChanged();
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

  /// The remembered category for [key], unless that category is archived.
  Future<int?> learnedCategory(String key) async {
    final rows = await _database.db.rawQuery(
      'SELECT l.category_id AS category_id FROM $_learned l '
      'JOIN categories c ON c.id = l.category_id '
      'WHERE l.name_key = ? AND c.is_archived = 0',
      [key],
    );
    return rows.isEmpty ? null : rows.first['category_id'] as int;
  }

  // ---- Approval ----

  Future<TransactionRecord> approveAsTransaction(
      PendingItem item, TransactionRecord record) async {
    final id = await _database.db.transaction((txn) async {
      final id = await txn.insert('transactions', record.toMap()..remove('id'));
      await txn.delete(_pending, where: 'id = ?', whereArgs: [item.id]);
      final key = item.learnKey;
      if (key != null) {
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

  Future<DebtEntry> approveAsDebt(PendingItem item, DebtEntry entry) async {
    final id = await _database.db.transaction((txn) async {
      final id = await txn.insert('debt_entries', entry.toMap()..remove('id'));
      await txn.delete(_pending, where: 'id = ?', whereArgs: [item.id]);
      return id;
    });
    _database.notifyChanged();
    return entry.withId(id);
  }
}
