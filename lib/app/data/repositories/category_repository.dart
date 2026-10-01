import '../../services/database_service.dart';
import '../models/enums.dart';
import '../models/transaction_category.dart';

class CategoryRepository {
  CategoryRepository(this._database);

  final DatabaseService _database;

  Future<List<TransactionCategory>> getAll({
    TransactionKind? kind,
    bool includeArchived = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (!includeArchived) where.add('is_archived = 0');
    final rows = await _database.db.query(
      'categories',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'sort_order, id',
    );
    return rows.map(TransactionCategory.fromMap).toList();
  }
}
