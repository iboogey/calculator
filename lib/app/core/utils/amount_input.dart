import 'money.dart';

/// Rules for typing an amount into the amount field.
abstract final class AmountInput {
  static final RegExp _shape = RegExp(r'^\d*\.?\d*$');
  static final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');

  /// Cleans what the keyboard produced: Arabic-Indic digits become 0–9, a
  /// "," or "٫" becomes ".", a lone leading "." becomes "0." and extra
  /// leading zeros go ("05" → "5").
  ///
  /// Returns null when the text cannot be an amount in a currency with
  /// [decimals] fraction digits (letters, two dots, too many digits), so the
  /// field keeps its previous text.
  static String? clean(String raw, {required int decimals}) {
    final text = Money.toAsciiDigits(
        raw.replaceAll(',', '.').replaceAll('٬', '.').trim());
    if (text.isEmpty) return '';
    if (!_shape.hasMatch(text)) return null;
    final dot = text.indexOf('.');
    if (dot != -1 && decimals == 0) return null;
    var whole = dot == -1 ? text : text.substring(0, dot);
    final fraction = dot == -1 ? '' : text.substring(dot + 1);
    whole = whole.replaceFirst(_leadingZeros, '');
    if (whole.isEmpty && dot != -1) whole = '0';
    if (whole.length > Money.maxWholeDigits || fraction.length > decimals) {
      return null;
    }
    return dot == -1 ? whole : '$whole.$fraction';
  }
}
