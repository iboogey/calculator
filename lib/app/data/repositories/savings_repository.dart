import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/savings_goal.dart';
import '../models/savings_movement.dart';

/// A withdrawal asked for more than the goal holds.
class InsufficientSavingsException implements Exception {
  const InsufficientSavingsException(this.available);

  final int available;
}

/// A goal can only be removed once it is empty.
class GoalNotEmptyException implements Exception {
  const GoalNotEmptyException(this.balance);

  final int balance;
}

/// A goal that a fixed monthly saving still pays into cannot be removed.
class GoalHasRecurringException implements Exception {
  const GoalHasRecurringException();
}

class SavingsRepository {
  SavingsRepository(this._database);

  final DatabaseService _database;

  static const _goals = 'savings_goals';
  static const _movements = 'savings_movements';

  Future<List<SavingsMovement>> getAllMovements() async {
    final rows = await _database.db.query(_movements, orderBy: 'date, id');
    return rows.map(SavingsMovement.fromMap).toList();
  }

  /// Active goals, General Savings first.
  Future<List<SavingsGoal>> getGoals({bool includeArchived = false}) async {
    final rows = await _database.db.query(
      _goals,
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'is_general DESC, id',
    );
    return rows.map(SavingsGoal.fromMap).toList();
  }

  Future<SavingsGoal?> getGoal(int id) async {
    final rows =
        await _database.db.query(_goals, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : SavingsGoal.fromMap(rows.single);
  }

  /// What each goal holds, by goal id (goals without movements are absent).
  Future<Map<int, int>> balances() async {
    final rows = await _database.db.rawQuery(
        'SELECT goal_id, SUM(amount) AS total FROM $_movements GROUP BY goal_id');
    return {for (final r in rows) r['goal_id'] as int: r['total'] as int};
  }

  Future<SavingsGoal> addGoal(SavingsGoal goal) async {
    final id = await _database.db.insert(_goals, goal.toMap()..remove('id'));
    _database.notifyChanged();
    return goal.withId(id);
  }

  Future<void> updateGoal(SavingsGoal goal) async {
    await _database.db
        .update(_goals, goal.toMap(), where: 'id = ?', whereArgs: [goal.id]);
    _database.notifyChanged();
  }

  /// Removes an empty goal: deleted when it has no history, archived when it
  /// has (returns true). General Savings is never removed, nor a goal that a
  /// fixed monthly saving still points at.
  Future<bool> removeGoal(SavingsGoal goal) async {
    if (goal.isGeneral) {
      throw ArgumentError('General Savings cannot be removed');
    }
    final archived = await _database.db.transaction((txn) async {
      final args = [goal.id];
      final balance = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COALESCE(SUM(amount), 0) FROM $_movements WHERE goal_id = ?',
              args)) ??
          0;
      if (balance != 0) throw GoalNotEmptyException(balance);
      final rules = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM recurring_rules WHERE goal_id = ?', args)) ??
          0;
      if (rules > 0) throw const GoalHasRecurringException();
      final used = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM $_movements WHERE goal_id = ?', args)) ??
          0;
      if (used == 0) {
        await txn.delete(_goals, where: 'id = ?', whereArgs: args);
        return false;
      }
      await txn.update(_goals, {'is_archived': 1},
          where: 'id = ?', whereArgs: args);
      return true;
    });
    _database.notifyChanged();
    return archived;
  }

  /// Saves [movements] in one transaction. A withdrawal larger than its goal
  /// holds throws [InsufficientSavingsException] and nothing is saved. With
  /// [answeredPeriodKey], the month-end question for that period is marked
  /// answered in the same transaction.
  Future<void> addMovements(
    List<SavingsMovement> movements, {
    String? answeredPeriodKey,
  }) async {
    await _database.db.transaction((txn) async {
      if (answeredPeriodKey != null) {
        await txn.update(
            'settings', {'last_month_end_prompt_period': answeredPeriodKey},
            where: 'id = ?', whereArgs: [1]);
      }
      for (final movement in movements) {
        if (movement.amount < 0) {
          final held = Sqflite.firstIntValue(await txn.rawQuery(
                  'SELECT COALESCE(SUM(amount), 0) FROM $_movements WHERE goal_id = ?',
                  [movement.goalId])) ??
              0;
          if (held + movement.amount < 0) {
            throw InsufficientSavingsException(held);
          }
        }
        await txn.insert(_movements, movement.toMap()..remove('id'));
      }
    });
    _database.notifyChanged();
  }

  Future<void> addMovement(SavingsMovement movement) =>
      addMovements([movement]);

  Future<List<SavingsMovement>> getMovements(int goalId) async {
    final rows = await _database.db.query(_movements,
        where: 'goal_id = ?', whereArgs: [goalId], orderBy: 'date DESC, id DESC');
    return rows.map(SavingsMovement.fromMap).toList();
  }
}
