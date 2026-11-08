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
}
