import 'package:calculator/app/bindings/initial_binding.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Registers every app service and repository against a fresh in-memory
/// database.
Future<void> setUpTestServices() async {
  Get.testMode = true;
  Get.reset();
  sqfliteFfiInit();
  await InitialBinding.initServices(
      factory: databaseFactoryFfi, path: inMemoryDatabasePath);
}

/// Lets `ever` workers and the reloads they start finish.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
