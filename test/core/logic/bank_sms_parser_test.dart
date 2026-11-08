import 'package:calculator/app/core/logic/bank_sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/sms_fixtures.dart';

void main() {
  test('card purchase', () {
    expect(
      BankSmsParser.parse(smsCard),
      const ParsedBankSms(
        type: BankSmsType.cardPurchase,
        amount: 3500,
        name: 'SAMPLE SUPER MARKET',
        city: 'AMMAN',
      ),
    );
  });

  test('CliQ sent', () {
    expect(
      BankSmsParser.parse(smsCliqSent),
      const ParsedBankSms(
        type: BankSmsType.cliqSent,
        amount: 25000,
        name: 'SAMI KHALED HADDAD',
      ),
    );
  });

  test('CliQ received', () {
    expect(
      BankSmsParser.parse(smsCliqReceived),
      const ParsedBankSms(
        type: BankSmsType.cliqReceived,
        amount: 10000,
        name: 'RANA OMAR SALEH',
      ),
    );
  });

  test('bank fee', () {
    expect(
      BankSmsParser.parse(smsFee),
      const ParsedBankSms(
        type: BankSmsType.bankFee,
        amount: 500,
        name: 'عمولة خدمات مصرفية الية',
      ),
    );
  });

  test('announcement is ignored', () {
    expect(BankSmsParser.parse(smsAnnouncement), isNull);
  });

  test('truncated merchant kept as-is', () {
    expect(BankSmsParser.parse(smsCardTruncated)!.name, 'SAMPLE ELECTRICITY R');
  });

  test('two-space gap still splits merchant and city', () {
    final p = BankSmsParser.parse(smsCardNarrowGap)!;
    expect((p.name, p.city, p.amount), ('SAMPLE FISH REST 2', 'AQABA', 34410));
  });

  test('three-decimal amount', () {
    expect(
      BankSmsParser.parse(smsCard.replaceFirst('3.5', '176.464'))!.amount,
      176464,
    );
  });

  test('Arabic-Indic digits in amount', () {
    expect(
      BankSmsParser.parse(smsCard.replaceFirst('3.5', '٣٫٥'))!.amount,
      3500,
    );
  });

  test('trailing/extra spaces tolerated', () {
    expect(BankSmsParser.parse('  $smsCliqSent  ')!.amount, 25000);
  });

  test('a message wrapped across lines still parses', () {
    expect(BankSmsParser.parse(smsCardWrapped), BankSmsParser.parse(smsCard));
    expect(BankSmsParser.parse(smsCliqSentWrapped),
        BankSmsParser.parse(smsCliqSent));
    expect(BankSmsParser.parse(smsCard), isNotNull);
    expect(BankSmsParser.parse(smsCliqSent), isNotNull);
  });

  test('unparseable amount returns null', () {
    expect(BankSmsParser.parse(smsCard.replaceFirst('3.5', '3.5.1')), isNull);
  });

  test('card merchant with single spaces only (no city split) returns null', () {
    expect(
      BankSmsParser.parse(
        'تفويض حركة على حسابكم 1 - 001 بقيمة 1.0 دينار اردني من SHOP AMMAN JOR الرصيد المتوفر 1.0 دينار اردني',
      ),
      isNull,
    );
  });

  test('OTP-like text returns null', () {
    expect(BankSmsParser.parse('رمز التحقق 123456'), isNull);
  });

  test('learnedKey normalizes', () {
    expect(
      learnedKey(BankSmsType.cardPurchase, ' route   65 '),
      'shop:ROUTE 65',
    );
    expect(
      learnedKey(BankSmsType.cliqReceived, 'Sami  Haddad'),
      'cliq:SAMI HADDAD',
    );
    expect(learnedKey(BankSmsType.bankFee, 'عمولة'), 'fee:عمولة');
  });
}
