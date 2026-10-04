import 'package:calculator/app/bindings/initial_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_notifications.dart';

/// Registers every app service and repository against a fresh in-memory
/// database and a fake notification system, which it returns.
Future<FakeNotificationProvider> setUpTestServices() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  Get.reset();
  sqfliteFfiInit();
  final notifications = FakeNotificationProvider();
  await InitialBinding.initServices(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    notifications: notifications,
  );
  return notifications;
}

/// Lets `ever` workers and the reloads they start finish.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
