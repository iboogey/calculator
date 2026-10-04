import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/modules/recurring/controllers/recurring_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  test('pausing and resuming a rule', () async {
    await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'نادي',
      kind: RecurringKind.expense,
      amount: 30000,
      categoryId: 6,
      dayOfMonth: 15,
      startDate: DateTime(2026, 10, 15),
    ));
    final c = Get.put(RecurringController(
      recurring: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => DateTime(2026, 10, 4),
    ));
    await c.load();
    expect(c.nextDue(c.rules.single), DateTime(2026, 10, 15));
    await c.toggleActive(c.rules.single);
    await settle();
    expect(c.rules.single.isActive, isFalse);
    await c.toggleActive(c.rules.single);
    await settle();
    expect(c.rules.single.isActive, isTrue);
    expect(c.categoriesById[6]!.name, 'ترفيه');
  });
}
