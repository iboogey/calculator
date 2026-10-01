import 'money.dart';

/// Rules for typing an amount on the keypad, one key at a time.
abstract final class AmountInput {
  /// Returns the text after pressing [key] ("0"–"9" or "."), or [current]
  /// unchanged when that key would make the amount invalid.
  static String append(String current, String key, {required int decimals}) {
    if (key == '.') {
      if (decimals == 0 || current.contains('.')) return current;
      return current.isEmpty ? '0.' : '$current.';
    }
    if (current == '0') return key;
    final next = '$current$key';
    final dot = next.indexOf('.');
    final whole = dot == -1 ? next : next.substring(0, dot);
    final fraction = dot == -1 ? '' : next.substring(dot + 1);
    if (whole.length > Money.maxWholeDigits || fraction.length > decimals) {
      return current;
    }
    return next;
  }

  static String backspace(String current) =>
      current.isEmpty ? current : current.substring(0, current.length - 1);
}
