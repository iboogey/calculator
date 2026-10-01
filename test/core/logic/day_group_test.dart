import 'package:calculator/app/core/logic/day_group.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

void main() {
  test('groups by day, newest day first, with the net amount', () {
    final groups = DayGroup.group([
      expense(2000, DateTime(2026, 10, 3)),
      income(10000, DateTime(2026, 10, 5)),
      expense(3000, DateTime(2026, 10, 5)),
      expense(1000, DateTime(2026, 10, 3)),
    ]);
    expect(groups.map((g) => g.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 3)]);
    expect(groups.first.net, 7000);
    expect(groups.last.net, -3000);
    expect(groups.last.transactions, hasLength(2));
  });

  test('no transactions means no groups', () {
    expect(DayGroup.group(const []), isEmpty);
  });
}
