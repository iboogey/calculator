import '../../services/database_service.dart';
import '../models/savings_movement.dart';

class SavingsRepository {
  SavingsRepository(this._database);

  final DatabaseService _database;

  Future<List<SavingsMovement>> getAllMovements() async {
    final rows =
        await _database.db.query('savings_movements', orderBy: 'date, id');
    return rows.map(SavingsMovement.fromMap).toList();
  }
}
