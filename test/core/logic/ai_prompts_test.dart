import 'package:calculator/app/core/logic/ai_prompts.dart';
import 'package:calculator/app/data/models/pending_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allowed = ['طعام', 'مواصلات'];

  group('AiPrompts', () {
    test('category contains merchant, city, categories and JSON shape', () {
      final p = AiPrompts.category(
        merchant: 'ROUTE 65',
        city: 'AMMAN',
        categories: allowed,
      );
      expect(p, contains('ROUTE 65'));
      expect(p, contains('AMMAN'));
      for (final c in allowed) {
        expect(p, contains(c));
      }
      expect(p, contains('{"category"'));
    });

    test('voice contains text, categories, people, date, currency, kinds', () {
      final p = AiPrompts.voice(
        text: 'دفعت خمسة دنانير',
        categories: allowed,
        people: const ['أحمد', 'سارة'],
        today: DateTime(2026, 11, 9),
        currencyCode: 'JOD',
      );
      expect(p, contains('دفعت خمسة دنانير'));
      for (final s in [...allowed, 'أحمد', 'سارة']) {
        expect(p, contains(s));
      }
      expect(p, contains('2026-11-09'));
      expect(p, contains('JOD'));
      expect(p, contains('expense|income|debt_gave|debt_took'));
    });
  });

  group('AiResponses.category', () {
    test('returns an allowed name', () {
      expect(AiResponses.category('{"category":"طعام"}', allowed), 'طعام');
    });
    test('trims the name', () {
      expect(AiResponses.category('{"category":" طعام "}', allowed), 'طعام');
    });
    test('unknown name, null, garbage give null', () {
      expect(AiResponses.category('{"category":"سفر"}', allowed), isNull);
      expect(AiResponses.category('{"category":null}', allowed), isNull);
      expect(AiResponses.category('not json', allowed), isNull);
      expect(AiResponses.category('[1]', allowed), isNull);
    });
    test('parses fenced JSON', () {
      expect(
        AiResponses.category('```json\n{"category":"طعام"}\n```', allowed),
        'طعام',
      );
    });
  });

  group('AiResponses.voice', () {
    test('parses a full expense', () {
      final r = AiResponses.voice(
        '{"kind":"expense","amount":"5.250","category":"طعام","person":null,'
        '"note":"سوبرماركت","date":null}',
      )!;
      expect(r.kind, PendingKind.expense);
      expect(r.amount, 5250);
      expect(r.category, 'طعام');
      expect(r.person, isNull);
      expect(r.note, 'سوبرماركت');
      expect(r.date, isNull);
    });
    test('maps kinds', () {
      PendingKind? k(String s) =>
          AiResponses.voice('{"kind":"$s","amount":"1"}')?.kind;
      expect(k('income'), PendingKind.income);
      expect(k('debt_gave'), PendingKind.debtGave);
      expect(k('debt_took'), PendingKind.debtTook);
      expect(k('gift'), isNull);
    });
    test('accepts Arabic-Indic and numeric amounts', () {
      expect(AiResponses.voice('{"kind":"expense","amount":"٥"}')!.amount, 5000);
      expect(AiResponses.voice('{"kind":"expense","amount":5.5}')!.amount, 5500);
      expect(AiResponses.voice('{"kind":"expense","amount":7}')!.amount, 7000);
    });
    test('missing or zero amount gives null', () {
      expect(AiResponses.voice('{"kind":"expense"}'), isNull);
      expect(AiResponses.voice('{"kind":"expense","amount":"0"}'), isNull);
      expect(AiResponses.voice('{"kind":"expense","amount":null}'), isNull);
    });
    test('parses a valid date, ignores a bad one', () {
      expect(
        AiResponses.voice('{"kind":"expense","amount":"1","date":"2026-11-08"}')!
            .date,
        DateTime(2026, 11, 8),
      );
      for (final d in ['2026-13-45', 'yesterday', '2026-02-30']) {
        final r =
            AiResponses.voice('{"kind":"expense","amount":"1","date":"$d"}');
        expect(r, isNotNull);
        expect(r!.date, isNull);
      }
    });
    test('garbage gives null', () {
      expect(AiResponses.voice('hello'), isNull);
    });
  });
}
