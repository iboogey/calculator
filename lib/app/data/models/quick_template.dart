import 'enums.dart';

/// A favorite ("قهوة · 1.500") that adds a transaction with one tap.
class QuickTemplate {
  const QuickTemplate({
    this.id,
    required this.label,
    required this.kind,
    required this.amount,
    required this.categoryId,
    this.sortOrder = 0,
  });

  factory QuickTemplate.fromMap(Map<String, Object?> map) => QuickTemplate(
        id: map['id'] as int?,
        label: map['label'] as String,
        kind: TransactionKind.values.byName(map['kind'] as String),
        amount: map['amount'] as int,
        categoryId: map['category_id'] as int,
        sortOrder: map['sort_order'] as int,
      );

  final int? id;
  final String label;
  final TransactionKind kind;
  final int amount;
  final int categoryId;
  final int sortOrder;

  QuickTemplate withId(int id) => QuickTemplate(
        id: id,
        label: label,
        kind: kind,
        amount: amount,
        categoryId: categoryId,
        sortOrder: sortOrder,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'sort_order': sortOrder,
      };

  @override
  bool operator ==(Object other) =>
      other is QuickTemplate &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.amount == amount &&
      other.categoryId == categoryId &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(id, label, kind, amount, categoryId, sortOrder);
}
