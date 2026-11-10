import 'dart:async';

import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/data/providers/sms_inbox_provider.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:calculator/app/services/sms_import_service.dart';
import 'package:calculator/app/services/startup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_sms_inbox.dart';
import '../helpers/sms_fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  test('refresh creates due recurring entries', () async {
    final now = DateTime.now();
    await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: 1,
      startDate: DateTime(now.year, now.month - 1, 1),
    ));
    await Get.find<StartupService>().refresh();
    final created = await Get.find<TransactionRepository>().getAll();
    expect(created, hasLength(2));
    expect(created.every((t) => t.isAuto), isTrue);
  });

  test('refresh tells every screen to reload, even with nothing due', () async {
    final database = Get.find<DatabaseService>();
    final before = database.revision.value;
    await Get.find<StartupService>().refresh();
    expect(database.revision.value, greaterThan(before));
  });

  test('refresh scans the SMS inbox', () async {
    final inbox = Get.find<SmsInboxProvider>() as FakeSmsInboxProvider;
    final settings = Get.find<SettingsService>();
    await settings
        .update(settings.settings.value.copyWith(smsImportEnabled: true));
    final before = inbox.readCount;
    await Get.find<StartupService>().refresh();
    expect(inbox.readCount, greaterThan(before));
  });

  test('refresh still notifies when the scan throws', () async {
    final database = Get.find<DatabaseService>();
    final settings = Get.find<SettingsService>();
    await settings
        .update(settings.settings.value.copyWith(smsImportEnabled: true));
    (Get.find<SmsInboxProvider>() as FakeSmsInboxProvider).throwOnRead = true;
    final before = database.revision.value;
    await Get.find<StartupService>().refresh();
    expect(database.revision.value, greaterThan(before));
  });

  test('init does not wait for a slow SMS scan, which lands later', () async {
    final settings = Get.find<SettingsService>();
    await settings
        .update(settings.settings.value.copyWith(smsImportEnabled: true));
    final now = DateTime.now();
    (Get.find<SmsInboxProvider>() as FakeSmsInboxProvider).messages.add(
        SmsMessage(
            date: now.subtract(const Duration(minutes: 1)), body: smsCard));
    final suggestion = Completer<int?>();
    final smsImport = Get.find<SmsImportService>()
      ..suggester = (_) => suggestion.future;
    final database = Get.find<DatabaseService>();
    final startup = StartupService(
      recurring: Get.find(),
      database: database,
      smsImport: smsImport,
      clock: () => now,
    );

    await startup.init();
    final afterInit = database.revision.value;
    final imports = Get.find<ImportRepository>();
    expect(await imports.getPending(), isEmpty);

    suggestion.complete(null);
    // Joins the scan init started, so this returns when it has finished.
    await smsImport.scan(now);
    await settle();
    expect(await imports.getPending(), hasLength(1));
    expect(database.revision.value, greaterThan(afterInit));
    startup.onClose();
  });
}
