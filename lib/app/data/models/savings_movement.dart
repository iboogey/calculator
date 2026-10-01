import '../../core/utils/date_utils.dart';
import 'enums.dart';

/// Money moved into (positive [amount]) or out of (negative) a savings goal.
class SavingsMovement {
  const SavingsMovement({
    this.id,
    required this.goalId,
    required this.amount,
    required this.date,
    required this.source,
    this.recurringRuleId,
    this.recurringDueDate,
    this.note,
    required this.createdAt,
  });

  factory SavingsMovement.fromMap(Map<String, Object?> map) {
    final dueDate = map['recurring_due_date'] as String?;
    return SavingsMovement(
      id: map['id'] as int?,
      goalId: map['goal_id'] as int,
      amount: map['amount'] as int,
      date: DateKeys.toDate(map['date'] as String),
      source: SavingsSource.values.byName(map['source'] as String),
      recurringRuleId: map['recurring_rule_id'] as int?,
      recurringDueDate: dueDate == null ? null : DateKeys.toDate(dueDate),
      note: map['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final int goalId;
  final int amount;
  final DateTime date;
  final SavingsSource source;
  final int? recurringRuleId;
  final DateTime? recurringDueDate;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'goal_id': goalId,
        'amount': amount,
        'date': DateKeys.fromDate(date),
        'source': source.name,
        'recurring_rule_id': recurringRuleId,
        'recurring_due_date':
            recurringDueDate == null ? null : DateKeys.fromDate(recurringDueDate!),
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is SavingsMovement &&
      other.id == id &&
      other.goalId == goalId &&
      other.amount == amount &&
      other.date == date &&
      other.source == source &&
      other.recurringRuleId == recurringRuleId &&
      other.recurringDueDate == recurringDueDate &&
      other.note == note &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, goalId, amount, date, source,
      recurringRuleId, recurringDueDate, note, createdAt);
}
