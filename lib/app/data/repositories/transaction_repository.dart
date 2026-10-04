import '../../core/utils/date_utils.dart';
import '../../services/database_service.dart';
import '../models/transaction_record.dart';

class TransactionRepository {
  TransactionRepository(this._database);

  final DatabaseService _database;

  static const _table = 'transactions';
  static const _newestFirst = 'date DESC, created_at DESC, id DESC';

  Future<TransactionRecord> add(TransactionRecord record) async {
    final id = await _database.db.insert(_table, record.toMap()..remove('id'));
    _database.notifyChanged();
    return record.withId(id);
  }

  Future<void> update(TransactionRecord record) async {
    await _database.db.update(_table, record.toMap(),
        where: 'id = ?', whereArgs: [record.id]);
    _database.notifyChanged();
  }

  Future<void> delete(int id) async {
    await _database.db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Puts back a deleted record with its original id (used by Undo).
  Future<void> restore(TransactionRecord record) async {
    await _database.db.insert(_table, record.toMap());
    _database.notifyChanged();
  }

  Future<TransactionRecord?> getById(int id) async {
    final rows =
        await _database.db.query(_table, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : TransactionRecord.fromMap(rows.single);
  }

  Future<List<TransactionRecord>> getBetween(
      DateTime start, DateTime endExclusive) async {
    final rows = await _database.db.query(
      _table,
      where: 'date >= ? AND date < ?',
      whereArgs: [DateKeys.fromDate(start), DateKeys.fromDate(endExclusive)],
      orderBy: _newestFirst,
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  Future<List<TransactionRecord>> getAll() async {
    final rows = await _database.db.query(_table, orderBy: _newestFirst);
    return rows.map(TransactionRecord.fromMap).toList();
  }

  Future<List<TransactionRecord>> getRecent({int limit = 5}) async {
    final rows =
        await _database.db.query(_table, orderBy: _newestFirst, limit: limit);
    return rows.map(TransactionRecord.fromMap).toList();
  }
}
