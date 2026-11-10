import '../utils/money.dart';

/// The kinds of bank SMS the app understands.
enum BankSmsType { cardPurchase, cliqSent, cliqReceived, bankFee }

/// A bank SMS reduced to what the app may keep: type, amount (thousandths),
/// and a name (merchant, CliQ counterparty or fee reason). [city] is only set
/// for card purchases. The account number and balance are dropped on purpose.
class ParsedBankSms {
  const ParsedBankSms({
    required this.type,
    required this.amount,
    required this.name,
    this.city,
  });

  final BankSmsType type;
  final int amount;
  final String name;
  final String? city;

  @override
  bool operator ==(Object other) =>
      other is ParsedBankSms &&
      other.type == type &&
      other.amount == amount &&
      other.name == name &&
      other.city == city;

  @override
  int get hashCode => Object.hash(type, amount, name, city);

  @override
  String toString() => 'ParsedBankSms($type, $amount, $name, $city)';
}

/// Key under which a learned category is remembered for a merchant,
/// counterparty or fee reason.
String learnedKey(BankSmsType type, String name) {
  final prefix = switch (type) {
    BankSmsType.cardPurchase => 'shop:',
    BankSmsType.cliqSent || BankSmsType.cliqReceived => 'cliq:',
    BankSmsType.bankFee => 'fee:',
  };
  return '$prefix${name.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase()}';
}

/// Parses Jordanian bank SMS bodies. Anything not matching one of the four
/// known templates (announcements, OTPs, ...) yields null.
abstract final class BankSmsParser {
  static const String _amount = r'([\d٠-٩.,٫]+)';
  static const String _account = r'[\d\s-]+';
  static const String _balance =
      r'الرصيد\s+المتوفر\s+[\d٠-٩.,٫]+\s+دينار\s+اردني';

  static final RegExp _card = RegExp(
    '^تفويض\\s+حركة\\s+على\\s+حسابكم\\s+$_account\\s+بقيمة\\s+$_amount'
    '\\s+دينار\\s+اردني\\s+من\\s+(.+?)\\s+$_balance\$',
  );
  static final RegExp _cliqSent = RegExp(
    '^حوالة\\s+كليك\\s+صادرة\\s+بمبلغ\\s+$_amount\\s+دينار\\s+اردني'
    '\\s+من\\s+حسابكم\\s+$_account\\s+الى\\s+(.+?)\\s+$_balance\$',
  );
  static final RegExp _cliqReceived = RegExp(
    '^حوالة\\s+كليك\\s+واردة\\s+بمبلغ\\s+$_amount\\s+دينار\\s+اردني'
    '\\s+لحسابكم\\s+$_account\\s+من\\s+(.+?)\\s+$_balance\$',
  );
  static final RegExp _fee = RegExp(
    '^قيد\\s+مبلغ\\s+$_amount\\s+دينار\\s+اردني\\s+على\\s+حسابكم'
    '\\s+$_account\\s+وذلك\\s+(.+)\$',
  );
  static final RegExp _gap = RegExp(r'\s{2,}');
  static final RegExp _country = RegExp(r'^[A-Z]{3}$');
  static final RegExp _lineBreaks = RegExp(r'[\r\n]+');

  static ParsedBankSms? parse(String body) {
    // A message wrapped across lines reads as one line.
    final text = body.replaceAll(_lineBreaks, ' ').trim();

    var m = _card.firstMatch(text);
    if (m != null) {
      final amount = Money.parse(m.group(1)!, decimals: 3);
      final parts = m.group(2)!.trim().split(_gap);
      if (amount == null || parts.length != 3 || !_country.hasMatch(parts[2])) {
        return null;
      }
      return ParsedBankSms(
        type: BankSmsType.cardPurchase,
        amount: amount,
        name: parts[0],
        city: parts[1],
      );
    }

    for (final (regex, type) in [
      (_cliqSent, BankSmsType.cliqSent),
      (_cliqReceived, BankSmsType.cliqReceived),
      (_fee, BankSmsType.bankFee),
    ]) {
      m = regex.firstMatch(text);
      if (m == null) continue;
      final amount = Money.parse(m.group(1)!, decimals: 3);
      if (amount == null) return null;
      return ParsedBankSms(
        type: type,
        amount: amount,
        name: m.group(2)!.trim(),
      );
    }
    return null;
  }
}
