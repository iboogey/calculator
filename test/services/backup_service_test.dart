import 'dart:convert';
import 'dart:io';

import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/providers/file_exchange_provider.dart';
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/backup_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_files.dart';
import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  BackupService backup() => Get.find<BackupService>();
  TransactionRepository transactions() => Get.find<TransactionRepository>();

  Future<void> seed() async {
    await transactions().add(expense(5000, DateTime(2026, 10, 1), note: 'قهوة'));
    await Get.find<BudgetRepository>().setLimit(1, 200000);
    final goal = await Get.find<SavingsRepository>().addGoal(
        SavingsGoal(name: 'لابتوب', targetAmount: 900000, createdAt: DateTime(2026, 10, 1)));
    await Get.find<SavingsRepository>()
        .addMovement(saving(100000, DateTime(2026, 10, 2), goalId: goal.id!));
  }

  test('export then restore brings back exactly the same data', () async {
    await seed();
    final before = await transactions().getAll();
    final json = await backup().exportJson(DateTime(2026, 10, 4));

    await transactions().add(expense(9999, DateTime(2026, 10, 3)));
    await Get.find<BudgetRepository>().remove(1);

    final summary = backup().parse(json);
    expect(summary.transactionCount, 1);
    expect(summary.goalCount, 2);
    await backup().restore(summary);

    expect(await transactions().getAll(), before);
    expect((await Get.find<BudgetRepository>().getAll()).single.limitAmount, 200000);
    expect((await Get.find<SavingsRepository>().balances()).values, [100000]);
  });

  test('a file that is not a backup is rejected', () {
    expect(() => backup().parse('hello'), throwsA(isA<BackupFormatException>()));
    expect(() => backup().parse(jsonEncode({'format': 'other'})),
        throwsA(isA<BackupFormatException>()));
  });

  test('a backup from a newer app version is rejected', () async {
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, Object?>;
    data['schemaVersion'] = 99;
    expect(
      () => backup().parse(jsonEncode(data)),
      throwsA(isA<BackupFormatException>().having(
          (e) => e.message, 'message', contains('أحدث'))),
    );
  });

  test('a backup without exactly one settings row is rejected', () async {
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    (data['tables'] as Map<String, dynamic>)['settings'] = [];
    expect(() => backup().parse(jsonEncode(data)), throwsA(isA<BackupFormatException>()));
  });

  test('a restore that fails half-way leaves the current data untouched', () async {
    await seed();
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    final rows = (data['tables'] as Map<String, dynamic>)['transactions'] as List;
    (rows.first as Map<String, dynamic>)['category_id'] = 999;
    final summary = backup().parse(jsonEncode(data));

    final before = await transactions().getAll();
    await expectLater(backup().restore(summary), throwsA(anything));
    expect(await transactions().getAll(), before);
  });

  test('shareBackup writes the file, opens sharing and records the time', () async {
    await seed();
    await backup().shareBackup(DateTime(2026, 10, 4, 9));
    final fake = Get.find<FileExchangeProvider>() as FakeFileExchangeProvider;
    expect(fake.shared.single, endsWith('masarifi-backup-2026-10-04.json'));
    expect(jsonDecode(File(fake.shared.single).readAsStringSync())['format'],
        'masarifi-backup');
    expect(Get.find<SettingsService>().settings.value.lastBackupAt,
        DateTime(2026, 10, 4, 9));
  });
}
