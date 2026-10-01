import 'package:calculator/app/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('parses whole and fractional dinars into fils', () {
      expect(Money.parse('12', decimals: 3), 12000);
      expect(Money.parse('1.5', decimals: 3), 1500);
      expect(Money.parse('0.250', decimals: 3), 250);
      expect(Money.parse('12.', decimals: 3), 12000);
      expect(Money.parse('1,250.5', decimals: 3), 1250500);
      expect(Money.parse(' 7 ', decimals: 3), 7000);
    });

    test('rejects empty, zero, malformed and negative input', () {
      for (final text in ['', '0', '0.000', '.', '.5', '1.2.3', 'abc', '-5', '1e3']) {
        expect(Money.parse(text, decimals: 3), isNull, reason: text);
      }
    });

    test('rejects more fraction digits than the currency allows', () {
      expect(Money.parse('1.2345', decimals: 3), isNull);
      expect(Money.parse('1.255', decimals: 2), isNull);
      expect(Money.parse('1.25', decimals: 2), 1250);
    });

    test('limits the whole part to 9 digits, ignoring leading zeros', () {
      expect(Money.parse('999999999', decimals: 3), 999999999000);
      expect(Money.parse('1000000000', decimals: 3), isNull);
      expect(Money.parse('0005', decimals: 3), 5000);
    });
  });

  group('Money.format', () {
    test('groups thousands and pads decimals', () {
      expect(Money.format(1250000, decimals: 3), '1,250.000');
      expect(Money.format(1500, decimals: 3), '1.500');
      expect(Money.format(0, decimals: 3), '0.000');
      expect(Money.format(999999999000, decimals: 3), '999,999,999.000');
    });

    test('shows negative amounts with a minus sign (overspending)', () {
      expect(Money.format(-12500, decimals: 3), '-12.500');
      expect(Money.format(-1250000, decimals: 3), '-1,250.000');
    });

    test('adds a plus sign only when asked and only for positive amounts', () {
      expect(Money.format(1500, decimals: 3, showPlus: true), '+1.500');
      expect(Money.format(0, decimals: 3, showPlus: true), '0.000');
      expect(Money.format(-1500, decimals: 3, showPlus: true), '-1.500');
    });

    test('the same stored amount keeps its meaning after a currency switch', () {
      expect(Money.format(1250, decimals: 3), '1.250');
      expect(Money.format(1250, decimals: 2), '1.25');
      expect(Money.format(1250000, decimals: 0), '1,250');
    });
  });

  test('toEditable round-trips through parse', () {
    for (final amount in [1, 250, 1500, 12000, 1250500]) {
      expect(Money.parse(Money.toEditable(amount), decimals: 3), amount);
    }
    expect(Money.toEditable(12500), '12.5');
    expect(Money.toEditable(12000), '12');
  });
}
