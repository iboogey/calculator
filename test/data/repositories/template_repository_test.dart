import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/quick_template.dart';
import 'package:calculator/app/data/repositories/template_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  test('add appends in order, delete removes', () async {
    final database = await openTestDatabase();
    final repo = TemplateRepository(database);
    final coffee = await repo.add(const QuickTemplate(
        label: 'قهوة', kind: TransactionKind.expense, amount: 1500, categoryId: 1));
    final taxi = await repo.add(const QuickTemplate(
        label: 'تكسي', kind: TransactionKind.expense, amount: 3000, categoryId: 2));
    expect((await repo.getAll()).map((t) => t.label), ['قهوة', 'تكسي']);
    expect(taxi.sortOrder, greaterThan(coffee.sortOrder));
    await repo.delete(coffee.id!);
    expect((await repo.getAll()).single.label, 'تكسي');
  });
}
