import '../../core/utils/date_utils.dart';

/// One line in a person's ledger: positive [amount] = I gave (they owe me
/// more), negative = I took (I owe them more).
class DebtEntry {
  const DebtEntry({
    this.id,
    required this.personId,
    required this.amount,
    required this.date,
    this.note,
    required this.createdAt,
  });

  factory DebtEntry.fromMap(Map<String, Object?> map) => DebtEntry(
        id: map['id'] as int?,
        personId: map['person_id'] as int,
        amount: map['amount'] as int,
        date: DateKeys.toDate(map['date'] as String),
        note: map['note'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  final int? id;
  final int personId;
  final int amount;
  final DateTime date;
  final String? note;
  final DateTime createdAt;

  DebtEntry withId(int id) => DebtEntry(
        id: id,
        personId: personId,
        amount: amount,
        date: date,
        note: note,
        createdAt: createdAt,
      );

  DebtEntry copyWith({int? amount, DateTime? date, String? note}) => DebtEntry(
        id: id,
        personId: personId,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'person_id': personId,
        'amount': amount,
        'date': DateKeys.fromDate(date),
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is DebtEntry &&
      other.id == id &&
      other.personId == personId &&
      other.amount == amount &&
      other.date == date &&
      other.note == note &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, personId, amount, date, note, createdAt);
}
