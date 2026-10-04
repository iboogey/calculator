import '../../core/utils/date_utils.dart';

/// A savings pot. Exactly one is [isGeneral] ("ادخار عام") and has no target.
class SavingsGoal {
  const SavingsGoal({
    this.id,
    required this.name,
    this.targetAmount,
    this.targetDate,
    this.isGeneral = false,
    this.isArchived = false,
    required this.createdAt,
  });

  factory SavingsGoal.fromMap(Map<String, Object?> map) {
    final date = map['target_date'] as String?;
    return SavingsGoal(
      id: map['id'] as int?,
      name: map['name'] as String,
      targetAmount: map['target_amount'] as int?,
      targetDate: date == null ? null : DateKeys.toDate(date),
      isGeneral: map['is_general'] == 1,
      isArchived: map['is_archived'] == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final String name;
  final int? targetAmount;
  final DateTime? targetDate;
  final bool isGeneral;
  final bool isArchived;
  final DateTime createdAt;

  SavingsGoal withId(int id) => SavingsGoal(
        id: id,
        name: name,
        targetAmount: targetAmount,
        targetDate: targetDate,
        isGeneral: isGeneral,
        isArchived: isArchived,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'target_amount': targetAmount,
        'target_date': targetDate == null ? null : DateKeys.fromDate(targetDate!),
        'is_general': isGeneral ? 1 : 0,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is SavingsGoal &&
      other.id == id &&
      other.name == name &&
      other.targetAmount == targetAmount &&
      other.targetDate == targetDate &&
      other.isGeneral == isGeneral &&
      other.isArchived == isArchived &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
      id, name, targetAmount, targetDate, isGeneral, isArchived, createdAt);
}
