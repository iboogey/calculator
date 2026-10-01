/// Money helpers.
///
/// Every amount in the app is an [int] in thousandths of the currency unit
/// (1 JOD = 1000 fils). The scale never changes, even for a currency with two
/// decimals, so switching currency never changes what stored amounts mean.
abstract final class Money {
  static const int scale = 1000;
  static const int maxWholeDigits = 9;

  static final RegExp _pattern = RegExp(r'^(\d+)(?:\.(\d*))?$');
  static final RegExp _leadingZeros = RegExp(r'^0+(?=\d)');
  static final RegExp _trailingZeros = RegExp(r'0+$');

  /// Parses a positive amount such as "12", "12.", "0.250" or "1,250.5".
  ///
  /// Returns null for empty, zero, malformed or too precise input.
  static int? parse(String text, {required int decimals}) {
    final match = _pattern.firstMatch(text.trim().replaceAll(',', ''));
    if (match == null) return null;
    final whole = match.group(1)!.replaceFirst(_leadingZeros, '');
    final fraction = match.group(2) ?? '';
    if (whole.length > maxWholeDigits || fraction.length > decimals) {
      return null;
    }
    final value =
        int.parse(whole) * scale + int.parse(fraction.padRight(3, '0'));
    return value > 0 ? value : null;
  }

  /// Formats [amount] with thousands separators and [decimals] fraction
  /// digits: 1250000 → "1,250.000". Negative amounts get a leading "-".
  static String format(
    int amount, {
    required int decimals,
    bool showPlus = false,
  }) {
    final absolute = amount.abs();
    final buffer = StringBuffer(_group(absolute ~/ scale));
    if (decimals > 0) {
      final fraction = (absolute % scale).toString().padLeft(3, '0');
      buffer
        ..write('.')
        ..write(fraction.substring(0, decimals));
    }
    if (amount < 0) return '-$buffer';
    if (showPlus && amount > 0) return '+$buffer';
    return buffer.toString();
  }

  /// The shortest text that [parse] reads back as [amount]: 12500 → "12.5".
  static String toEditable(int amount) {
    final whole = amount ~/ scale;
    final fraction = (amount % scale)
        .toString()
        .padLeft(3, '0')
        .replaceFirst(_trailingZeros, '');
    return fraction.isEmpty ? '$whole' : '$whole.$fraction';
  }

  static String _group(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
