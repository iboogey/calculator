import '../../services/database_service.dart';
import '../models/debt_entry.dart';
import '../models/debt_person.dart';

/// Another person already has this (trimmed) name.
class DuplicateNameException implements Exception {
  const DuplicateNameException();
}

class DebtRepository {
  DebtRepository(this._database);

  final DatabaseService _database;

  static const _people = 'debt_people';
  static const _entries = 'debt_entries';

  // ---- People ----

  Future<List<DebtPerson>> getPeople() async {
    final rows = await _database.db.query(_people, orderBy: 'name, id');
    return rows.map(DebtPerson.fromMap).toList();
  }

  Future<DebtPerson?> getPerson(int id) async {
    final rows =
        await _database.db.query(_people, where: 'id = ?', whereArgs: [id]);
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
    await _database.db.update(_people, {'name': trimmed},
        where: 'id = ?', whereArgs: [id]);
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
        'SELECT person_id, SUM(amount) AS total FROM $_entries GROUP BY person_id');
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
    await _database.db.update(_entries, entry.toMap(),
        where: 'id = ?', whereArgs: [entry.id]);
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
}
