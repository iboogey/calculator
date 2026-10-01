import 'enums.dart';

class TransactionCategory {
  const TransactionCategory({
    this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.kind,
    this.sortOrder = 0,
    this.isArchived = false,
  });

  factory TransactionCategory.fromMap(Map<String, Object?> map) =>
      TransactionCategory(
        id: map['id'] as int?,
        name: map['name'] as String,
        iconKey: map['icon_key'] as String,
        colorValue: map['color_value'] as int,
        kind: TransactionKind.values.byName(map['kind'] as String),
        sortOrder: map['sort_order'] as int,
        isArchived: map['is_archived'] == 1,
      );

  final int? id;
  final String name;
  final String iconKey;
  final int colorValue;
  final TransactionKind kind;
  final int sortOrder;
  final bool isArchived;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
        'color_value': colorValue,
        'kind': kind.name,
        'sort_order': sortOrder,
        'is_archived': isArchived ? 1 : 0,
      };

  @override
  bool operator ==(Object other) =>
      other is TransactionCategory &&
      other.id == id &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.colorValue == colorValue &&
      other.kind == kind &&
      other.sortOrder == sortOrder &&
      other.isArchived == isArchived;

  @override
  int get hashCode =>
      Object.hash(id, name, iconKey, colorValue, kind, sortOrder, isArchived);
}
