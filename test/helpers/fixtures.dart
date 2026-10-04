import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/savings_movement.dart';
import 'package:calculator/app/data/models/transaction_record.dart';

/// Seeded category ids: 1 = أكل (expense), 9 = راتب (income).
const foodCategoryId = 1;
const salaryCategoryId = 9;

TransactionRecord expense(int amount, DateTime date,
        {int categoryId = foodCategoryId, String? note, DateTime? createdAt}) =>
    TransactionRecord(
      kind: TransactionKind.expense,
      amount: amount,
      categoryId: categoryId,
      date: date,
      note: note,
      createdAt: createdAt ?? date,
    );

TransactionRecord income(int amount, DateTime date,
        {int categoryId = salaryCategoryId}) =>
    TransactionRecord(
      kind: TransactionKind.income,
      amount: amount,
      categoryId: categoryId,
      date: date,
      createdAt: date,
    );

SavingsMovement saving(int amount, DateTime date, {int goalId = 1}) =>
    SavingsMovement(
      goalId: goalId,
      amount: amount,
      date: date,
      source: SavingsSource.manual,
      createdAt: date,
    );
