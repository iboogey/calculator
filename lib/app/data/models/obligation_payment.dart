import '../../core/utils/date_utils.dart';

/// A payment toward an obligation, optionally linked to the expense it created.
class ObligationPayment {
  const ObligationPayment({
    this.id,
    required this.obligationId,
    required this.amount,
    required this.date,
    this.transactionId,
    required this.createdAt,
  });

  factory ObligationPayment.fromMap(Map<String, Object?> map) =>
      ObligationPayment(
        id: map['id'] as int?,
        obligationId: map['obligation_id'] as int,
        amount: map['amount'] as int,
        date: DateKeys.toDate(map['date'] as String),
        transactionId: map['transaction_id'] as int?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  final int? id;
  final int obligationId;
  final int amount;
  final DateTime date;
  final int? transactionId;
  final DateTime createdAt;

  ObligationPayment withId(int id) => ObligationPayment(
        id: id,
        obligationId: obligationId,
        amount: amount,
        date: date,
        transactionId: transactionId,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'obligation_id': obligationId,
        'amount': amount,
        'date': DateKeys.fromDate(date),
        'transaction_id': transactionId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is ObligationPayment &&
      other.id == id &&
      other.obligationId == obligationId &&
      other.amount == amount &&
      other.date == date &&
      other.transactionId == transactionId &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, obligationId, amount, date, transactionId, createdAt);
}
