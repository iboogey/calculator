import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

void main() {
  test('seeds categories, General Savings and default settings', () async {
    final db = (await openTestDatabase()).db;
    final categories = await db.query('categories', orderBy: 'id');
    expect(categories.where((c) => c['kind'] == 'expense'), hasLength(8));
    expect(categories.where((c) => c['kind'] == 'income'), hasLength(2));
    expect(categories.first['name'], 'أكل');
    expect(categories[8]['name'], 'راتب');

    final goals = await db.query('savings_goals');
    expect(goals.single['is_general'], 1);
    expect(goals.single['name'], 'ادخار عام');

    final settings = (await db.query('settings')).single;
    expect(settings['period_start_day'], 1);
    expect(settings['currency_code'], 'JOD');
    expect(settings['currency_decimals'], 3);
  });

  test('rejects a zero amount', () async {
    final db = (await openTestDatabase()).db;
    expect(
      () => db.insert('transactions', {
        'kind': 'expense',
        'amount': 0,
        'category_id': 1,
        'date': '2026-10-01',
        'created_at': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('a recurring rule can generate each due date only once', () async {
    final db = (await openTestDatabase()).db;
    final ruleId = await db.insert('recurring_rules', {
      'label': 'إيجار',
      'kind': 'expense',
      'amount': 350000,
      'category_id': 4,
      'day_of_month': 1,
      'start_date': '2026-10-01',
    });
    Map<String, Object?> occurrence() => {
          'kind': 'expense',
          'amount': 350000,
          'category_id': 4,
          'date': '2026-10-01',
          'recurring_rule_id': ruleId,
          'recurring_due_date': '2026-10-01',
          'created_at': 0,
        };
    await db.insert('transactions', occurrence());
    expect(() => db.insert('transactions', occurrence()),
        throwsA(isA<DatabaseException>()));
  });

  test('each test database is isolated', () async {
    final first = (await openTestDatabase()).db;
    final second = (await openTestDatabase()).db;
    await first.insert('transactions', {
      'kind': 'expense',
      'amount': 1000,
      'category_id': 1,
      'date': '2026-10-01',
      'created_at': 0,
    });
    expect(await second.query('transactions'), isEmpty);
  });
}
