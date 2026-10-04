import 'package:sqflite/sqflite.dart';

import '../../core/logic/recurring_generator.dart';
import '../../core/utils/date_utils.dart';
import '../../services/database_service.dart';
import '../models/enums.dart';
import '../models/recurring_rule.dart';

class RecurringRepository {
  RecurringRepository(this._database);

  final DatabaseService _database;

  static const _table = 'recurring_rules';

  Future<List<RecurringRule>> getAll() async {
    final rows = await _database.db
        .query(_table, orderBy: 'is_active DESC, day_of_month, id');
    return rows.map(RecurringRule.fromMap).toList();
  }

  Future<RecurringRule> add(RecurringRule rule) async {
    final id = await _database.db.insert(_table, rule.toMap()..remove('id'));
    _database.notifyChanged();
    return rule.withId(id);
  }

  Future<void> update(RecurringRule rule) async {
    await _database.db
        .update(_table, rule.toMap(), where: 'id = ?', whereArgs: [rule.id]);
    _database.notifyChanged();
  }

  /// Deletes the rule. Entries it already created stay (they lose their
  /// "auto" link through ON DELETE SET NULL).
  Future<void> delete(int id) async {
    await _database.db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  Future<void> setActive(int id, bool isActive) async {
    await _database.db.update(_table, {'is_active': isActive ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Creates every due entry up to [today] that was not created yet, in one
  /// database transaction. Returns how many entries were created.
  Future<int> applyDue(DateTime today) async {
    final rules = await getAll();
    var created = 0;
    await _database.db.transaction((txn) async {
      for (final rule in rules) {
        final dates = RecurringGenerator.dueDates(rule, today);
        if (dates.isEmpty) continue;
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final due in dates) {
          final dueKey = DateKeys.fromDate(due);
          if (rule.kind == RecurringKind.saving) {
            await txn.insert(
              'savings_movements',
              {
                'goal_id': rule.goalId,
                'amount': rule.amount,
                'date': dueKey,
                'source': SavingsSource.recurring.name,
                'recurring_rule_id': rule.id,
                'recurring_due_date': dueKey,
                'note': rule.label,
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          } else {
            await txn.insert(
              'transactions',
              {
                'kind': rule.kind.name,
                'amount': rule.amount,
                'category_id': rule.categoryId,
                'date': dueKey,
                'note': rule.label,
                'recurring_rule_id': rule.id,
                'recurring_due_date': dueKey,
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
          created++;
        }
        await txn.update(
          _table,
          {'last_generated_date': DateKeys.fromDate(dates.last)},
          where: 'id = ?',
          whereArgs: [rule.id],
        );
      }
    });
    if (created > 0) _database.notifyChanged();
    return created;
  }
}
