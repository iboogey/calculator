/// A monthly spending limit for one expense category.
class Budget {
  const Budget({this.id, required this.categoryId, required this.limitAmount});

  factory Budget.fromMap(Map<String, Object?> map) => Budget(
        id: map['id'] as int?,
        categoryId: map['category_id'] as int,
        limitAmount: map['limit_amount'] as int,
      );

  final int? id;
  final int categoryId;
  final int limitAmount;

  Map<String, Object?> toMap() => {
        'id': id,
        'category_id': categoryId,
        'limit_amount': limitAmount,
      };

  @override
  bool operator ==(Object other) =>
      other is Budget &&
      other.id == id &&
      other.categoryId == categoryId &&
      other.limitAmount == limitAmount;

  @override
  int get hashCode => Object.hash(id, categoryId, limitAmount);
}
