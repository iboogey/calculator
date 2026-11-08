import 'package:calculator/app/core/utils/arabic_count.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('obligation counts follow Arabic number agreement', () {
    expect(ArabicCount.obligations(1), 'التزام واحد');
    expect(ArabicCount.obligations(2), 'التزامان');
    expect(ArabicCount.obligations(3), '3 التزامات');
    expect(ArabicCount.obligations(10), '10 التزامات');
    expect(ArabicCount.obligations(11), '11 التزامًا');
    expect(ArabicCount.obligations(25), '25 التزامًا');
  });

  test('generic counted noun picks the right form', () {
    String days(int n) =>
        ArabicCount.of(n, one: 'يوم واحد', two: 'يومان', few: 'أيام', many: 'يومًا');
    expect(days(1), 'يوم واحد');
    expect(days(2), 'يومان');
    expect(days(7), '7 أيام');
    expect(days(30), '30 يومًا');
  });

  test('restore summary counts agree and attach the conjunction', () {
    expect(ArabicCount.transactions(1), 'عملية واحدة');
    expect(ArabicCount.transactions(2), 'عمليتان');
    expect(ArabicCount.transactions(5), '5 عمليات');
    expect(ArabicCount.transactions(12), '12 عمليةً');
    expect(ArabicCount.goals(1), 'هدف واحد');
    expect(ArabicCount.goals(2), 'هدفان');
    expect(ArabicCount.goals(5), '5 أهداف');
    expect(ArabicCount.goals(12), '12 هدفًا');
    expect(ArabicCount.restoreSummary(1, 5), 'عملية واحدة و5 أهداف');
    expect(ArabicCount.restoreSummary(5, 1), '5 عمليات وهدف واحد');
  });
}
