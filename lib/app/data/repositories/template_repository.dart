import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/quick_template.dart';

class TemplateRepository {
  TemplateRepository(this._database);

  final DatabaseService _database;

  static const _table = 'quick_templates';

  Future<List<QuickTemplate>> getAll() async {
    final rows = await _database.db.query(_table, orderBy: 'sort_order, id');
    return rows.map(QuickTemplate.fromMap).toList();
  }

  /// Adds [template] after the existing favorites.
  Future<QuickTemplate> add(QuickTemplate template) async {
    final next = Sqflite.firstIntValue(await _database.db
            .rawQuery('SELECT COALESCE(MAX(sort_order), -1) + 1 FROM $_table')) ??
        0;
    final row = template.toMap()
      ..remove('id')
      ..['sort_order'] = next;
    final id = await _database.db.insert(_table, row);
    _database.notifyChanged();
    return QuickTemplate.fromMap({...row, 'id': id});
  }

  Future<void> delete(int id) async {
    await _database.db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }
}
