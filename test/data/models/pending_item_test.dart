import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final card = PendingItem(
    id: 1,
    source: PendingSource.sms,
    kind: PendingKind.expense,
    amount: 12500,
    occurredAt: DateTime(2026, 11, 8, 14, 30),
    smsType: BankSmsType.cardPurchase,
    name: 'SAMPLE SUPER MARKET',
    city: 'AMMAN',
    suggestedCategoryId: 1,
    createdAt: DateTime(2026, 11, 8, 15),
  );
  final voice = PendingItem(
    id: 2,
    source: PendingSource.voice,
    kind: PendingKind.debtGave,
    amount: 20000,
    occurredAt: DateTime(2026, 11, 9),
    personId: 3,
    personName: 'سامر',
    note: 'سلفة',
    createdAt: DateTime(2026, 11, 9, 1),
  );

  test('toMap and fromMap round-trip an SMS card item', () {
    final map = card.toMap();
    expect(map['sms_type'], 'cardPurchase');
    expect(map['occurred_at'], DateTime(2026, 11, 8, 14, 30).millisecondsSinceEpoch);
    expect(PendingItem.fromMap(map), card);
  });

  test('toMap and fromMap round-trip a voice debt item', () {
    final back = PendingItem.fromMap(voice.toMap());
    expect(back, voice);
    expect(back.smsType, isNull);
    expect(back.personName, 'سامر');
  });

  test('learnKey is built from sms type and name, null for voice', () {
    expect(card.learnKey, 'shop:SAMPLE SUPER MARKET');
    expect(voice.learnKey, isNull);
  });

  test('withId sets only the id', () {
    final saved = voice.withId(9);
    expect(saved.id, 9);
    expect(saved, voice.copyWith(id: 9));
  });
}
