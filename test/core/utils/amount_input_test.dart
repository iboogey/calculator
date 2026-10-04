import 'package:calculator/app/core/utils/amount_input.dart';
import 'package:flutter_test/flutter_test.dart';

String type(List<String> keys, {int decimals = 3}) {
  var text = '';
  for (final key in keys) {
    text = AmountInput.append(text, key, decimals: decimals);
  }
  return text;
}

void main() {
  test('typing digits and a dot builds the amount', () {
    expect(type(['1', '2', '.', '5']), '12.5');
  });

  test('a dot typed first becomes "0."', () {
    expect(type(['.', '5']), '0.5');
  });

  test('a second dot is ignored', () {
    expect(type(['1', '.', '5', '.']), '1.5');
  });

  test('no dot for a currency without decimals', () {
    expect(type(['1', '.'], decimals: 0), '1');
  });

  test('a leading zero is replaced, never repeated', () {
    expect(type(['0', '0']), '0');
    expect(type(['0', '5']), '5');
  });

  test('stops at the currency decimals', () {
    expect(type(['1', '.', '2', '5', '9'], decimals: 2), '1.25');
    expect(type(['1', '.', '2', '5', '5', '1']), '1.255');
  });

  test('stops at 9 whole digits', () {
    expect(type(List.filled(12, '9')), '999999999');
  });

  test('backspace removes the last character', () {
    expect(AmountInput.backspace('12.'), '12');
    expect(AmountInput.backspace('5'), '');
    expect(AmountInput.backspace(''), '');
  });
}
