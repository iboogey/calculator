import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/debt_entry.dart';
import '../models/debt_person.dart';
import '../models/enums.dart';
import '../models/obligation.dart';
import '../models/obligation_payment.dart';
import '../models/transaction_record.dart';

/// Another person already has this (trimmed) name.
class DuplicateNameException implements Exception {
  const DuplicateNameException();
}

/// A payment is larger than what is still owed; [remaining] is in thousandths.
class OverpaymentException implements Exception {
  const OverpaymentException(this.remaining);
  final int remaining;
}

/// The new obligation amount is below what was already paid ([paid], thousandths).
class AmountBelowPaidException implements Exception {
  const AmountBelowPaidException(this.paid);
  final int paid;
}

class DebtRepository {
  DebtRepository(this._database);

  final DatabaseService _database;

  static const _people = 'debt_people';
  static const _entries = 'debt_entries';
  static const _obligations = 'obligations';
  static const _payments = 'obligation_payments';

  // ---- People ----

  Future<List<DebtPerson>> getPeople() async {
    final rows = await _database.db.query(_people, orderBy: 'name, id');
    return rows.map(DebtPerson.fromMap).toList();
  }

  Future<DebtPerson?> getPerson(int id) async {
    final rows = await _database.db.query(
      _people,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : DebtPerson.fromMap(rows.single);
  }

  Future<DebtPerson> addPerson(String name) async {
    final trimmed = await _checkedName(name);
    final person = DebtPerson(name: trimmed, createdAt: DateTime.now());
    final id = await _database.db.insert(_people, person.toMap()..remove('id'));
    _database.notifyChanged();
    return person.withId(id);
  }

  Future<void> renamePerson(int id, String name) async {
    final trimmed = await _checkedName(name, exceptId: id);
    await _database.db.update(
      _people,
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [id],
    );
    _database.notifyChanged();
  }

  /// Removes the person; their entries go with them (cascade).
  Future<void> deletePerson(int id) async {
    await _database.db.delete(_people, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// What each person's ledger sums to, by person id (positive = they owe me).
  Future<Map<int, int>> personBalances() async {
    final rows = await _database.db.rawQuery(
      'SELECT person_id, SUM(amount) AS total FROM $_entries GROUP BY person_id',
    );
    return {for (final r in rows) r['person_id'] as int: r['total'] as int};
  }

  Future<String> _checkedName(String name, {int? exceptId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Name must not be empty');
    final rows = await _database.db.query(
      _people,
      columns: ['id'],
      where: exceptId == null ? 'trim(name) = ?' : 'trim(name) = ? AND id <> ?',
      whereArgs: exceptId == null ? [trimmed] : [trimmed, exceptId],
      limit: 1,
    );
    if (rows.isNotEmpty) throw const DuplicateNameException();
    return trimmed;
  }

  // ---- Person entries ----

  /// Newest first.
  Future<List<DebtEntry>> getEntries(int personId) async {
    final rows = await _database.db.query(
      _entries,
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(DebtEntry.fromMap).toList();
  }

  Future<DebtEntry> addEntry(DebtEntry entry) async {
    final id = await _database.db.insert(_entries, entry.toMap()..remove('id'));
    _database.notifyChanged();
    return entry.withId(id);
  }

  Future<void> updateEntry(DebtEntry entry) async {
    await _database.db.update(
      _entries,
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    _database.notifyChanged();
  }

  Future<void> deleteEntry(int id) async {
    await _database.db.delete(_entries, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Puts a deleted entry back under its old id (for Undo).
  Future<void> restoreEntry(DebtEntry entry) async {
    await _database.db.insert(_entries, entry.toMap());
    _database.notifyChanged();
  }

  // ---- Obligations ----

  Future<List<Obligation>> getObligations() async {
    final rows = await _database.db.query(_obligations, orderBy: 'id');
    return rows.map(Obligation.fromMap).toList();
  }

  Future<Obligation?> getObligation(int id) async {
    final rows = await _database.db.query(
      _obligations,
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : Obligation.fromMap(rows.single);
  }

  Future<Obligation> addObligation(Obligation o) async {
    final title = o.title.trim();
    if (title.isEmpty) throw ArgumentError('Title must not be empty');
    final trimmed = o.copyWith(title: title);
    final id = await _database.db.insert(
      _obligations,
      trimmed.toMap()..remove('id'),
    );
    _database.notifyChanged();
    return trimmed.withId(id);
  }

  /// Throws [AmountBelowPaidException] when the amount is below what is paid.
  Future<void> updateObligation(Obligation o) async {
    final title = o.title.trim();
    if (title.isEmpty) throw ArgumentError('Title must not be empty');
    await _database.db.transaction((txn) async {
      final paid = await _paidFor(txn, o.id!);
      if (o.amount < paid) throw AmountBelowPaidException(paid);
      await txn.update(
        _obligations,
        o.copyWith(title: title).toMap(),
        where: 'id = ?',
        whereArgs: [o.id],
      );
    });
    _database.notifyChanged();
  }

  /// Payments go with it (cascade); the expenses they created stay.
  Future<void> deleteObligation(int id) async {
    await _database.db.delete(_obligations, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Total paid per obligation id.
  Future<Map<int, int>> paidTotals() async {
    final rows = await _database.db.rawQuery(
      'SELECT obligation_id, SUM(amount) AS total FROM $_payments GROUP BY obligation_id',
    );
    return {for (final r in rows) r['obligation_id'] as int: r['total'] as int};
  }

  /// Newest first.
  Future<List<ObligationPayment>> getPayments(int obligationId) async {
    final rows = await _database.db.query(
      _payments,
      where: 'obligation_id = ?',
      whereArgs: [obligationId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(ObligationPayment.fromMap).toList();
  }

  /// Distinct obligation titles, most recently created first.
  Future<List<String>> recentTitles({int limit = 5}) async {
    final rows = await _database.db.rawQuery(
      'SELECT title FROM $_obligations GROUP BY title '
      'ORDER BY MAX(created_at) DESC, MAX(id) DESC LIMIT ?',
      [limit],
    );
    return rows.map((r) => r['title'] as String).toList();
  }

  /// Records a payment; with [expenseCategoryId], also an expense of the same
  /// amount and date, linked to it. All or nothing.
  Future<ObligationPayment> pay({
    required int obligationId,
    required int amount,
    required DateTime date,
    int? expenseCategoryId,
  }) async {
    if (amount <= 0) throw ArgumentError('Amount must be positive');
    final now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
    );
    final payment = await _database.db.transaction((txn) async {
      final rows = await txn.query(
        _obligations,
        where: 'id = ?',
        whereArgs: [obligationId],
      );
      final obligation = Obligation.fromMap(rows.single);
      final remaining = obligation.amount - await _paidFor(txn, obligationId);
      if (amount > remaining) throw OverpaymentException(remaining);
      int? transactionId;
      if (expenseCategoryId != null) {
        final record = TransactionRecord(
          kind: TransactionKind.expense,
          amount: amount,
          categoryId: expenseCategoryId,
          date: date,
          note: obligation.title,
          createdAt: now,
        );
        transactionId = await txn.insert(
          'transactions',
          record.toMap()..remove('id'),
        );
      }
      final p = ObligationPayment(
        obligationId: obligationId,
        amount: amount,
        date: date,
        transactionId: transactionId,
        createdAt: now,
      );
      final id = await txn.insert(_payments, p.toMap()..remove('id'));
      return p.withId(id);
    });
    _database.notifyChanged();
    return payment;
  }

  /// Deletes the payment and the expense it created, if any.
  Future<void> deletePayment(ObligationPayment p) async {
    await _database.db.transaction((txn) async {
      await txn.delete(_payments, where: 'id = ?', whereArgs: [p.id]);
      if (p.transactionId != null) {
        await txn.delete(
          'transactions',
          where: 'id = ?',
          whereArgs: [p.transactionId],
        );
      }
    });
    _database.notifyChanged();
  }

  /// transaction id -> obligation title, for every payment that made an expense.
  Future<Map<int, String>> linkedExpenses() async {
    final rows = await _database.db.rawQuery(
      'SELECT p.transaction_id AS tid, o.title AS title FROM $_payments p '
      'JOIN $_obligations o ON o.id = p.obligation_id '
      'WHERE p.transaction_id IS NOT NULL',
    );
    return {for (final r in rows) r['tid'] as int: r['title'] as String};
  }

  Future<int> _paidFor(DatabaseExecutor db, int obligationId) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) FROM $_payments WHERE obligation_id = ?',
          [obligationId],
        ),
      ) ??
      0;
}
