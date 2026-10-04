import '../../core/utils/date_utils.dart';
import 'enums.dart';

/// "Rent 350 every month on day 1". Income and expense rules need a
/// [categoryId]; saving rules need a [goalId].
class RecurringRule {
  const RecurringRule({
    this.id,
    required this.label,
    required this.kind,
    required this.amount,
    this.categoryId,
    this.goalId,
    required this.dayOfMonth,
    required this.startDate,
    this.lastGeneratedDate,
    this.isActive = true,
  });

  factory RecurringRule.fromMap(Map<String, Object?> map) {
    final last = map['last_generated_date'] as String?;
    return RecurringRule(
      id: map['id'] as int?,
      label: map['label'] as String,
      kind: RecurringKind.values.byName(map['kind'] as String),
      amount: map['amount'] as int,
      categoryId: map['category_id'] as int?,
      goalId: map['goal_id'] as int?,
      dayOfMonth: map['day_of_month'] as int,
      startDate: DateKeys.toDate(map['start_date'] as String),
      lastGeneratedDate: last == null ? null : DateKeys.toDate(last),
      isActive: map['is_active'] == 1,
    );
  }

  final int? id;
  final String label;
  final RecurringKind kind;
  final int amount;
  final int? categoryId;
  final int? goalId;
  final int dayOfMonth;
  final DateTime startDate;

  /// The due date of the last entry this rule created.
  final DateTime? lastGeneratedDate;
  final bool isActive;

  RecurringRule withId(int id) => RecurringRule(
        id: id,
        label: label,
        kind: kind,
        amount: amount,
        categoryId: categoryId,
        goalId: goalId,
        dayOfMonth: dayOfMonth,
        startDate: startDate,
        lastGeneratedDate: lastGeneratedDate,
        isActive: isActive,
      );

  RecurringRule copyWith({
    String? label,
    RecurringKind? kind,
    int? amount,
    int? categoryId,
    int? dayOfMonth,
    DateTime? lastGeneratedDate,
    bool? isActive,
  }) =>
      RecurringRule(
        id: id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        goalId: goalId,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        startDate: startDate,
        lastGeneratedDate: lastGeneratedDate ?? this.lastGeneratedDate,
        isActive: isActive ?? this.isActive,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'goal_id': goalId,
        'day_of_month': dayOfMonth,
        'start_date': DateKeys.fromDate(startDate),
        'last_generated_date': lastGeneratedDate == null
            ? null
            : DateKeys.fromDate(lastGeneratedDate!),
        'is_active': isActive ? 1 : 0,
      };

  @override
  bool operator ==(Object other) =>
      other is RecurringRule &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.amount == amount &&
      other.categoryId == categoryId &&
      other.goalId == goalId &&
      other.dayOfMonth == dayOfMonth &&
      other.startDate == startDate &&
      other.lastGeneratedDate == lastGeneratedDate &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, label, kind, amount, categoryId, goalId,
      dayOfMonth, startDate, lastGeneratedDate, isActive);
}
