import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/budget.dart';

class BudgetRepository {
  BudgetRepository(this._database);

  final DatabaseService _database;

  Future<List<Budget>> getAll() async {
    final rows = await _database.db.query('budgets', orderBy: 'id');
    return rows.map(Budget.fromMap).toList();
  }

  /// Creates or replaces the monthly limit of [categoryId].
  Future<void> setLimit(int categoryId, int limitAmount) async {
    await _database.db.insert(
      'budgets',
      {'category_id': categoryId, 'limit_amount': limitAmount},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _database.notifyChanged();
  }

  Future<void> remove(int categoryId) async {
    await _database.db
        .delete('budgets', where: 'category_id = ?', whereArgs: [categoryId]);
    _database.notifyChanged();
  }

  /// Records that the [threshold] alert of [categoryId] went out in
  /// [periodKey]. Returns false when it had already been sent. Bookkeeping
  /// only, so it does not announce a change.
  Future<bool> markAlertSent(int categoryId, String periodKey, int threshold) {
    return _database.db.transaction((txn) async {
      final args = [categoryId, periodKey, threshold];
      final existing = await txn.query(
        'budget_alerts_sent',
        where: 'category_id = ? AND period_key = ? AND threshold = ?',
        whereArgs: args,
      );
      if (existing.isNotEmpty) return false;
      await txn.insert('budget_alerts_sent', {
        'category_id': categoryId,
        'period_key': periodKey,
        'threshold': threshold,
      });
      return true;
    });
  }
}
