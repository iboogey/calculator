/// Arabic counted nouns: 1 and 2 use the noun alone (singular / dual),
/// 3–10 a plural, and 11 and above a singular in the accusative.
abstract final class ArabicCount {
  /// [one] and [two] are full phrases ("التزام واحد", "التزامان"); [few] and
  /// [many] are the nouns written after the number.
  static String of(
    int n, {
    required String one,
    required String two,
    required String few,
    required String many,
  }) {
    if (n == 1) return one;
    if (n == 2) return two;
    if (n <= 10) return '$n $few';
    return '$n $many';
  }

  /// "عملية واحدة", "عمليتان", "5 عمليات", "12 عمليةً".
  static String transactions(int n) => of(n,
      one: 'عملية واحدة', two: 'عمليتان', few: 'عمليات', many: 'عمليةً');

  /// "هدف واحد", "هدفان", "5 أهداف", "12 هدفًا".
  static String goals(int n) =>
      of(n, one: 'هدف واحد', two: 'هدفان', few: 'أهداف', many: 'هدفًا');

  /// Both counts joined, with the conjunction attached to the second.
  static String restoreSummary(int transactionCount, int goalCount) =>
      '${transactions(transactionCount)} و${goals(goalCount)}';

  /// "التزام واحد", "التزامان", "3 التزامات", "11 التزامًا".
  static String obligations(int n) => of(n,
      one: 'التزام واحد', two: 'التزامان', few: 'التزامات', many: 'التزامًا');
}
