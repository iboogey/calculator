import '../../core/utils/date_utils.dart';
import 'enums.dart';

/// One income or expense entry. [amount] is always positive; [kind] gives
/// the direction.
class TransactionRecord {
  const TransactionRecord({
    this.id,
    required this.kind,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note,
    this.recurringRuleId,
    this.recurringDueDate,
    required this.createdAt,
  });

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    final dueDate = map['recurring_due_date'] as String?;
    return TransactionRecord(
      id: map['id'] as int?,
      kind: TransactionKind.values.byName(map['kind'] as String),
      amount: map['amount'] as int,
      categoryId: map['category_id'] as int,
      date: DateKeys.toDate(map['date'] as String),
      note: map['note'] as String?,
      recurringRuleId: map['recurring_rule_id'] as int?,
      recurringDueDate: dueDate == null ? null : DateKeys.toDate(dueDate),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final TransactionKind kind;
  final int amount;
  final int categoryId;
  final DateTime date;
  final String? note;
  final int? recurringRuleId;
  final DateTime? recurringDueDate;
  final DateTime createdAt;

  /// Positive for income, negative for expenses.
  int get signedAmount => kind == TransactionKind.income ? amount : -amount;

  /// True when a recurring rule generated this entry.
  bool get isAuto => recurringRuleId != null;

  TransactionRecord withId(int id) => TransactionRecord(
        id: id,
        kind: kind,
        amount: amount,
        categoryId: categoryId,
        date: date,
        note: note,
        recurringRuleId: recurringRuleId,
        recurringDueDate: recurringDueDate,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'date': DateKeys.fromDate(date),
        'note': note,
        'recurring_rule_id': recurringRuleId,
        'recurring_due_date':
            recurringDueDate == null ? null : DateKeys.fromDate(recurringDueDate!),
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is TransactionRecord &&
      other.id == id &&
      other.kind == kind &&
      other.amount == amount &&
      other.categoryId == categoryId &&
      other.date == date &&
      other.note == note &&
      other.recurringRuleId == recurringRuleId &&
      other.recurringDueDate == recurringDueDate &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, kind, amount, categoryId, date, note,
      recurringRuleId, recurringDueDate, createdAt);
}
