import 'package:calculator/app/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fresh, isolated in-memory database for one test.
Future<DatabaseService> openTestDatabase() {
  sqfliteFfiInit();
  return DatabaseService(factory: databaseFactoryFfi, path: inMemoryDatabasePath)
      .init();
}
