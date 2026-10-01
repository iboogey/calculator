import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/category_repository.dart';
import '../data/repositories/savings_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';

/// Registers the app-wide services and repositories before the first screen.
/// Async because the database has to open first, so it runs from `main()`
/// instead of a synchronous `Bindings.dependencies()`.
abstract final class InitialBinding {
  static Future<void> initServices({DatabaseFactory? factory, String? path}) async {
    final database = await Get.putAsync(
        () => DatabaseService(factory: factory, path: path).init(),
        permanent: true);
    final settingsRepository =
        Get.put(SettingsRepository(database), permanent: true);
    Get.put(CategoryRepository(database), permanent: true);
    Get.put(TransactionRepository(database), permanent: true);
    Get.put(SavingsRepository(database), permanent: true);
    await Get.putAsync(
        () => SettingsService(settingsRepository, database).init(),
        permanent: true);
  }
}
