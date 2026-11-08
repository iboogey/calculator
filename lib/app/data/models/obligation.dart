import '../../core/utils/date_utils.dart';

/// Something I must pay (rent, a bill, an instalment), optionally with a due date.
class Obligation {
  const Obligation({
    this.id,
    required this.title,
    required this.amount,
    this.dueDate,
    this.note,
    required this.createdAt,
  });

  factory Obligation.fromMap(Map<String, Object?> map) {
    final due = map['due_date'] as String?;
    return Obligation(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: map['amount'] as int,
      dueDate: due == null ? null : DateKeys.toDate(due),
      note: map['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final String title;
  final int amount;
  final DateTime? dueDate;
  final String? note;
  final DateTime createdAt;

  Obligation withId(int id) => Obligation(
        id: id,
        title: title,
        amount: amount,
        dueDate: dueDate,
        note: note,
        createdAt: createdAt,
      );

  Obligation copyWith({
    String? title,
    int? amount,
    DateTime? Function()? dueDate,
    String? Function()? note,
  }) =>
      Obligation(
        id: id,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        dueDate: dueDate == null ? this.dueDate : dueDate(),
        note: note == null ? this.note : note(),
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'amount': amount,
        'due_date': dueDate == null ? null : DateKeys.fromDate(dueDate!),
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is Obligation &&
      other.id == id &&
      other.title == title &&
      other.amount == amount &&
      other.dueDate == dueDate &&
      other.note == note &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, title, amount, dueDate, note, createdAt);
}
