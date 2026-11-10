import '../../core/logic/bank_sms_parser.dart';

enum PendingKind { income, expense, debtGave, debtTook }

enum PendingSource { sms, voice }

/// An import candidate (a bank SMS or a voice note) waiting for the user to
/// approve or dismiss it. [amount] is always positive.
class PendingItem {
  const PendingItem({
    this.id,
    required this.source,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    this.smsType,
    this.name,
    this.city,
    this.suggestedCategoryId,
    this.personId,
    this.personName,
    this.note,
    required this.createdAt,
  });

  factory PendingItem.fromMap(Map<String, Object?> map) {
    final smsType = map['sms_type'] as String?;
    return PendingItem(
      id: map['id'] as int?,
      source: PendingSource.values.byName(map['source'] as String),
      kind: PendingKind.values.byName(map['kind'] as String),
      amount: map['amount'] as int,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(map['occurred_at'] as int),
      smsType: smsType == null ? null : BankSmsType.values.byName(smsType),
      name: map['name'] as String?,
      city: map['city'] as String?,
      suggestedCategoryId: map['suggested_category_id'] as int?,
      personId: map['person_id'] as int?,
      personName: map['person_name'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final PendingSource source;
  final PendingKind kind;
  final int amount;
  final DateTime occurredAt;
  final BankSmsType? smsType;
  final String? name;
  final String? city;
  final int? suggestedCategoryId;
  final int? personId;
  final String? personName;
  final String? note;
  final DateTime createdAt;

  /// Key for remembering the category chosen for this merchant or payee.
  String? get learnKey =>
      smsType == null || name == null ? null : learnedKey(smsType!, name!);

  PendingItem withId(int id) => copyWith(id: id);

  PendingItem copyWith({
    int? id,
    PendingSource? source,
    PendingKind? kind,
    int? amount,
    DateTime? occurredAt,
    BankSmsType? smsType,
    String? name,
    String? city,
    int? suggestedCategoryId,
    int? personId,
    String? personName,
    String? note,
    DateTime? createdAt,
  }) =>
      PendingItem(
        id: id ?? this.id,
        source: source ?? this.source,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        occurredAt: occurredAt ?? this.occurredAt,
        smsType: smsType ?? this.smsType,
        name: name ?? this.name,
        city: city ?? this.city,
        suggestedCategoryId: suggestedCategoryId ?? this.suggestedCategoryId,
        personId: personId ?? this.personId,
        personName: personName ?? this.personName,
        note: note ?? this.note,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'source': source.name,
        'kind': kind.name,
        'amount': amount,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'sms_type': smsType?.name,
        'name': name,
        'city': city,
        'suggested_category_id': suggestedCategoryId,
        'person_id': personId,
        'person_name': personName,
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is PendingItem &&
      other.id == id &&
      other.source == source &&
      other.kind == kind &&
      other.amount == amount &&
      other.occurredAt == occurredAt &&
      other.smsType == smsType &&
      other.name == name &&
      other.city == city &&
      other.suggestedCategoryId == suggestedCategoryId &&
      other.personId == personId &&
      other.personName == personName &&
      other.note == note &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, source, kind, amount, occurredAt,
      smsType, name, city, suggestedCategoryId, personId, personName, note,
      createdAt);
}
