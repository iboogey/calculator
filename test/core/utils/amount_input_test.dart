import 'package:calculator/app/core/utils/amount_input.dart';
import 'package:flutter_test/flutter_test.dart';

String? clean(String text, {int decimals = 3}) =>
    AmountInput.clean(text, decimals: decimals);

void main() {
  test('plain amounts pass through', () {
    expect(clean('12.5'), '12.5');
    expect(clean('12.'), '12.');
    expect(clean(''), '');
  });

  test('a dot typed first becomes "0."', () {
    expect(clean('.'), '0.');
    expect(clean('.5'), '0.5');
  });

  test('a second dot, letters or a minus are rejected', () {
    expect(clean('1.5.'), isNull);
    expect(clean('1a'), isNull);
    expect(clean('-1'), isNull);
  });

  test('no dot for a currency without decimals', () {
    expect(clean('1.', decimals: 0), isNull);
    expect(clean('1', decimals: 0), '1');
  });

  test('extra leading zeros are dropped', () {
    expect(clean('00'), '0');
    expect(clean('05'), '5');
    expect(clean('00.5'), '0.5');
  });

  test('stops at the currency decimals', () {
    expect(clean('1.259', decimals: 2), isNull);
    expect(clean('1.25', decimals: 2), '1.25');
    expect(clean('1.2551'), isNull);
  });

  test('stops at 9 whole digits', () {
    expect(clean('999999999'), '999999999');
    expect(clean('9999999999'), isNull);
  });

  test('Arabic keyboard digits and separators become 0–9 and "."', () {
    expect(clean('١٢٫٥'), '12.5');
    expect(clean('۷'), '7');
    expect(clean('3,5'), '3.5');
  });
}
