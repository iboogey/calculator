import 'package:calculator/app/data/providers/file_exchange_provider.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/services/backup_service.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_files.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  final today = DateTime(2026, 10, 4, 9);

  SettingsController open() => Get.put(SettingsController(
        settingsService: Get.find(),
        notifications: Get.find(),
        backup: Get.find(),
        files: Get.find(),
        clock: () => today,
      ));

  FakeFileExchangeProvider files() =>
      Get.find<FileExchangeProvider>() as FakeFileExchangeProvider;

  test('never backed up: says so and flags it', () {
    final c = open();
    expect(c.lastBackupLabel, 'ما عملت نسخة احتياطية لسا');
    expect(c.backupOverdue, isTrue);
  });

  test('backing up shares a file and updates the label', () async {
    final c = open();
    await c.exportBackup();
    expect(files().shared, hasLength(1));
    expect(c.lastBackupLabel, 'آخر نسخة: اليوم');
    expect(c.backupOverdue, isFalse);
  });

  test('picking a file that is not a backup shows why', () async {
    files().textToPick = 'not json';
    expect(await open().pickBackup(), isNull);
    expect(Get.find<MessageService>().lastMessage.value, contains('مش نسخة'));
  });

  test('cancelling the picker does nothing', () async {
    files().textToPick = null;
    expect(await open().pickBackup(), isNull);
    expect(Get.find<MessageService>().lastMessage.value, isNull);
  });

  test('restoring a picked backup replaces the data', () async {
    final repo = Get.find<TransactionRepository>();
    await repo.add(expense(5000, DateTime(2026, 10, 1)));
    files().textToPick = await Get.find<BackupService>().exportJson(today);
    await repo.add(expense(7000, DateTime(2026, 10, 2)));

    final c = open();
    final summary = await c.pickBackup();
    expect(summary!.transactionCount, 1);
    expect(await c.restore(summary), isTrue);
    expect((await repo.getAll()).single.amount, 5000);
  });
}
