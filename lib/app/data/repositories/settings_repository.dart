import '../../services/database_service.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  final DatabaseService _database;

  Future<AppSettings> load() async {
    final rows =
        await _database.db.query('settings', where: 'id = ?', whereArgs: [1]);
    return AppSettings.fromMap(rows.single);
  }

  /// Saves without announcing; [SettingsService] announces once its value is
  /// up to date.
  Future<void> save(AppSettings settings) => _database.db
      .update('settings', settings.toMap(), where: 'id = ?', whereArgs: [1]);
}
