import 'dart:convert';

import '../../data/models/pending_item.dart';
import '../utils/date_utils.dart';
import '../utils/money.dart';

/// An expense/income/debt entry extracted from a voice note.
class VoiceResult {
  const VoiceResult({
    required this.kind,
    required this.amount,
    this.category,
    this.person,
    this.note,
    this.date,
  });

  final PendingKind kind;
  final int amount;
  final String? category;
  final String? person;
  final String? note;
  final DateTime? date;
}

/// Builds the prompts sent to the AI. The category prompt carries only the
/// merchant, city and category names (no amounts or personal data).
abstract final class AiPrompts {
  static String category({
    required String merchant,
    String? city,
    required List<String> categories,
  }) {
    final place = (city == null || city.trim().isEmpty) ? '' : '\nCity: $city';
    return 'You categorize a shop for an expense tracker. '
        'The names may be Arabic or English.\n'
        'Merchant: $merchant$place\n'
        'Choose the single best category from this list: '
        '${categories.join(', ')}.\n'
        'Reply with ONLY JSON, no other text, in the form '
        '{"category": "<one name from the list, or null if none fits>"}.';
  }

  static String voice({
    required String text,
    required List<String> categories,
    required List<String> people,
    required DateTime today,
    required String currencyCode,
  }) {
    return 'You extract one money entry from a spoken note for an expense '
        'tracker. The note may be Arabic or English.\n'
        'Note: "$text"\n'
        'Today is ${DateKeys.fromDate(today)}. Currency: $currencyCode.\n'
        'Categories: ${categories.join(', ')}.\n'
        'People: ${people.join(', ')}.\n'
        'Reply with ONLY JSON, no other text, in the form '
        '{"kind": "expense|income|debt_gave|debt_took", '
        '"amount": "<number as text>", '
        '"category": "<one name from Categories or null>", '
        '"person": "<one name from People, or the name mentioned, or null>", '
        '"note": "<short note or null>", '
        '"date": "<YYYY-MM-DD or null if not mentioned>"}.\n'
        'Use debt_gave when the user lent money to someone and debt_took '
        'when the user borrowed money.';
  }
}

/// Strictly parses the AI's JSON replies; anything unexpected yields null.
abstract final class AiResponses {
  static const _kinds = {
    'expense': PendingKind.expense,
    'income': PendingKind.income,
    'debt_gave': PendingKind.debtGave,
    'debt_took': PendingKind.debtTook,
  };

  static String? category(String raw, List<String> allowed) {
    final json = _decode(raw);
    if (json == null) return null;
    final value = json['category'];
    if (value is! String) return null;
    final name = value.trim();
    return allowed.contains(name) ? name : null;
  }

  static VoiceResult? voice(String raw) {
    final json = _decode(raw);
    if (json == null) return null;
    final kind = _kinds[json['kind']];
    if (kind == null) return null;
    final rawAmount = json['amount'];
    if (rawAmount is! String && rawAmount is! num) return null;
    final amount = Money.parse(rawAmount.toString().trim(), decimals: 3);
    if (amount == null) return null;
    return VoiceResult(
      kind: kind,
      amount: amount,
      category: _text(json['category']),
      person: _text(json['person']),
      note: _text(json['note']),
      date: _date(json['date']),
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    final key = value.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return null;
    final date = DateKeys.toDate(key);
    return DateKeys.fromDate(date) == key ? date : null;
  }

  static Map<String, Object?>? _decode(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'^```[a-zA-Z]*\s*([\s\S]*?)\s*```$').firstMatch(text);
    if (fence != null) text = fence.group(1)!;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
