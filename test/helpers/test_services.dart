import 'package:calculator/app/bindings/initial_binding.dart';
import 'package:calculator/app/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_files.dart';
import 'fake_notifications.dart';
import 'fake_secret_store.dart';
import 'fake_sms_inbox.dart';

/// Registers every app service and repository against a fresh in-memory
/// database and a fake notification system, which it returns.
Future<FakeNotificationProvider> setUpTestServices({
  AiClientFactory? aiClientFactory,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  Get.reset();
  sqfliteFfiInit();
  final notifications = FakeNotificationProvider();
  await InitialBinding.initServices(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    notifications: notifications,
    files: FakeFileExchangeProvider(),
    smsInbox: FakeSmsInboxProvider(),
    secrets: FakeSecretStore(),
    aiClientFactory: aiClientFactory,
  );
  return notifications;
}

/// Lets `ever` workers and the reloads they start finish.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
