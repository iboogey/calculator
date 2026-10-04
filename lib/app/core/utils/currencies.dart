class Currency {
  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.decimals,
  });

  final String code;
  final String symbol;
  final String name;
  final int decimals;
}

abstract final class Currencies {
  static const jod =
      Currency(code: 'JOD', symbol: 'د.أ', name: 'دينار أردني', decimals: 3);

  static const all = [
    jod,
    Currency(code: 'USD', symbol: r'$', name: 'دولار أمريكي', decimals: 2),
    Currency(code: 'EUR', symbol: '€', name: 'يورو', decimals: 2),
    Currency(code: 'SAR', symbol: 'ر.س', name: 'ريال سعودي', decimals: 2),
    Currency(code: 'AED', symbol: 'د.إ', name: 'درهم إماراتي', decimals: 2),
    Currency(code: 'KWD', symbol: 'د.ك', name: 'دينار كويتي', decimals: 3),
    Currency(code: 'EGP', symbol: 'ج.م', name: 'جنيه مصري', decimals: 2),
  ];

  /// The currency with [code], or JOD when the code is unknown.
  static Currency byCode(String code) =>
      all.firstWhere((c) => c.code == code, orElse: () => jod);
}
