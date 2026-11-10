import 'dart:convert';
import 'dart:io';

import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/debt_entry.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/providers/app_database.dart';
import 'package:calculator/app/data/providers/file_exchange_provider.dart';
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/debt_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/backup_service.dart';
import 'package:calculator/app/services/database_service.dart';
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

  Future<void> seedDebts() async {
    final debts = Get.find<DebtRepository>();
    final person = await debts.addPerson('سامر');
    await debts.addEntry(DebtEntry(
        personId: person.id!,
        amount: 50000,
        date: DateTime(2026, 10, 2),
        createdAt: DateTime(2026, 10, 2)));
    final o = await debts.addObligation(Obligation(
        title: 'إيجار', amount: 100000, createdAt: DateTime(2026, 10, 1)));
    await debts.pay(
        obligationId: o.id!,
        amount: 30000,
        date: DateTime(2026, 10, 3),
        expenseCategoryId: foodCategoryId);
  }

  Future<List<int>> debtCounts() async {
    final debts = Get.find<DebtRepository>();
    final people = await debts.getPeople();
    final entries = <Object>[
      for (final p in people) ...await debts.getEntries(p.id!)
    ];
    final obligations = await debts.getObligations();
    final payments = <Object>[
      for (final o in obligations) ...await debts.getPayments(o.id!)
    ];
    return [people.length, entries.length, obligations.length, payments.length];
  }

  test('export then restore keeps people, entries, obligations and payments',
      () async {
    await seedDebts();
    final json = await backup().exportJson(DateTime(2026, 10, 4));
    final before = await transactions().getAll();
    final debts = Get.find<DebtRepository>();
    await debts.deletePerson((await debts.getPeople()).single.id!);
    final o = (await debts.getObligations()).single;
    for (final p in await debts.getPayments(o.id!)) {
      await debts.deletePayment(p);
    }
    await debts.deleteObligation(o.id!);
    expect(await debtCounts(), [0, 0, 0, 0]);

    await backup().restore(backup().parse(json));
    expect(await debtCounts(), [1, 1, 1, 1]);
    expect(await transactions().getAll(), before);
    expect((await debts.linkedExpenses()).length, 1);
  });

  test('a version-1 backup restores with no debts', () async {
    await seed();
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    final tables = data['tables'] as Map<String, dynamic>;
    for (final k in [
      'debt_people',
      'debt_entries',
      'obligations',
      'obligation_payments'
    ]) {
      tables.remove(k);
    }
    data['schemaVersion'] = 1;
    await seedDebts();
    await backup().restore(backup().parse(jsonEncode(data)));
    expect(await debtCounts(), [0, 0, 0, 0]);
    expect((await transactions().getAll()).length, 1);
  });

  test('a payment pointing at a missing transaction is rejected cleanly',
      () async {
    await seedDebts();
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    final pays = (data['tables'] as Map)['obligation_payments'] as List;
    (pays.first as Map)['transaction_id'] = 9999;
    final before = await transactions().getAll();
    expect(() => backup().parse(jsonEncode(data)),
        throwsA(isA<BackupFormatException>()));
    expect(await transactions().getAll(), before);
    expect(await debtCounts(), [1, 1, 1, 1]);
  });

  test('an entry pointing at a missing person is rejected', () async {
    await seedDebts();
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    (((data['tables'] as Map)['debt_entries'] as List).first as Map)['person_id'] = 9999;
    expect(() => backup().parse(jsonEncode(data)),
        throwsA(isA<BackupFormatException>()));
  });

  test('a version-2 backup missing a debt table is rejected', () async {
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    (data['tables'] as Map).remove('obligations');
    expect(() => backup().parse(jsonEncode(data)),
        throwsA(isA<BackupFormatException>()));
  });


  test('a file that is not a backup is rejected', () {
    expect(() => backup().parse('hello'), throwsA(isA<BackupFormatException>()));
    expect(() => backup().parse(jsonEncode({'format': 'other'})),
        throwsA(isA<BackupFormatException>()));
  });

  test('a backup from a newer app version is rejected', () async {
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, Object?>;
    data['schemaVersion'] = AppDatabase.version + 1;
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

  test('a backup with wrong value types is rejected before anything is replaced', () async {
    await seed();
    final good = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4))) as Map<String, dynamic>;
    final badAmount = jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
    ((badAmount['tables'] as Map)['transactions'] as List).first['amount'] = 'abc';
    expect(() => backup().parse(jsonEncode(badAmount)), throwsA(isA<BackupFormatException>()));

    final badDate = jsonDecode(jsonEncode(good)) as Map<String, dynamic>;
    ((badDate['tables'] as Map)['transactions'] as List).first['date'] = 5;
    expect(() => backup().parse(jsonEncode(badDate)), throwsA(isA<BackupFormatException>()));
  });

  test('dismissing the share sheet does not count as a backup', () async {
    final fake = Get.find<FileExchangeProvider>() as FakeFileExchangeProvider;
    fake.shareSucceeds = false;
    expect(await backup().shareBackup(DateTime(2026, 10, 4)), isFalse);
    expect(Get.find<SettingsService>().settings.value.lastBackupAt, isNull);
  });

  DatabaseService dbService() => Get.find<DatabaseService>();

  Future<void> learn(String key, int categoryId) => dbService()
      .db
      .insert('learned_categories', {'name_key': key, 'category_id': categoryId});

  test('export then restore round-trips learned_categories', () async {
    await learn('shop:SAMPLE SUPER MARKET', foodCategoryId);
    final json = await backup().exportJson(DateTime(2026, 10, 4));
    await dbService().db.delete('learned_categories');

    await backup().restore(backup().parse(json));
    final rows = await dbService().db.query('learned_categories');
    expect(rows.single['name_key'], 'shop:SAMPLE SUPER MARKET');
    expect(rows.single['category_id'], foodCategoryId);
  });

  test('the export has no pending_items or device_state', () async {
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    final tables = data['tables'] as Map<String, dynamic>;
    expect(tables.containsKey('pending_items'), isFalse);
    expect(tables.containsKey('device_state'), isFalse);
    expect(tables.containsKey('learned_categories'), isTrue);
  });

  test('restore leaves pending items and the scan point untouched', () async {
    final json = await backup().exportJson(DateTime(2026, 10, 4));
    final item = PendingItem(
      source: PendingSource.sms,
      kind: PendingKind.expense,
      amount: 1000,
      occurredAt: DateTime(2026, 10, 3),
      name: 'SAMPLE',
      createdAt: DateTime(2026, 10, 3),
    );
    await dbService().db.insert('pending_items', item.toMap()..remove('id'));
    await dbService()
        .db
        .update('device_state', {'last_sms_scan_at': 12345}, where: 'id = 1');

    await backup().restore(backup().parse(json));

    final pending = await dbService().db.query('pending_items');
    expect(pending, hasLength(1));
    expect(pending.single['amount'], 1000);
    expect((await dbService().db.query('device_state')).single['last_sms_scan_at'],
        12345);
  });

  test('a version-2 backup restores with defaults for the new settings', () async {
    await learn('shop:OLD', foodCategoryId);
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    final tables = data['tables'] as Map<String, dynamic>;
    tables.remove('learned_categories');
    final settings = (tables['settings'] as List).single as Map<String, dynamic>;
    for (final k in [
      'sms_import_enabled',
      'ai_provider',
      'ai_model',
      'voice_language'
    ]) {
      settings.remove(k);
    }
    data['schemaVersion'] = 2;

    await backup().restore(backup().parse(jsonEncode(data)));
    expect(await dbService().db.query('learned_categories'), isEmpty);
    final restored = Get.find<SettingsService>().settings.value;
    expect(restored.smsImportEnabled, isFalse);
    expect(restored.aiProvider, AiProviderKind.none);
    expect(restored.voiceLanguage, 'ar-JO');
  });

  test('a learned category pointing at a missing category is rejected', () async {
    await learn('shop:SAMPLE', foodCategoryId);
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    (((data['tables'] as Map)['learned_categories'] as List).first as Map)['category_id'] = 9999;
    expect(() => backup().parse(jsonEncode(data)),
        throwsA(isA<BackupFormatException>()));
  });
  Future<int> learnPerson(String key) async {
    final id = await dbService()
        .db
        .insert('debt_people', {'name': 'سامي', 'created_at': 0});
    await dbService()
        .db
        .insert('learned_people', {'name_key': key, 'person_id': id});
    return id;
  }

  test('export then restore round-trips learned_people', () async {
    final sami = await learnPerson('cliq:SAMI AHMAD');
    final json = await backup().exportJson(DateTime(2026, 10, 4));
    await dbService().db.delete('learned_people');

    await backup().restore(backup().parse(json));
    final rows = await dbService().db.query('learned_people');
    expect(rows.single['name_key'], 'cliq:SAMI AHMAD');
    expect(rows.single['person_id'], sami);
  });

  test('a version-3 backup restores with no learned people', () async {
    await learnPerson('cliq:SAMI AHMAD');
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    (data['tables'] as Map).remove('learned_people');
    data['schemaVersion'] = 3;

    await backup().restore(backup().parse(jsonEncode(data)));
    expect(await dbService().db.query('learned_people'), isEmpty);
    expect(await dbService().db.query('debt_people'), hasLength(1));
  });

  test('a learned person pointing at a missing person is rejected', () async {
    await learnPerson('cliq:SAMI AHMAD');
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    (((data['tables'] as Map)['learned_people'] as List).first
        as Map)['person_id'] = 9999;
    expect(() => backup().parse(jsonEncode(data)),
        throwsA(isA<BackupFormatException>()));
  });
}
