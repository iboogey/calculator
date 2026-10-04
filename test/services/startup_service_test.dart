import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/startup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

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
}
