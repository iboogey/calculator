import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:calculator/app/data/providers/sms_inbox_provider.dart';
import 'package:calculator/app/data/repositories/category_repository.dart';
import 'package:calculator/app/data/repositories/import_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:calculator/app/services/sms_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_sms_inbox.dart';
import '../helpers/fixtures.dart';
import '../helpers/sms_fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  final now = DateTime(2026, 11, 9, 10);
  late FakeSmsInboxProvider inbox;
  late SmsImportService service;
  late ImportRepository imports;

  setUp(() async {
    await setUpTestServices();
    inbox = Get.find<SmsInboxProvider>() as FakeSmsInboxProvider;
    imports = Get.find<ImportRepository>();
    final settings = Get.find<SettingsService>();
    await settings.update(
      settings.settings.value.copyWith(
        smsImportEnabled: true,
        periodStartDay: 1,
      ),
    );
    service = Get.find<SmsImportService>();
  });

  void add(String body, DateTime date) =>
      inbox.messages.add(SmsMessage(date: date, body: body));

  Future<int?> categoryByIcon(String icon) async =>
      (await Get.find<CategoryRepository>().getAll())
          .firstWhere((c) => c.iconKey == icon)
          .id;

  test('does nothing when disabled, not granted or unsupported', () async {
    add(smsCard, DateTime(2026, 11, 2));
    final settings = Get.find<SettingsService>();
    await settings.update(
      settings.settings.value.copyWith(smsImportEnabled: false),
    );
    expect(await service.scan(now), 0);
    await settings.update(
      settings.settings.value.copyWith(smsImportEnabled: true),
    );
    inbox.granted = false;
    expect(await service.scan(now), 0);
    inbox.granted = true;
    inbox.supported = false;
    expect(await service.scan(now), 0);
    expect(inbox.readCount, 0);
  });

  test('first scan reads from the period start', () async {
    add(smsCard, DateTime(2026, 10, 31));
    add(smsCard, DateTime(2026, 11, 2));
    expect(await service.scan(now), 1);
    final pending = await imports.getPending();
    expect(pending.single.occurredAt, DateTime(2026, 11, 2));
    expect(pending.single.createdAt, now);
  });

  test('each message type becomes the right pending item', () async {
    add(smsCard, DateTime(2026, 11, 2, 1));
    add(smsCliqSent, DateTime(2026, 11, 2, 2));
    add(smsCliqReceived, DateTime(2026, 11, 2, 3));
    add(smsFee, DateTime(2026, 11, 2, 4));
    add(smsAnnouncement, DateTime(2026, 11, 2, 5));
    expect(await service.scan(now), 4);
    final byType = {for (final p in await imports.getPending()) p.smsType!: p};
    expect(byType[BankSmsType.cardPurchase]!.kind, PendingKind.expense);
    expect(byType[BankSmsType.cardPurchase]!.suggestedCategoryId, isNull);
    expect(byType[BankSmsType.cardPurchase]!.note, 'SAMPLE SUPER MARKET');
    expect(byType[BankSmsType.cliqSent]!.kind, PendingKind.expense);
    expect(byType[BankSmsType.cliqSent]!.suggestedCategoryId, isNull);
    expect(byType[BankSmsType.cliqReceived]!.kind, PendingKind.income);
    expect(
      byType[BankSmsType.cliqReceived]!.suggestedCategoryId,
      await categoryByIcon('income_other'),
    );
    expect(byType[BankSmsType.bankFee]!.kind, PendingKind.expense);
    expect(
      byType[BankSmsType.bankFee]!.suggestedCategoryId,
      await categoryByIcon('other'),
    );
  });

  test('a learned category wins', () async {
    final db = Get.find<DatabaseService>().db;
    for (final key in [
      'shop:SAMPLE SUPER MARKET',
      'cliq:SAMI KHALED HADDAD',
      learnedKey(BankSmsType.bankFee, BankSmsParser.parse(smsFee)!.name),
    ]) {
      await db.insert('learned_categories', {
        'name_key': key,
        'category_id': 5,
      });
    }
    add(smsCard, DateTime(2026, 11, 2, 1));
    add(smsCliqSent, DateTime(2026, 11, 2, 2));
    add(smsFee, DateTime(2026, 11, 2, 3));
    expect(await service.scan(now), 3);
    final pending = await imports.getPending();
    expect(pending.map((p) => p.suggestedCategoryId), everyElement(5));
  });

  test('a category learned from a received CliQ is not offered when sending',
      () async {
    await Get.find<DatabaseService>().db.insert('learned_categories', {
      'name_key': 'cliq:RANA OMAR SALEH',
      'category_id': salaryCategoryId,
    });
    add(smsCliqReceived, DateTime(2026, 11, 2, 1));
    add(smsCliqSent.replaceFirst('SAMI KHALED HADDAD', 'RANA OMAR SALEH'),
        DateTime(2026, 11, 2, 2));
    expect(await service.scan(now), 2);
    final byType = {for (final p in await imports.getPending()) p.smsType!: p};
    expect(byType[BankSmsType.cliqReceived]!.suggestedCategoryId,
        salaryCategoryId);
    expect(byType[BankSmsType.cliqSent]!.suggestedCategoryId, isNull);
  });

  test('scan point follows the newest message read', () async {
    add(smsCard, DateTime(2026, 11, 2));
    add(smsAnnouncement, DateTime(2026, 11, 3));
    expect(await service.scan(now), 1);
    expect(await imports.scanPoint(), DateTime(2026, 11, 3));
    expect(await service.scan(now), 0);
    expect(await imports.scanPoint(), DateTime(2026, 11, 3));
  });

  test('a future-dated message never moves the scan point past now',
      () async {
    add(smsCard, DateTime(2026, 11, 2));
    add(smsCliqSent, DateTime(2026, 11, 12));
    expect(await service.scan(now), 1);
    expect(await imports.scanPoint(), DateTime(2026, 11, 2));
    // A message that arrives later is still imported...
    add(smsFee, DateTime(2026, 11, 9, 9));
    expect(await service.scan(now), 1);
    expect(await imports.scanPoint(), DateTime(2026, 11, 9, 9));
    // ...and the future-dated one once its time has come, exactly once.
    expect(await service.scan(DateTime(2026, 11, 13)), 1);
    expect(await service.scan(DateTime(2026, 11, 13)), 0);
    final sent = (await imports.getPending())
        .where((p) => p.smsType == BankSmsType.cliqSent);
    expect(sent, hasLength(1));
    expect(await imports.scanPoint(), DateTime(2026, 11, 12));
  });

  test('a failing inbox read leaves the scan point alone', () async {
    final failing = _ThrowingInbox();
    final s = SmsImportService(
      inbox: failing,
      imports: imports,
      categories: Get.find<CategoryRepository>(),
      settings: Get.find<SettingsService>(),
    );
    await expectLater(s.scan(now), throwsA(isA<StateError>()));
    expect(await imports.scanPoint(), isNull);
    // And a later scan is not stuck behind the failure.
    await expectLater(s.scan(now), throwsA(isA<StateError>()));
  });

  test('identical messages one second apart are both kept', () async {
    add(smsCard, DateTime(2026, 11, 2, 1, 0, 0));
    add(smsCard, DateTime(2026, 11, 2, 1, 0, 1));
    expect(await service.scan(now), 2);
  });

  test('the fake inbox returns messages oldest first', () async {
    add(smsCliqSent, DateTime(2026, 11, 4));
    add(smsCard, DateTime(2026, 11, 2));
    final read = await inbox.readInbox(after: DateTime(2026, 10));
    expect(read.map((m) => m.body), [smsCard, smsCliqSent]);
  });

  test('concurrent scans add items once', () async {
    add(smsCard, DateTime(2026, 11, 2));
    final results = await Future.wait([service.scan(now), service.scan(now)]);
    expect(results.reduce((a, b) => a + b), 1);
    expect(await imports.getPending(), hasLength(1));
  });

  test('suggester runs once per card key, never for CliQ or fees', () async {
    final asked = <String>[];
    service.suggester = (sms) async {
      asked.add(sms.name);
      return 7;
    };
    add(smsCard, DateTime(2026, 11, 2, 1));
    add(smsCard, DateTime(2026, 11, 2, 2));
    add(smsCardTruncated, DateTime(2026, 11, 2, 3));
    add(smsCliqSent, DateTime(2026, 11, 2, 4));
    add(smsFee, DateTime(2026, 11, 2, 5));
    expect(await service.scan(now), 5);
    expect(asked, ['SAMPLE SUPER MARKET', 'SAMPLE ELECTRICITY R']);
    final pending = await imports.getPending();
    expect(
      pending
          .where((p) => p.smsType == BankSmsType.cardPurchase)
          .map((p) => p.suggestedCategoryId),
      everyElement(7),
    );
    expect(
      pending
          .firstWhere((p) => p.smsType == BankSmsType.cliqSent)
          .suggestedCategoryId,
      isNull,
    );
  });

  test('a throwing suggester leaves the item uncategorised, scan goes on',
      () async {
    var calls = 0;
    service.suggester = (_) async {
      calls++;
      throw StateError('timeout');
    };
    add(smsCard, DateTime(2026, 11, 2, 1));
    add(smsCard, DateTime(2026, 11, 2, 2));
    add(smsCliqReceived, DateTime(2026, 11, 2, 3));
    expect(await service.scan(now), 3);
    expect(calls, 1);
    final pending = await imports.getPending();
    expect(
        pending
            .where((p) => p.smsType == BankSmsType.cardPurchase)
            .map((p) => p.suggestedCategoryId),
        everyElement(isNull));
    expect(
        pending
            .firstWhere((p) => p.smsType == BankSmsType.cliqReceived)
            .suggestedCategoryId,
        await categoryByIcon('income_other'));
    expect(await imports.scanPoint(), DateTime(2026, 11, 2, 3));
  });

  test('suggester is skipped when a category was learned', () async {
    await Get.find<DatabaseService>().db.insert('learned_categories', {
      'name_key': 'shop:SAMPLE SUPER MARKET',
      'category_id': 5,
    });
    var called = false;
    service.suggester = (_) async {
      called = true;
      return 7;
    };
    add(smsCard, DateTime(2026, 11, 2));
    await service.scan(now);
    expect(called, isFalse);
    expect((await imports.getPending()).single.suggestedCategoryId, 5);
  });

  test('pending items never store the message body', () async {
    add(smsCard, DateTime(2026, 11, 2));
    await service.scan(now);
    final keys = (await imports.getPending()).single.toMap().keys.toSet();
    expect(keys, {
      'id',
      'source',
      'kind',
      'amount',
      'occurred_at',
      'sms_type',
      'name',
      'city',
      'suggested_category_id',
      'person_id',
      'person_name',
      'note',
      'created_at',
    });
    final columns = (await Get.find<DatabaseService>().db.rawQuery(
      'PRAGMA table_info(pending_items)',
    )).map((r) => r['name']).toSet();
    expect(columns, keys);
  });
}

class _ThrowingInbox extends FakeSmsInboxProvider {
  @override
  Future<List<SmsMessage>> readInbox({required DateTime after}) async =>
      throw StateError('boom');
}
