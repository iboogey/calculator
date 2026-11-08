import 'package:calculator/app/data/models/debt_entry.dart';
import 'package:calculator/app/data/models/debt_person.dart';
import 'package:calculator/app/data/models/obligation.dart';
import 'package:calculator/app/data/models/obligation_payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.fromMillisecondsSinceEpoch(1790000000000);

  test('DebtPerson round-trips and rejects wrong types', () {
    final person = DebtPerson(id: 1, name: 'أحمد', createdAt: created);
    expect(DebtPerson.fromMap(person.toMap()), person);
    expect(person.copyWith(name: 'علي').name, 'علي');
    expect(person.withId(5).id, 5);
    expect(() => DebtPerson.fromMap({...person.toMap(), 'name': 5}),
        throwsA(isA<TypeError>()));
  });

  test('DebtEntry round-trips with and without a note', () {
    final entry = DebtEntry(
      id: 2,
      personId: 1,
      amount: -5000,
      date: DateTime(2026, 11, 8),
      note: 'سلفة',
      createdAt: created,
    );
    expect(entry.toMap()['date'], '2026-11-08');
    expect(DebtEntry.fromMap(entry.toMap()), entry);

    final noNote = DebtEntry(
      personId: 1,
      amount: 1000,
      date: DateTime(2026, 11, 8),
      createdAt: created,
    );
    expect(DebtEntry.fromMap(noNote.toMap()), noNote);
    expect(noNote.withId(9).id, 9);
    expect(entry.copyWith(amount: 7).amount, 7);
    expect(
        () => DebtEntry.fromMap({...entry.toMap(), 'amount': '5'}),
        throwsA(isA<TypeError>()));
  });

  test('Obligation round-trips and copyWith can clear optional fields', () {
    final obligation = Obligation(
      id: 3,
      title: 'إيجار',
      amount: 200000,
      dueDate: DateTime(2026, 12, 1),
      note: 'شهري',
      createdAt: created,
    );
    expect(obligation.toMap()['due_date'], '2026-12-01');
    expect(Obligation.fromMap(obligation.toMap()), obligation);

    final cleared = obligation.copyWith(dueDate: () => null, note: () => null);
    expect(cleared.dueDate, isNull);
    expect(cleared.note, isNull);
    expect(Obligation.fromMap(cleared.toMap()), cleared);
    expect(obligation.copyWith(title: 'ماء').title, 'ماء');
    expect(obligation.copyWith(amount: 1).amount, 1);
    expect(obligation.withId(8).id, 8);
    expect(
        () => Obligation.fromMap({...obligation.toMap(), 'amount': '5'}),
        throwsA(isA<TypeError>()));
  });

  test('ObligationPayment round-trips with a null transaction id', () {
    final payment = ObligationPayment(
      id: 4,
      obligationId: 3,
      amount: 50000,
      date: DateTime(2026, 11, 8),
      transactionId: 12,
      createdAt: created,
    );
    expect(ObligationPayment.fromMap(payment.toMap()), payment);

    final noTx = ObligationPayment(
      obligationId: 3,
      amount: 50000,
      date: DateTime(2026, 11, 8),
      createdAt: created,
    );
    expect(ObligationPayment.fromMap(noTx.toMap()), noTx);
    expect(noTx.withId(6).id, 6);
    expect(
        () => ObligationPayment.fromMap({...payment.toMap(), 'amount': '5'}),
        throwsA(isA<TypeError>()));
  });
}
