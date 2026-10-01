# Phase 1 — Foundation (MVP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the counter template with a working offline expense tracker: add/edit/delete income and expenses, see the period's remaining money on Home, browse transactions by period, and set the period start day and currency.

**Architecture:** GetX Pattern (modules with `bindings/ controllers/ views/ widgets/`), app-wide `GetxService`s, repositories over a raw `sqflite` database, and pure-Dart money logic in `lib/app/core/logic`. Screens refresh through `DatabaseService.revision` (an `RxInt` bumped after every write) that controllers watch with `ever`.

**Tech Stack:** Flutter 3.44.8 / Dart ^3.12.2, `get`, `sqflite`, `path`, `flutter_localizations`; dev: `sqflite_common_ffi`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-01-expense-tracker-design.md`

## Global Constraints

- Fully offline: no network packages (no `google_fonts`, no `http`); `android/app/src/main/AndroidManifest.xml` must not declare `INTERNET`.
- Amounts are `int` thousandths of the currency unit; `Money.scale == 1000` for every currency.
- Calendar dates are stored as `TEXT 'YYYY-MM-DD'`; timestamps (`created_at`) as `INTEGER` milliseconds since epoch.
- UI text is Arabic, RTL (`Locale('ar')`); code, comments, README in English.
- Period start day is 1–28, default 1.
- GetX rules (spec §8.3): views never touch repositories/services; controllers never build layout; money math only in `core/logic` / `core/utils/money.dart`; named routes only; one class per file where it is public.
- The model class for categories is `TransactionCategory` (Flutter's foundation library already exports a `Category` class).

## Review Focus

1. Typing awkward amounts ("." first, "00", a 4th decimal, a 10th digit) → keypad ignores the invalid key, never crashes, never saves 0. *(Task 2: `amount_input_test.dart`, `money_test.dart`)*
2. Periods that cross a year boundary or fall exactly on the start day → the date belongs to the period that starts that day. *(Task 3: `period_test.dart`)*
3. Overspending → Remaining goes negative and is shown with a minus sign, never clamped. *(Task 2 `money_test.dart`, Task 6 `balance_calculator_test.dart`)*
4. Swipe-delete then Undo → the exact same record (id, date, note, created_at) comes back. *(Task 5 `transaction_repository_test.dart`, Task 10 `transactions_controller_test.dart`)*
5. Switching currency from JOD (3 decimals) to USD (2 decimals) after entries exist → stored amounts keep their meaning. *(Task 2 `money_test.dart`, Task 11 `settings_controller_test.dart`)*

## File Map

```
lib/main.dart                                         bootstrap
lib/app/app_widget.dart                               GetMaterialApp (RTL, theme, routes)
lib/app/bindings/initial_binding.dart                 registers services + repositories
lib/app/routes/app_routes.dart, app_pages.dart        named routes
lib/app/core/utils/money.dart, amount_input.dart, date_utils.dart, currencies.dart
lib/app/core/logic/period.dart, balance_calculator.dart, day_group.dart
lib/app/core/theme/app_colors.dart, app_theme.dart, category_icons.dart
lib/app/data/models/enums.dart, transaction_category.dart, transaction_record.dart, savings_movement.dart, app_settings.dart
lib/app/data/providers/app_database.dart
lib/app/data/repositories/settings_repository.dart, category_repository.dart, transaction_repository.dart, savings_repository.dart
lib/app/services/database_service.dart, settings_service.dart
lib/app/widgets/money_text.dart, category_avatar.dart, transaction_tile.dart, amount_keypad.dart, app_bottom_nav.dart, empty_state.dart, section_header.dart, period_switcher.dart
lib/app/modules/home/{bindings,controllers,views,widgets}/...
lib/app/modules/transaction_form/{bindings,controllers,views,widgets}/...
lib/app/modules/transactions/{bindings,controllers,views}/...
lib/app/modules/settings/{bindings,controllers,views}/...
test/helpers/test_database.dart, test_services.dart, fixtures.dart
test/... mirrors lib/app
```

---

### Task 1: Project setup and dependencies

**Files:**
- Modify: `pubspec.yaml` (via `flutter pub add`)
- Delete: `test/widget_test.dart` (counter test)
- Modify: `lib/main.dart` (temporary minimal app so the project compiles; replaced in Task 12)

**Interfaces:**
- Produces: packages `get`, `sqflite`, `path`, `flutter_localizations`, dev `sqflite_common_ffi` available.

- [ ] **Step 1: Add dependencies**

```bash
flutter pub add get sqflite path
flutter pub add flutter_localizations --sdk=flutter
flutter pub add dev:sqflite_common_ffi
```

- [ ] **Step 2: Replace the counter app with a placeholder and remove its test**

```dart
// file: lib/main.dart
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('مصاريفي')))));
}
```

```bash
git rm -q test/widget_test.dart
```

- [ ] **Step 3: Verify the manifest has no INTERNET permission and analysis is clean**

Run: `grep -c INTERNET android/app/src/main/AndroidManifest.xml; flutter analyze`
Expected: `0` and `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: add GetX and sqflite dependencies, remove counter template"
```

---

### Task 2: Money, amount input and currencies

**Files:**
- Create: `lib/app/core/utils/money.dart`, `lib/app/core/utils/amount_input.dart`, `lib/app/core/utils/currencies.dart`
- Test: `test/core/utils/money_test.dart`, `test/core/utils/amount_input_test.dart`

**Interfaces:**
- Produces: `Money.scale`, `Money.maxWholeDigits`, `Money.parse(String, {required int decimals}) → int?`, `Money.format(int, {required int decimals, bool showPlus}) → String`, `Money.toEditable(int) → String`; `AmountInput.append(String current, String key, {required int decimals}) → String`, `AmountInput.backspace(String) → String`; `Currency {code, symbol, name, decimals}`, `Currencies.jod`, `Currencies.all`, `Currencies.byCode(String) → Currency`.

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/core/utils/money_test.dart
import 'package:calculator/app/core/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money.parse', () {
    test('parses whole and fractional dinars into fils', () {
      expect(Money.parse('12', decimals: 3), 12000);
      expect(Money.parse('1.5', decimals: 3), 1500);
      expect(Money.parse('0.250', decimals: 3), 250);
      expect(Money.parse('12.', decimals: 3), 12000);
      expect(Money.parse('1,250.5', decimals: 3), 1250500);
      expect(Money.parse(' 7 ', decimals: 3), 7000);
    });

    test('rejects empty, zero, malformed and negative input', () {
      for (final text in ['', '0', '0.000', '.', '.5', '1.2.3', 'abc', '-5', '1e3']) {
        expect(Money.parse(text, decimals: 3), isNull, reason: text);
      }
    });

    test('rejects more fraction digits than the currency allows', () {
      expect(Money.parse('1.2345', decimals: 3), isNull);
      expect(Money.parse('1.255', decimals: 2), isNull);
      expect(Money.parse('1.25', decimals: 2), 1250);
    });

    test('limits the whole part to 9 digits, ignoring leading zeros', () {
      expect(Money.parse('999999999', decimals: 3), 999999999000);
      expect(Money.parse('1000000000', decimals: 3), isNull);
      expect(Money.parse('0005', decimals: 3), 5000);
    });
  });

  group('Money.format', () {
    test('groups thousands and pads decimals', () {
      expect(Money.format(1250000, decimals: 3), '1,250.000');
      expect(Money.format(1500, decimals: 3), '1.500');
      expect(Money.format(0, decimals: 3), '0.000');
      expect(Money.format(999999999000, decimals: 3), '999,999,999.000');
    });

    test('shows negative amounts with a minus sign (overspending)', () {
      expect(Money.format(-12500, decimals: 3), '-12.500');
      expect(Money.format(-1250000, decimals: 3), '-1,250.000');
    });

    test('adds a plus sign only when asked and only for positive amounts', () {
      expect(Money.format(1500, decimals: 3, showPlus: true), '+1.500');
      expect(Money.format(0, decimals: 3, showPlus: true), '0.000');
      expect(Money.format(-1500, decimals: 3, showPlus: true), '-1.500');
    });

    test('the same stored amount keeps its meaning after a currency switch', () {
      expect(Money.format(1250, decimals: 3), '1.250');
      expect(Money.format(1250, decimals: 2), '1.25');
      expect(Money.format(1250000, decimals: 0), '1,250');
    });
  });

  test('toEditable round-trips through parse', () {
    for (final amount in [1, 250, 1500, 12000, 1250500]) {
      expect(Money.parse(Money.toEditable(amount), decimals: 3), amount);
    }
    expect(Money.toEditable(12500), '12.5');
    expect(Money.toEditable(12000), '12');
  });
}
```

```dart
// file: test/core/utils/amount_input_test.dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/utils`
Expected: FAIL — `money.dart` / `amount_input.dart` not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/core/utils/money.dart
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
```

```dart
// file: lib/app/core/utils/amount_input.dart
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
```

```dart
// file: lib/app/core/utils/currencies.dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/utils`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/core/utils test/core/utils && git commit -m "feat: add money parsing/formatting, keypad input rules and currencies"
```

---

### Task 3: Dates and financial periods

**Files:**
- Create: `lib/app/core/utils/date_utils.dart`, `lib/app/core/logic/period.dart`
- Test: `test/core/utils/date_utils_test.dart`, `test/core/logic/period_test.dart`

**Interfaces:**
- Produces: `DateKeys.fromDate(DateTime) → String`, `DateKeys.toDate(String) → DateTime`, `DateKeys.dateOnly(DateTime) → DateTime`; `ArabicDates.dayMonth(DateTime) → String`, `ArabicDates.relativeDay(DateTime, {required DateTime today}) → String`; `Period.containing(DateTime, {required int startDay})`, `.start`, `.end` (exclusive), `.lastDay`, `.key`, `.label`, `.contains(DateTime)`, `.previous`, `.next`.

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/core/utils/date_utils_test.dart
import 'package:calculator/app/core/utils/date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('date keys round-trip and drop the time of day', () {
    expect(DateKeys.fromDate(DateTime(2026, 3, 7, 23, 59)), '2026-03-07');
    expect(DateKeys.toDate('2026-03-07'), DateTime(2026, 3, 7));
  });

  test('Arabic day and month labels', () {
    expect(ArabicDates.dayMonth(DateTime(2026, 9, 25)), '25 أيلول');
    expect(ArabicDates.dayMonth(DateTime(2026, 1, 1)), '1 كانون الثاني');
  });

  test('relative day labels', () {
    final today = DateTime(2026, 10, 1, 9);
    expect(ArabicDates.relativeDay(DateTime(2026, 10, 1, 22), today: today), 'اليوم');
    expect(ArabicDates.relativeDay(DateTime(2026, 9, 30), today: today), 'أمس');
    expect(ArabicDates.relativeDay(DateTime(2026, 9, 29), today: today), '29 أيلول');
  });
}
```

```dart
// file: test/core/logic/period_test.dart
import 'package:calculator/app/core/logic/period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('start day 1 gives calendar months', () {
    final p = Period.containing(DateTime(2026, 10, 15), startDay: 1);
    expect(p.start, DateTime(2026, 10, 1));
    expect(p.end, DateTime(2026, 11, 1));
    expect(p.lastDay, DateTime(2026, 10, 31));
    expect(p.key, '2026-10');
  });

  test('a date before the start day belongs to the previous period', () {
    final p = Period.containing(DateTime(2026, 10, 10), startDay: 25);
    expect(p.start, DateTime(2026, 9, 25));
    expect(p.end, DateTime(2026, 10, 25));
  });

  test('the start day itself opens a new period', () {
    final p = Period.containing(DateTime(2026, 9, 25, 8), startDay: 25);
    expect(p.start, DateTime(2026, 9, 25));
  });

  test('periods cross the year boundary', () {
    final p = Period.containing(DateTime(2027, 1, 10), startDay: 25);
    expect(p.start, DateTime(2026, 12, 25));
    expect(p.end, DateTime(2027, 1, 25));
    expect(p.key, '2026-12');
    expect(Period.containing(DateTime(2026, 12, 31), startDay: 25), p);
  });

  test('contains ignores the time of day and excludes the end', () {
    final p = Period.containing(DateTime(2026, 10, 15), startDay: 1);
    expect(p.contains(DateTime(2026, 10, 31, 23, 59)), isTrue);
    expect(p.contains(DateTime(2026, 10, 1)), isTrue);
    expect(p.contains(DateTime(2026, 11, 1)), isFalse);
    expect(p.contains(DateTime(2026, 9, 30, 23)), isFalse);
  });

  test('previous and next move one period at a time', () {
    final p = Period.containing(DateTime(2026, 1, 15), startDay: 28);
    expect(p.start, DateTime(2025, 12, 28));
    expect(p.previous.start, DateTime(2025, 11, 28));
    expect(p.previous.end, p.start);
    expect(p.next, Period.containing(DateTime(2026, 2, 1), startDay: 28));
    expect(p.next.end, DateTime(2026, 2, 28));
  });

  test('label shows the first and last day', () {
    final p = Period.containing(DateTime(2026, 10, 1), startDay: 25);
    expect(p.label, '25 أيلول – 24 تشرين الأول');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/utils/date_utils_test.dart test/core/logic/period_test.dart`
Expected: FAIL — files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/core/utils/date_utils.dart
/// Calendar-date helpers. Dates are stored as "YYYY-MM-DD" text so they never
/// shift with time zones.
abstract final class DateKeys {
  static String fromDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

  static DateTime toDate(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// Arabic (Levantine) date labels with Western digits, as in the mockup.
abstract final class ArabicDates {
  static const months = [
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  /// "25 أيلول"
  static String dayMonth(DateTime date) =>
      '${date.day} ${months[date.month - 1]}';

  /// "اليوم", "أمس", or the day and month.
  static String relativeDay(DateTime date, {required DateTime today}) {
    final day = DateKeys.dateOnly(date);
    final now = DateKeys.dateOnly(today);
    if (day == now) return 'اليوم';
    if (day == DateTime(now.year, now.month, now.day - 1)) return 'أمس';
    return dayMonth(day);
  }
}
```

```dart
// file: lib/app/core/logic/period.dart
import '../utils/date_utils.dart';

/// A financial month: from [start] (inclusive) to [end] (exclusive), both on
/// the same day of the month (the user's period start day, 1–28).
class Period {
  const Period._(this.start, this.end);

  /// The period that contains [date] when periods begin on [startDay].
  factory Period.containing(DateTime date, {required int startDay}) {
    assert(startDay >= 1 && startDay <= 28, 'startDay must be 1–28');
    final day = DateKeys.dateOnly(date);
    var start = DateTime(day.year, day.month, startDay);
    if (day.isBefore(start)) start = DateTime(day.year, day.month - 1, startDay);
    return Period._(start, DateTime(start.year, start.month + 1, startDay));
  }

  final DateTime start;
  final DateTime end;

  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  /// "2026-09" — the month in which the period starts.
  String get key =>
      '${start.year}-${start.month.toString().padLeft(2, '0')}';

  /// "25 أيلول – 24 تشرين الأول"
  String get label =>
      '${ArabicDates.dayMonth(start)} – ${ArabicDates.dayMonth(lastDay)}';

  bool contains(DateTime date) {
    final day = DateKeys.dateOnly(date);
    return !day.isBefore(start) && day.isBefore(end);
  }

  Period get previous =>
      Period._(DateTime(start.year, start.month - 1, start.day), start);

  Period get next => Period._(end, DateTime(end.year, end.month + 1, end.day));

  @override
  bool operator ==(Object other) =>
      other is Period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Period($key)';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/core test/core && git commit -m "feat: add date keys, Arabic date labels and financial periods"
```

---

### Task 4: Data models

**Files:**
- Create: `lib/app/data/models/enums.dart`, `transaction_category.dart`, `transaction_record.dart`, `savings_movement.dart`, `app_settings.dart`
- Test: `test/data/models/models_test.dart`

**Interfaces:**
- Produces:
  - `enum TransactionKind { income, expense }`, `enum SavingsSource { manual, monthEnd, recurring }`
  - `TransactionCategory({int? id, required String name, required String iconKey, required int colorValue, required TransactionKind kind, int sortOrder = 0, bool isArchived = false})`, `.fromMap`, `.toMap`
  - `TransactionRecord({int? id, required TransactionKind kind, required int amount, required int categoryId, required DateTime date, String? note, int? recurringRuleId, DateTime? recurringDueDate, required DateTime createdAt})`, `.signedAmount`, `.isAuto`, `.withId(int)`, `.fromMap`, `.toMap`
  - `SavingsMovement({int? id, required int goalId, required int amount, required DateTime date, required SavingsSource source, int? recurringRuleId, DateTime? recurringDueDate, String? note, required DateTime createdAt})`, `.fromMap`, `.toMap`
  - `AppSettings({int periodStartDay = 1, String currencyCode = 'JOD', int currencyDecimals = 3, bool reminderEnabled = true, int reminderMinutes = 1260, String? lastMonthEndPromptPeriod, DateTime? lastBackupAt})`, `.copyWith(...)`, `.fromMap`, `.toMap`
  - All models implement `==` / `hashCode` on every field.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/data/models/models_test.dart
import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/savings_movement.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:calculator/app/data/models/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TransactionCategory round-trips through a database row', () {
    const category = TransactionCategory(
      id: 3,
      name: 'فواتير',
      iconKey: 'bills',
      colorValue: 0xFF0E5E4E,
      kind: TransactionKind.expense,
      sortOrder: 2,
      isArchived: true,
    );
    expect(category.toMap()['is_archived'], 1);
    expect(category.toMap()['kind'], 'expense');
    expect(TransactionCategory.fromMap(category.toMap()), category);
  });

  test('TransactionRecord round-trips and stores dates as text', () {
    final record = TransactionRecord(
      id: 7,
      kind: TransactionKind.expense,
      amount: 12500,
      categoryId: 1,
      date: DateTime(2026, 10, 1),
      note: 'غدا',
      recurringRuleId: 2,
      recurringDueDate: DateTime(2026, 10, 1),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    final map = record.toMap();
    expect(map['date'], '2026-10-01');
    expect(map['created_at'], 1790000000000);
    expect(TransactionRecord.fromMap(map), record);
  });

  test('signedAmount is negative for expenses and positive for income', () {
    final expense = TransactionRecord(
      kind: TransactionKind.expense,
      amount: 5000,
      categoryId: 1,
      date: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
    );
    expect(expense.signedAmount, -5000);
    expect(expense.isAuto, isFalse);
    final income = TransactionRecord(
      kind: TransactionKind.income,
      amount: 5000,
      categoryId: 9,
      date: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
    );
    expect(income.signedAmount, 5000);
    expect(income.withId(4).id, 4);
  });

  test('SavingsMovement round-trips', () {
    final movement = SavingsMovement(
      id: 1,
      goalId: 1,
      amount: -2000,
      date: DateTime(2026, 9, 30),
      source: SavingsSource.monthEnd,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    expect(movement.toMap()['source'], 'monthEnd');
    expect(SavingsMovement.fromMap(movement.toMap()), movement);
  });

  test('AppSettings defaults, copyWith and round-trip', () {
    const defaults = AppSettings();
    expect(defaults.periodStartDay, 1);
    expect(defaults.currencyCode, 'JOD');
    expect(defaults.currencyDecimals, 3);
    final changed = defaults.copyWith(periodStartDay: 25, currencyCode: 'USD', currencyDecimals: 2);
    expect(changed.periodStartDay, 25);
    expect(changed.reminderMinutes, defaults.reminderMinutes);
    expect(AppSettings.fromMap(changed.toMap()), changed);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models`
Expected: FAIL — model files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/data/models/enums.dart
enum TransactionKind { income, expense }

enum SavingsSource { manual, monthEnd, recurring }
```

```dart
// file: lib/app/data/models/transaction_category.dart
import 'enums.dart';

class TransactionCategory {
  const TransactionCategory({
    this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    required this.kind,
    this.sortOrder = 0,
    this.isArchived = false,
  });

  factory TransactionCategory.fromMap(Map<String, Object?> map) =>
      TransactionCategory(
        id: map['id'] as int?,
        name: map['name'] as String,
        iconKey: map['icon_key'] as String,
        colorValue: map['color_value'] as int,
        kind: TransactionKind.values.byName(map['kind'] as String),
        sortOrder: map['sort_order'] as int,
        isArchived: map['is_archived'] == 1,
      );

  final int? id;
  final String name;
  final String iconKey;
  final int colorValue;
  final TransactionKind kind;
  final int sortOrder;
  final bool isArchived;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
        'color_value': colorValue,
        'kind': kind.name,
        'sort_order': sortOrder,
        'is_archived': isArchived ? 1 : 0,
      };

  @override
  bool operator ==(Object other) =>
      other is TransactionCategory &&
      other.id == id &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.colorValue == colorValue &&
      other.kind == kind &&
      other.sortOrder == sortOrder &&
      other.isArchived == isArchived;

  @override
  int get hashCode =>
      Object.hash(id, name, iconKey, colorValue, kind, sortOrder, isArchived);
}
```

```dart
// file: lib/app/data/models/transaction_record.dart
import '../../core/utils/date_utils.dart';
import 'enums.dart';

/// One income or expense entry. [amount] is always positive; [kind] gives
/// the direction.
class TransactionRecord {
  const TransactionRecord({
    this.id,
    required this.kind,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note,
    this.recurringRuleId,
    this.recurringDueDate,
    required this.createdAt,
  });

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    final dueDate = map['recurring_due_date'] as String?;
    return TransactionRecord(
      id: map['id'] as int?,
      kind: TransactionKind.values.byName(map['kind'] as String),
      amount: map['amount'] as int,
      categoryId: map['category_id'] as int,
      date: DateKeys.toDate(map['date'] as String),
      note: map['note'] as String?,
      recurringRuleId: map['recurring_rule_id'] as int?,
      recurringDueDate: dueDate == null ? null : DateKeys.toDate(dueDate),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final TransactionKind kind;
  final int amount;
  final int categoryId;
  final DateTime date;
  final String? note;
  final int? recurringRuleId;
  final DateTime? recurringDueDate;
  final DateTime createdAt;

  /// Positive for income, negative for expenses.
  int get signedAmount => kind == TransactionKind.income ? amount : -amount;

  /// True when a recurring rule generated this entry.
  bool get isAuto => recurringRuleId != null;

  TransactionRecord withId(int id) => TransactionRecord(
        id: id,
        kind: kind,
        amount: amount,
        categoryId: categoryId,
        date: date,
        note: note,
        recurringRuleId: recurringRuleId,
        recurringDueDate: recurringDueDate,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'date': DateKeys.fromDate(date),
        'note': note,
        'recurring_rule_id': recurringRuleId,
        'recurring_due_date':
            recurringDueDate == null ? null : DateKeys.fromDate(recurringDueDate!),
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is TransactionRecord &&
      other.id == id &&
      other.kind == kind &&
      other.amount == amount &&
      other.categoryId == categoryId &&
      other.date == date &&
      other.note == note &&
      other.recurringRuleId == recurringRuleId &&
      other.recurringDueDate == recurringDueDate &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, kind, amount, categoryId, date, note,
      recurringRuleId, recurringDueDate, createdAt);
}
```

```dart
// file: lib/app/data/models/savings_movement.dart
import '../../core/utils/date_utils.dart';
import 'enums.dart';

/// Money moved into (positive [amount]) or out of (negative) a savings goal.
class SavingsMovement {
  const SavingsMovement({
    this.id,
    required this.goalId,
    required this.amount,
    required this.date,
    required this.source,
    this.recurringRuleId,
    this.recurringDueDate,
    this.note,
    required this.createdAt,
  });

  factory SavingsMovement.fromMap(Map<String, Object?> map) {
    final dueDate = map['recurring_due_date'] as String?;
    return SavingsMovement(
      id: map['id'] as int?,
      goalId: map['goal_id'] as int,
      amount: map['amount'] as int,
      date: DateKeys.toDate(map['date'] as String),
      source: SavingsSource.values.byName(map['source'] as String),
      recurringRuleId: map['recurring_rule_id'] as int?,
      recurringDueDate: dueDate == null ? null : DateKeys.toDate(dueDate),
      note: map['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final int goalId;
  final int amount;
  final DateTime date;
  final SavingsSource source;
  final int? recurringRuleId;
  final DateTime? recurringDueDate;
  final String? note;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'goal_id': goalId,
        'amount': amount,
        'date': DateKeys.fromDate(date),
        'source': source.name,
        'recurring_rule_id': recurringRuleId,
        'recurring_due_date':
            recurringDueDate == null ? null : DateKeys.fromDate(recurringDueDate!),
        'note': note,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is SavingsMovement &&
      other.id == id &&
      other.goalId == goalId &&
      other.amount == amount &&
      other.date == date &&
      other.source == source &&
      other.recurringRuleId == recurringRuleId &&
      other.recurringDueDate == recurringDueDate &&
      other.note == note &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, goalId, amount, date, source,
      recurringRuleId, recurringDueDate, note, createdAt);
}
```

```dart
// file: lib/app/data/models/app_settings.dart
class AppSettings {
  const AppSettings({
    this.periodStartDay = 1,
    this.currencyCode = 'JOD',
    this.currencyDecimals = 3,
    this.reminderEnabled = true,
    this.reminderMinutes = 21 * 60,
    this.lastMonthEndPromptPeriod,
    this.lastBackupAt,
  });

  factory AppSettings.fromMap(Map<String, Object?> map) {
    final backupAt = map['last_backup_at'] as int?;
    return AppSettings(
      periodStartDay: map['period_start_day'] as int,
      currencyCode: map['currency_code'] as String,
      currencyDecimals: map['currency_decimals'] as int,
      reminderEnabled: map['reminder_enabled'] == 1,
      reminderMinutes: map['reminder_minutes'] as int,
      lastMonthEndPromptPeriod: map['last_month_end_prompt_period'] as String?,
      lastBackupAt:
          backupAt == null ? null : DateTime.fromMillisecondsSinceEpoch(backupAt),
    );
  }

  final int periodStartDay;
  final String currencyCode;
  final int currencyDecimals;
  final bool reminderEnabled;

  /// Minutes after midnight for the daily reminder (1260 = 21:00).
  final int reminderMinutes;
  final String? lastMonthEndPromptPeriod;
  final DateTime? lastBackupAt;

  AppSettings copyWith({
    int? periodStartDay,
    String? currencyCode,
    int? currencyDecimals,
    bool? reminderEnabled,
    int? reminderMinutes,
  }) =>
      AppSettings(
        periodStartDay: periodStartDay ?? this.periodStartDay,
        currencyCode: currencyCode ?? this.currencyCode,
        currencyDecimals: currencyDecimals ?? this.currencyDecimals,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        lastMonthEndPromptPeriod: lastMonthEndPromptPeriod,
        lastBackupAt: lastBackupAt,
      );

  Map<String, Object?> toMap() => {
        'period_start_day': periodStartDay,
        'currency_code': currencyCode,
        'currency_decimals': currencyDecimals,
        'reminder_enabled': reminderEnabled ? 1 : 0,
        'reminder_minutes': reminderMinutes,
        'last_month_end_prompt_period': lastMonthEndPromptPeriod,
        'last_backup_at': lastBackupAt?.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.periodStartDay == periodStartDay &&
      other.currencyCode == currencyCode &&
      other.currencyDecimals == currencyDecimals &&
      other.reminderEnabled == reminderEnabled &&
      other.reminderMinutes == reminderMinutes &&
      other.lastMonthEndPromptPeriod == lastMonthEndPromptPeriod &&
      other.lastBackupAt == lastBackupAt;

  @override
  int get hashCode => Object.hash(periodStartDay, currencyCode,
      currencyDecimals, reminderEnabled, reminderMinutes,
      lastMonthEndPromptPeriod, lastBackupAt);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/models test/data/models && git commit -m "feat: add data models with database row mapping"
```

---

### Task 5: Database, services and repositories

**Files:**
- Create: `lib/app/data/providers/app_database.dart`, `lib/app/services/database_service.dart`, `lib/app/services/settings_service.dart`, `lib/app/data/repositories/settings_repository.dart`, `category_repository.dart`, `transaction_repository.dart`, `savings_repository.dart`
- Test: `test/helpers/test_database.dart`, `test/helpers/fixtures.dart`, `test/data/providers/app_database_test.dart`, `test/data/repositories/repositories_test.dart`, `test/services/settings_service_test.dart`

**Interfaces:**
- Consumes: models (Task 4), `DateKeys` (Task 3), `Period` (Task 3), `Currencies` (Task 2).
- Produces:
  - `AppDatabase.open({DatabaseFactory? factory, String? path}) → Future<Database>`; seeded expense categories ids 1–8 (`أكل, مواصلات, فواتير, سكن, تسوّق, ترفيه, صحة, أخرى`), income ids 9–10 (`راتب, دخل آخر`), General Savings goal id 1 (`ادخار عام`), settings row id 1.
  - `DatabaseService({DatabaseFactory? factory, String? path})`, `.init() → Future<DatabaseService>`, `.db`, `.revision` (`RxInt`), `.notifyChanged()`.
  - `SettingsRepository(DatabaseService)`: `load()`, `save(AppSettings)` (does not notify).
  - `CategoryRepository(DatabaseService)`: `getAll({TransactionKind? kind, bool includeArchived = false})`.
  - `TransactionRepository(DatabaseService)`: `add(TransactionRecord) → Future<TransactionRecord>`, `update`, `delete(int id)`, `restore(TransactionRecord)`, `getById(int) → Future<TransactionRecord?>`, `getBetween(DateTime start, DateTime endExclusive)`, `getAll()`, `getRecent({int limit = 5})` — lists newest first; every write calls `notifyChanged()`.
  - `SavingsRepository(DatabaseService)`: `getAllMovements()`.
  - `SettingsService(SettingsRepository, DatabaseService)`: `.settings` (`Rx<AppSettings>`), `init()`, `update(AppSettings)` (saves, sets value, then notifies), `currency → Currency`, `currentPeriod([DateTime? now]) → Period`.

- [ ] **Step 1: Write the test helpers and failing tests**

```dart
// file: test/helpers/test_database.dart
import 'package:calculator/app/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fresh, isolated in-memory database for one test.
Future<DatabaseService> openTestDatabase() {
  sqfliteFfiInit();
  return DatabaseService(factory: databaseFactoryFfi, path: inMemoryDatabasePath)
      .init();
}
```

```dart
// file: test/helpers/fixtures.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/savings_movement.dart';
import 'package:calculator/app/data/models/transaction_record.dart';

/// Seeded category ids: 1 = أكل (expense), 9 = راتب (income).
const foodCategoryId = 1;
const salaryCategoryId = 9;

TransactionRecord expense(int amount, DateTime date,
        {int categoryId = foodCategoryId, String? note, DateTime? createdAt}) =>
    TransactionRecord(
      kind: TransactionKind.expense,
      amount: amount,
      categoryId: categoryId,
      date: date,
      note: note,
      createdAt: createdAt ?? date,
    );

TransactionRecord income(int amount, DateTime date,
        {int categoryId = salaryCategoryId}) =>
    TransactionRecord(
      kind: TransactionKind.income,
      amount: amount,
      categoryId: categoryId,
      date: date,
      createdAt: date,
    );

SavingsMovement saving(int amount, DateTime date, {int goalId = 1}) =>
    SavingsMovement(
      goalId: goalId,
      amount: amount,
      date: date,
      source: SavingsSource.manual,
      createdAt: date,
    );
```

```dart
// file: test/data/providers/app_database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database.dart';

void main() {
  test('seeds categories, General Savings and default settings', () async {
    final db = (await openTestDatabase()).db;
    final categories = await db.query('categories', orderBy: 'id');
    expect(categories.where((c) => c['kind'] == 'expense'), hasLength(8));
    expect(categories.where((c) => c['kind'] == 'income'), hasLength(2));
    expect(categories.first['name'], 'أكل');
    expect(categories[8]['name'], 'راتب');

    final goals = await db.query('savings_goals');
    expect(goals.single['is_general'], 1);
    expect(goals.single['name'], 'ادخار عام');

    final settings = (await db.query('settings')).single;
    expect(settings['period_start_day'], 1);
    expect(settings['currency_code'], 'JOD');
    expect(settings['currency_decimals'], 3);
  });

  test('rejects a zero amount', () async {
    final db = (await openTestDatabase()).db;
    expect(
      () => db.insert('transactions', {
        'kind': 'expense',
        'amount': 0,
        'category_id': 1,
        'date': '2026-10-01',
        'created_at': 0,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('a recurring rule can generate each due date only once', () async {
    final db = (await openTestDatabase()).db;
    final ruleId = await db.insert('recurring_rules', {
      'label': 'إيجار',
      'kind': 'expense',
      'amount': 350000,
      'category_id': 4,
      'day_of_month': 1,
      'start_date': '2026-10-01',
    });
    Map<String, Object?> occurrence() => {
          'kind': 'expense',
          'amount': 350000,
          'category_id': 4,
          'date': '2026-10-01',
          'recurring_rule_id': ruleId,
          'recurring_due_date': '2026-10-01',
          'created_at': 0,
        };
    await db.insert('transactions', occurrence());
    expect(() => db.insert('transactions', occurrence()),
        throwsA(isA<DatabaseException>()));
  });

  test('each test database is isolated', () async {
    final first = (await openTestDatabase()).db;
    final second = (await openTestDatabase()).db;
    await first.insert('transactions', {
      'kind': 'expense',
      'amount': 1000,
      'category_id': 1,
      'date': '2026-10-01',
      'created_at': 0,
    });
    expect(await second.query('transactions'), isEmpty);
  });
}
```

```dart
// file: test/data/repositories/repositories_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/category_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/settings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_database.dart';

void main() {
  late DatabaseService database;

  setUp(() async => database = await openTestDatabase());

  group('SettingsRepository', () {
    test('loads defaults and saves changes', () async {
      final repo = SettingsRepository(database);
      final defaults = await repo.load();
      expect(defaults.periodStartDay, 1);
      await repo.save(defaults.copyWith(periodStartDay: 25));
      expect((await repo.load()).periodStartDay, 25);
    });
  });

  group('CategoryRepository', () {
    test('filters by kind and hides archived categories', () async {
      final repo = CategoryRepository(database);
      expect(await repo.getAll(kind: TransactionKind.expense), hasLength(8));
      expect((await repo.getAll(kind: TransactionKind.income)).first.name, 'راتب');
      await database.db.update('categories', {'is_archived': 1},
          where: 'id = ?', whereArgs: [1]);
      expect(await repo.getAll(), hasLength(9));
      expect(await repo.getAll(includeArchived: true), hasLength(10));
    });
  });

  group('TransactionRepository', () {
    late TransactionRepository repo;
    setUp(() => repo = TransactionRepository(database));

    test('add assigns an id and announces the change', () async {
      final before = database.revision.value;
      final saved = await repo.add(expense(5000, DateTime(2026, 10, 1)));
      expect(saved.id, isNotNull);
      expect(await repo.getById(saved.id!), saved);
      expect(database.revision.value, before + 1);
    });

    test('update changes the record in place', () async {
      final saved = await repo.add(expense(5000, DateTime(2026, 10, 1)));
      final edited = expense(7000, DateTime(2026, 10, 2), note: 'x').withId(saved.id!);
      await repo.update(edited);
      expect(await repo.getAll(), [edited]);
    });

    test('delete then restore brings back the identical record', () async {
      final saved = await repo.add(expense(5000, DateTime(2026, 10, 1),
          note: 'قهوة', createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000123)));
      await repo.delete(saved.id!);
      expect(await repo.getById(saved.id!), isNull);
      await repo.restore(saved);
      expect(await repo.getById(saved.id!), saved);
    });

    test('getBetween includes the start and excludes the end', () async {
      await repo.add(expense(1000, DateTime(2026, 9, 30)));
      await repo.add(expense(2000, DateTime(2026, 10, 1)));
      await repo.add(expense(3000, DateTime(2026, 10, 31)));
      await repo.add(expense(4000, DateTime(2026, 11, 1)));
      final october = await repo.getBetween(DateTime(2026, 10, 1), DateTime(2026, 11, 1));
      expect(october.map((t) => t.amount), [3000, 2000]);
    });

    test('getRecent returns the newest entries first', () async {
      for (var day = 1; day <= 7; day++) {
        await repo.add(expense(day * 1000, DateTime(2026, 10, day)));
      }
      final recent = await repo.getRecent(limit: 5);
      expect(recent.map((t) => t.date.day), [7, 6, 5, 4, 3]);
    });
  });

  group('SavingsRepository', () {
    test('returns all movements', () async {
      final repo = SavingsRepository(database);
      expect(await repo.getAllMovements(), isEmpty);
      final movement = saving(100000, DateTime(2026, 10, 1));
      await database.db.insert('savings_movements', movement.toMap()..remove('id'));
      final all = await repo.getAllMovements();
      expect(all.single.amount, 100000);
    });
  });
}
```

```dart
// file: test/services/settings_service_test.dart
import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/repositories/settings_repository.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/test_database.dart';

void main() {
  test('update saves, exposes the new value, then announces the change', () async {
    final database = await openTestDatabase();
    final service = await SettingsService(SettingsRepository(database), database).init();
    AppSettings? seenOnChange;
    ever(database.revision, (_) => seenOnChange = service.settings.value);

    await service.update(service.settings.value.copyWith(periodStartDay: 25));
    await Future<void>.delayed(Duration.zero);

    expect(seenOnChange?.periodStartDay, 25);
    expect((await SettingsRepository(database).load()).periodStartDay, 25);
  });

  test('currency and current period follow the settings', () async {
    final database = await openTestDatabase();
    final service = await SettingsService(SettingsRepository(database), database).init();
    expect(service.currency.code, 'JOD');
    await service.update(service.settings.value
        .copyWith(periodStartDay: 25, currencyCode: 'USD', currencyDecimals: 2));
    expect(service.currency.decimals, 2);
    expect(service.currentPeriod(DateTime(2026, 10, 10)).start, DateTime(2026, 9, 25));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data test/services`
Expected: FAIL — database/repository/service files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/data/providers/app_database.dart
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the SQLite database, creates the schema for every phase and seeds
/// first-run data.
abstract final class AppDatabase {
  static const int version = 1;
  static const String fileName = 'masarifi.db';

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    return dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: dbPath != inMemoryDatabasePath,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _onCreate,
      ),
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final statement in _schema) {
      batch.execute(statement);
    }
    _seed(batch);
    await batch.commit(noResult: true);
  }

  static const _schema = [
    '''
    CREATE TABLE categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      icon_key TEXT NOT NULL,
      color_value INTEGER NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('income', 'expense')),
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE savings_goals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      target_amount INTEGER CHECK (target_amount > 0),
      target_date TEXT,
      is_general INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE recurring_rules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      label TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('income', 'expense', 'saving')),
      amount INTEGER NOT NULL CHECK (amount > 0),
      category_id INTEGER REFERENCES categories(id),
      goal_id INTEGER REFERENCES savings_goals(id),
      day_of_month INTEGER NOT NULL CHECK (day_of_month BETWEEN 1 AND 28),
      start_date TEXT NOT NULL,
      last_generated_date TEXT,
      is_active INTEGER NOT NULL DEFAULT 1
    )''',
    '''
    CREATE TABLE transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL CHECK (kind IN ('income', 'expense')),
      amount INTEGER NOT NULL CHECK (amount > 0),
      category_id INTEGER NOT NULL REFERENCES categories(id),
      date TEXT NOT NULL,
      note TEXT,
      recurring_rule_id INTEGER REFERENCES recurring_rules(id) ON DELETE SET NULL,
      recurring_due_date TEXT,
      created_at INTEGER NOT NULL,
      UNIQUE (recurring_rule_id, recurring_due_date)
    )''',
    'CREATE INDEX idx_transactions_date ON transactions(date)',
    '''
    CREATE TABLE budgets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category_id INTEGER NOT NULL UNIQUE REFERENCES categories(id),
      limit_amount INTEGER NOT NULL CHECK (limit_amount > 0)
    )''',
    '''
    CREATE TABLE savings_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      goal_id INTEGER NOT NULL REFERENCES savings_goals(id),
      amount INTEGER NOT NULL CHECK (amount <> 0),
      date TEXT NOT NULL,
      source TEXT NOT NULL CHECK (source IN ('manual', 'monthEnd', 'recurring')),
      recurring_rule_id INTEGER REFERENCES recurring_rules(id) ON DELETE SET NULL,
      recurring_due_date TEXT,
      note TEXT,
      created_at INTEGER NOT NULL,
      UNIQUE (recurring_rule_id, recurring_due_date)
    )''',
    '''
    CREATE TABLE quick_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      label TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('income', 'expense')),
      amount INTEGER NOT NULL CHECK (amount > 0),
      category_id INTEGER NOT NULL REFERENCES categories(id),
      sort_order INTEGER NOT NULL DEFAULT 0
    )''',
    '''
    CREATE TABLE budget_alerts_sent (
      category_id INTEGER NOT NULL REFERENCES categories(id),
      period_key TEXT NOT NULL,
      threshold INTEGER NOT NULL,
      PRIMARY KEY (category_id, period_key, threshold)
    )''',
    '''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      period_start_day INTEGER NOT NULL DEFAULT 1
        CHECK (period_start_day BETWEEN 1 AND 28),
      currency_code TEXT NOT NULL DEFAULT 'JOD',
      currency_decimals INTEGER NOT NULL DEFAULT 3,
      reminder_enabled INTEGER NOT NULL DEFAULT 1,
      reminder_minutes INTEGER NOT NULL DEFAULT 1260,
      last_month_end_prompt_period TEXT,
      last_backup_at INTEGER
    )''',
  ];

  static void _seed(Batch batch) {
    const categories = [
      ('أكل', 'food', 0xFFC2410C, 'expense'),
      ('مواصلات', 'transport', 0xFF1D4ED8, 'expense'),
      ('فواتير', 'bills', 0xFFB45309, 'expense'),
      ('سكن', 'housing', 0xFF0E3B32, 'expense'),
      ('تسوّق', 'shopping', 0xFFBE185D, 'expense'),
      ('ترفيه', 'entertainment', 0xFF7C3AED, 'expense'),
      ('صحة', 'health', 0xFF0F766E, 'expense'),
      ('أخرى', 'other', 0xFF56645E, 'expense'),
      ('راتب', 'salary', 0xFF0E5E4E, 'income'),
      ('دخل آخر', 'income_other', 0xFF15803D, 'income'),
    ];
    for (final (index, (name, icon, color, kind)) in categories.indexed) {
      batch.insert('categories', {
        'name': name,
        'icon_key': icon,
        'color_value': color,
        'kind': kind,
        'sort_order': index,
      });
    }
    batch.insert('savings_goals', {
      'name': 'ادخار عام',
      'is_general': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    batch.insert('settings', {'id': 1});
  }
}
```

```dart
// file: lib/app/services/database_service.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/providers/app_database.dart';

/// Owns the open database and tells listeners when its data changes.
class DatabaseService extends GetxService {
  DatabaseService({this.factory, this.path});

  final DatabaseFactory? factory;
  final String? path;

  late final Database db;

  /// Bumped after every committed write. Controllers reload with
  /// `ever(database.revision, (_) => load())`.
  final revision = 0.obs;

  Future<DatabaseService> init() async {
    db = await AppDatabase.open(factory: factory, path: path);
    return this;
  }

  void notifyChanged() => revision.value++;

  @override
  void onClose() {
    db.close();
    super.onClose();
  }
}
```

```dart
// file: lib/app/data/repositories/settings_repository.dart
import '../../services/database_service.dart';
import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._database);

  final DatabaseService _database;

  Future<AppSettings> load() async {
    final rows =
        await _database.db.query('settings', where: 'id = ?', whereArgs: [1]);
    return AppSettings.fromMap(rows.single);
  }

  /// Saves without announcing; [SettingsService] announces once its value is
  /// up to date.
  Future<void> save(AppSettings settings) => _database.db
      .update('settings', settings.toMap(), where: 'id = ?', whereArgs: [1]);
}
```

```dart
// file: lib/app/data/repositories/category_repository.dart
import '../../services/database_service.dart';
import '../models/enums.dart';
import '../models/transaction_category.dart';

class CategoryRepository {
  CategoryRepository(this._database);

  final DatabaseService _database;

  Future<List<TransactionCategory>> getAll({
    TransactionKind? kind,
    bool includeArchived = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.name);
    }
    if (!includeArchived) where.add('is_archived = 0');
    final rows = await _database.db.query(
      'categories',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'sort_order, id',
    );
    return rows.map(TransactionCategory.fromMap).toList();
  }
}
```

```dart
// file: lib/app/data/repositories/transaction_repository.dart
import '../../core/utils/date_utils.dart';
import '../../services/database_service.dart';
import '../models/transaction_record.dart';

class TransactionRepository {
  TransactionRepository(this._database);

  final DatabaseService _database;

  static const _table = 'transactions';
  static const _newestFirst = 'date DESC, created_at DESC, id DESC';

  Future<TransactionRecord> add(TransactionRecord record) async {
    final id = await _database.db.insert(_table, record.toMap()..remove('id'));
    _database.notifyChanged();
    return record.withId(id);
  }

  Future<void> update(TransactionRecord record) async {
    await _database.db.update(_table, record.toMap(),
        where: 'id = ?', whereArgs: [record.id]);
    _database.notifyChanged();
  }

  Future<void> delete(int id) async {
    await _database.db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Puts back a deleted record with its original id (used by Undo).
  Future<void> restore(TransactionRecord record) async {
    await _database.db.insert(_table, record.toMap());
    _database.notifyChanged();
  }

  Future<TransactionRecord?> getById(int id) async {
    final rows =
        await _database.db.query(_table, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : TransactionRecord.fromMap(rows.single);
  }

  Future<List<TransactionRecord>> getBetween(
      DateTime start, DateTime endExclusive) async {
    final rows = await _database.db.query(
      _table,
      where: 'date >= ? AND date < ?',
      whereArgs: [DateKeys.fromDate(start), DateKeys.fromDate(endExclusive)],
      orderBy: _newestFirst,
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  Future<List<TransactionRecord>> getAll() async {
    final rows = await _database.db.query(_table, orderBy: _newestFirst);
    return rows.map(TransactionRecord.fromMap).toList();
  }

  Future<List<TransactionRecord>> getRecent({int limit = 5}) async {
    final rows =
        await _database.db.query(_table, orderBy: _newestFirst, limit: limit);
    return rows.map(TransactionRecord.fromMap).toList();
  }
}
```

```dart
// file: lib/app/data/repositories/savings_repository.dart
import '../../services/database_service.dart';
import '../models/savings_movement.dart';

class SavingsRepository {
  SavingsRepository(this._database);

  final DatabaseService _database;

  Future<List<SavingsMovement>> getAllMovements() async {
    final rows =
        await _database.db.query('savings_movements', orderBy: 'date, id');
    return rows.map(SavingsMovement.fromMap).toList();
  }
}
```

```dart
// file: lib/app/services/settings_service.dart
import 'package:get/get.dart';

import '../core/logic/period.dart';
import '../core/utils/currencies.dart';
import '../data/models/app_settings.dart';
import '../data/repositories/settings_repository.dart';
import 'database_service.dart';

/// The current settings, shared by every screen.
class SettingsService extends GetxService {
  SettingsService(this._repository, this._database);

  final SettingsRepository _repository;
  final DatabaseService _database;

  final settings = const AppSettings().obs;

  Future<SettingsService> init() async {
    settings.value = await _repository.load();
    return this;
  }

  Future<void> update(AppSettings value) async {
    await _repository.save(value);
    settings.value = value;
    _database.notifyChanged();
  }

  Currency get currency => Currencies.byCode(settings.value.currencyCode);

  Period currentPeriod([DateTime? now]) => Period.containing(
        now ?? DateTime.now(),
        startDay: settings.value.periodStartDay,
      );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data test/services`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/data lib/app/services test/helpers test/data test/services && git commit -m "feat: add sqflite schema, database and settings services, repositories"
```

---

### Task 6: Balance calculator and day groups

**Files:**
- Create: `lib/app/core/logic/balance_calculator.dart`, `lib/app/core/logic/day_group.dart`
- Test: `test/core/logic/balance_calculator_test.dart`, `test/core/logic/day_group_test.dart`

**Interfaces:**
- Consumes: `Period`, `TransactionRecord`, `SavingsMovement`, fixtures.
- Produces: `BalanceSummary {carriedOver, income, expenses, saved, totalSavings, remaining, total}`; `BalanceCalculator.calculate({required Period period, required Iterable<TransactionRecord> transactions, required Iterable<SavingsMovement> movements}) → BalanceSummary`; `DayGroup {day, transactions, net}`, `DayGroup.group(Iterable<TransactionRecord>) → List<DayGroup>` (newest day first).

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/core/logic/balance_calculator_test.dart
import 'package:calculator/app/core/logic/balance_calculator.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

void main() {
  final october = Period.containing(DateTime(2026, 10, 15), startDay: 1);

  test('the interview example: 500 remaining, 910 saved, 1,410 in total', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [
        income(2000000, DateTime(2026, 9, 1)),
        expense(1240000, DateTime(2026, 9, 10)),
        income(1250000, DateTime(2026, 10, 1)),
        expense(600000, DateTime(2026, 10, 5)),
      ],
      movements: [
        saving(760000, DateTime(2026, 9, 30)),
        saving(100000, DateTime(2026, 10, 2), goalId: 2),
        saving(50000, DateTime(2026, 10, 2), goalId: 3),
      ],
    );
    expect(summary.carriedOver, 0);
    expect(summary.income, 1250000);
    expect(summary.expenses, 600000);
    expect(summary.saved, 150000);
    expect(summary.remaining, 500000);
    expect(summary.totalSavings, 910000);
    expect(summary.total, 1410000);
  });

  test('money left last period and not saved carries over', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [
        income(1000000, DateTime(2026, 9, 1)),
        expense(900000, DateTime(2026, 9, 20)),
      ],
      movements: const [],
    );
    expect(summary.carriedOver, 100000);
    expect(summary.remaining, 100000);
  });

  test('a withdrawal from savings adds back to remaining', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: const [],
      movements: [
        saving(300000, DateTime(2026, 9, 1)),
        saving(-50000, DateTime(2026, 10, 3)),
      ],
    );
    expect(summary.saved, -50000);
    expect(summary.remaining, -300000 + 50000);
    expect(summary.totalSavings, 250000);
  });

  test('overspending makes remaining negative', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [
        income(100000, DateTime(2026, 10, 1)),
        expense(150000, DateTime(2026, 10, 2)),
      ],
      movements: const [],
    );
    expect(summary.remaining, -50000);
    expect(summary.total, -50000);
  });

  test('entries dated after the period are ignored', () {
    final summary = BalanceCalculator.calculate(
      period: october,
      transactions: [expense(5000, DateTime(2026, 11, 1))],
      movements: [saving(5000, DateTime(2026, 11, 1))],
    );
    expect(summary.remaining, 0);
    expect(summary.totalSavings, 0);
  });
}
```

```dart
// file: test/core/logic/day_group_test.dart
import 'package:calculator/app/core/logic/day_group.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

void main() {
  test('groups by day, newest day first, with the net amount', () {
    final groups = DayGroup.group([
      expense(2000, DateTime(2026, 10, 3)),
      income(10000, DateTime(2026, 10, 5)),
      expense(3000, DateTime(2026, 10, 5)),
      expense(1000, DateTime(2026, 10, 3)),
    ]);
    expect(groups.map((g) => g.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 3)]);
    expect(groups.first.net, 7000);
    expect(groups.last.net, -3000);
    expect(groups.last.transactions, hasLength(2));
  });

  test('no transactions means no groups', () {
    expect(DayGroup.group(const []), isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/logic`
Expected: FAIL — `balance_calculator.dart` / `day_group.dart` not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/core/logic/balance_calculator.dart
import '../../data/models/enums.dart';
import '../../data/models/savings_movement.dart';
import '../../data/models/transaction_record.dart';
import 'period.dart';

/// The numbers on the Home card for one period (spec §6.3).
class BalanceSummary {
  const BalanceSummary({
    required this.carriedOver,
    required this.income,
    required this.expenses,
    required this.saved,
    required this.totalSavings,
  });

  /// Money left from earlier periods that was not moved to savings.
  final int carriedOver;
  final int income;
  final int expenses;

  /// Net amount moved to savings during the period (negative after a
  /// withdrawal).
  final int saved;

  /// Everything held in savings at the end of the period.
  final int totalSavings;

  /// "Remaining from salary".
  int get remaining => carriedOver + income - expenses - saved;

  /// "Total you have".
  int get total => remaining + totalSavings;
}

abstract final class BalanceCalculator {
  static BalanceSummary calculate({
    required Period period,
    required Iterable<TransactionRecord> transactions,
    required Iterable<SavingsMovement> movements,
  }) {
    var carriedOver = 0;
    var income = 0;
    var expenses = 0;
    var saved = 0;
    var totalSavings = 0;

    for (final t in transactions) {
      if (!t.date.isBefore(period.end)) continue;
      if (t.date.isBefore(period.start)) {
        carriedOver += t.signedAmount;
      } else if (t.kind == TransactionKind.income) {
        income += t.amount;
      } else {
        expenses += t.amount;
      }
    }

    for (final m in movements) {
      if (!m.date.isBefore(period.end)) continue;
      totalSavings += m.amount;
      if (m.date.isBefore(period.start)) {
        carriedOver -= m.amount;
      } else {
        saved += m.amount;
      }
    }

    return BalanceSummary(
      carriedOver: carriedOver,
      income: income,
      expenses: expenses,
      saved: saved,
      totalSavings: totalSavings,
    );
  }
}
```

```dart
// file: lib/app/core/logic/day_group.dart
import '../../data/models/transaction_record.dart';
import '../utils/date_utils.dart';

/// Transactions of one calendar day, for the grouped list.
class DayGroup {
  const DayGroup({required this.day, required this.transactions});

  final DateTime day;
  final List<TransactionRecord> transactions;

  int get net => transactions.fold(0, (sum, t) => sum + t.signedAmount);

  /// Groups [items] by day, newest day first. Order inside a day is kept
  /// newest first as well.
  static List<DayGroup> group(Iterable<TransactionRecord> items) {
    final sorted = items.toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
    final groups = <DayGroup>[];
    for (final t in sorted) {
      final day = DateKeys.dateOnly(t.date);
      if (groups.isEmpty || groups.last.day != day) {
        groups.add(DayGroup(day: day, transactions: [t]));
      } else {
        groups.last.transactions.add(t);
      }
    }
    return groups;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/logic`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/core/logic test/core/logic && git commit -m "feat: add balance calculator and day grouping"
```

---

### Task 7: Theme, shared widgets, routes and app bootstrap

**Files:**
- Create: `lib/app/core/theme/app_colors.dart`, `app_theme.dart`, `category_icons.dart`; `lib/app/widgets/money_text.dart`, `category_avatar.dart`, `transaction_tile.dart`, `amount_keypad.dart`, `app_bottom_nav.dart`, `empty_state.dart`, `section_header.dart`, `period_switcher.dart`; `lib/app/routes/app_routes.dart`; `lib/app/bindings/initial_binding.dart`; `test/helpers/test_services.dart`
- Test: `test/widgets/shared_widgets_test.dart`

**Interfaces:**
- Consumes: services and repositories (Task 5), `Money`, `Currency`, `ArabicDates`, `Period`.
- Produces:
  - `AppColors.*`, `AppTheme.light`, `CategoryIcons.of(String) → IconData`
  - `MoneyText(int amount, {required Currency currency, TextStyle? style, bool showPlus = false, bool showSymbol = true})`
  - `CategoryAvatar({required TransactionCategory category, double size = 40})`
  - `TransactionTile({required TransactionRecord transaction, required TransactionCategory? category, required Currency currency, required String subtitle, VoidCallback? onTap})`
  - `AmountKeypad({required ValueChanged<String> onKey, required VoidCallback onBackspace, bool showDot = true})`
  - `AppBottomNav({required String current})`, `EmptyState({required IconData icon, required String message})`, `SectionHeader({required String title, String? actionLabel, VoidCallback? onAction})`, `PeriodSwitcher({required Period period, required VoidCallback onPrevious, required VoidCallback onNext})`
  - `Routes.home`, `Routes.transactionForm`, `Routes.transactions`, `Routes.settings`
  - `InitialBinding.initServices({DatabaseFactory? factory, String? path}) → Future<void>`
  - test helpers `setUpTestServices()`, `settle()`

- [ ] **Step 1: Write the test helper and failing widget test**

```dart
// file: test/helpers/test_services.dart
import 'package:calculator/app/bindings/initial_binding.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Registers every app service and repository against a fresh in-memory
/// database.
Future<void> setUpTestServices() async {
  Get.testMode = true;
  Get.reset();
  sqfliteFfiInit();
  await InitialBinding.initServices(
      factory: databaseFactoryFfi, path: inMemoryDatabasePath);
}

/// Lets `ever` workers and the reloads they start finish.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
```

```dart
// file: test/widgets/shared_widgets_test.dart
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/widgets/amount_keypad.dart';
import 'package:calculator/app/widgets/money_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(
      home: Directionality(
          textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  testWidgets('MoneyText shows the amount, sign and currency symbol', (tester) async {
    await tester.pumpWidget(wrap(const MoneyText(-12500, currency: Currencies.jod)));
    expect(find.textContaining('-12.500'), findsOneWidget);
    expect(find.textContaining('د.أ'), findsOneWidget);
  });

  testWidgets('AmountKeypad reports keys and backspace', (tester) async {
    final pressed = <String>[];
    var backspaces = 0;
    await tester.pumpWidget(wrap(AmountKeypad(
      onKey: pressed.add,
      onBackspace: () => backspaces++,
    )));
    await tester.tap(find.text('7'));
    await tester.tap(find.text('.'));
    await tester.tap(find.byTooltip('مسح'));
    expect(pressed, ['7', '.']);
    expect(backspaces, 1);
  });

  testWidgets('AmountKeypad hides the dot for currencies without decimals', (tester) async {
    await tester.pumpWidget(wrap(AmountKeypad(onKey: (_) {}, onBackspace: () {}, showDot: false)));
    expect(find.text('.'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets`
Expected: FAIL — widget files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/core/theme/app_colors.dart
import 'package:flutter/material.dart';

/// Colors from the approved mockup.
abstract final class AppColors {
  static const background = Color(0xFFF3F5F4);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF14211C);
  static const muted = Color(0xFF56645E);
  static const border = Color(0xFFDCE2DF);
  static const divider = Color(0xFFEEF1EF);
  static const primary = Color(0xFF0E5E4E);
  static const primaryDark = Color(0xFF0E3B32);
  static const primaryCard = Color(0xFF1A4D42);
  static const primarySoft = Color(0xFFE3EEEA);
  static const onPrimaryMuted = Color(0xFFB9D3CB);
  static const income = Color(0xFF0E5E4E);
  static const expense = Color(0xFF9A3412);
  static const warning = Color(0xFFC2410C);
  static const warningSoft = Color(0xFFFFF1E6);
  static const danger = Color(0xFF7C2D12);
  static const negativeOnDark = Color(0xFFFFB4A1);
}
```

```dart
// file: lib/app/core/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme:
          const DividerThemeData(color: AppColors.divider, space: 1, thickness: 1),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
```

```dart
// file: lib/app/core/theme/category_icons.dart
import 'package:flutter/material.dart';

/// Maps a category's stored icon key to an icon.
abstract final class CategoryIcons {
  static const Map<String, IconData> _icons = {
    'food': Icons.restaurant,
    'transport': Icons.directions_car_outlined,
    'bills': Icons.bolt,
    'housing': Icons.home_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'entertainment': Icons.movie_outlined,
    'health': Icons.medical_services_outlined,
    'other': Icons.more_horiz,
    'salary': Icons.payments_outlined,
    'income_other': Icons.attach_money,
  };

  static IconData of(String key) => _icons[key] ?? Icons.category_outlined;
}
```

```dart
// file: lib/app/widgets/money_text.dart
import 'package:flutter/material.dart';

import '../core/utils/currencies.dart';
import '../core/utils/money.dart';

/// An amount with its currency symbol. The number is wrapped in a
/// left-to-right isolate so "-12.500" keeps its minus sign on the left inside
/// Arabic text.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    required this.currency,
    this.style,
    this.showPlus = false,
    this.showSymbol = true,
  });

  final int amount;
  final Currency currency;
  final TextStyle? style;
  final bool showPlus;
  final bool showSymbol;

  @override
  Widget build(BuildContext context) {
    final number =
        Money.format(amount, decimals: currency.decimals, showPlus: showPlus);
    final text = '⁦$number⁩';
    return Text(showSymbol ? '$text ${currency.symbol}' : text, style: style);
  }
}
```

```dart
// file: lib/app/widgets/category_avatar.dart
import 'package:flutter/material.dart';

import '../core/theme/category_icons.dart';
import '../data/models/transaction_category.dart';

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 40});

  final TransactionCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(CategoryIcons.of(category.iconKey),
          color: color, size: size * 0.5),
    );
  }
}
```

```dart
// file: lib/app/widgets/transaction_tile.dart
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/currencies.dart';
import '../data/models/enums.dart';
import '../data/models/transaction_category.dart';
import '../data/models/transaction_record.dart';
import 'category_avatar.dart';
import 'money_text.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    required this.category,
    required this.currency,
    required this.subtitle,
    this.onTap,
  });

  final TransactionRecord transaction;
  final TransactionCategory? category;
  final Currency currency;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.kind == TransactionKind.income;
    return ListTile(
      onTap: onTap,
      leading: category == null ? null : CategoryAvatar(category: category!),
      title: Text(category?.name ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      trailing: MoneyText(
        transaction.signedAmount,
        currency: currency,
        showPlus: true,
        showSymbol: false,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isIncome ? AppColors.income : AppColors.expense,
        ),
      ),
    );
  }
}
```

```dart
// file: lib/app/widgets/amount_keypad.dart
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A calculator-style number pad. Always laid out left-to-right, like a
/// phone keypad.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onKey,
    required this.onBackspace,
    this.showDot = true,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final bool showDot;

  static const _digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [
          for (final digit in _digits) _KeyButton(label: digit, onPressed: () => onKey(digit)),
          if (showDot)
            _KeyButton(label: '.', onPressed: () => onKey('.'))
          else
            const SizedBox.shrink(),
          _KeyButton(label: '0', onPressed: () => onKey('0')),
          _KeyButton(
            icon: Icons.backspace_outlined,
            tooltip: 'مسح',
            onPressed: onBackspace,
          ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({this.label, this.icon, this.tooltip, required this.onPressed});

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: icon == null ? AppColors.surface : AppColors.divider,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Center(
          child: icon != null
              ? Icon(icon, color: AppColors.ink)
              : Text(label!,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
```

```dart
// file: lib/app/widgets/empty_state.dart
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
```

```dart
// file: lib/app/widgets/section_header.dart
import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}
```

```dart
// file: lib/app/widgets/period_switcher.dart
import 'package:flutter/material.dart';

import '../core/logic/period.dart';

/// "‹ 1 تشرين الأول – 31 تشرين الأول ›". In RTL the right arrow goes back.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.period,
    required this.onPrevious,
    required this.onNext,
  });

  final Period period;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'الفترة السابقة',
          icon: const Icon(Icons.chevron_right),
          onPressed: onPrevious,
        ),
        Text(period.label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        IconButton(
          tooltip: 'الفترة التالية',
          icon: const Icon(Icons.chevron_left),
          onPressed: onNext,
        ),
      ],
    );
  }
}
```

```dart
// file: lib/app/routes/app_routes.dart
abstract final class Routes {
  static const home = '/home';
  static const transactionForm = '/transaction-form';
  static const transactions = '/transactions';
  static const settings = '/settings';
}
```

```dart
// file: lib/app/widgets/app_bottom_nav.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../routes/app_routes.dart';

/// The main tabs. Switching tabs replaces the stack so Back leaves the app.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.current});

  final String current;

  static const _tabs = [
    (Routes.home, Icons.home_outlined, Icons.home, 'الرئيسية'),
    (Routes.transactions, Icons.receipt_long_outlined, Icons.receipt_long, 'العمليات'),
    (Routes.settings, Icons.settings_outlined, Icons.settings, 'الإعدادات'),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _tabs.indexWhere((tab) => tab.$1 == current),
      onDestinationSelected: (index) {
        final route = _tabs[index].$1;
        if (route != current) Get.offAllNamed(route);
      },
      destinations: [
        for (final (_, icon, selectedIcon, label) in _tabs)
          NavigationDestination(
              icon: Icon(icon), selectedIcon: Icon(selectedIcon), label: label),
      ],
    );
  }
}
```

```dart
// file: lib/app/bindings/initial_binding.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/category_repository.dart';
import '../data/repositories/savings_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';

/// Registers the app-wide services and repositories before the first screen.
/// Async because the database has to open first, so it runs from `main()`
/// instead of a synchronous `Bindings.dependencies()`.
abstract final class InitialBinding {
  static Future<void> initServices({DatabaseFactory? factory, String? path}) async {
    final database = await Get.putAsync(
        () => DatabaseService(factory: factory, path: path).init(),
        permanent: true);
    final settingsRepository =
        Get.put(SettingsRepository(database), permanent: true);
    Get.put(CategoryRepository(database), permanent: true);
    Get.put(TransactionRepository(database), permanent: true);
    Get.put(SavingsRepository(database), permanent: true);
    await Get.putAsync(
        () => SettingsService(settingsRepository, database).init(),
        permanent: true);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widgets && flutter analyze`
Expected: PASS, `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/app test/helpers test/widgets && git commit -m "feat: add theme, shared widgets, routes and service registration"
```

---

### Task 8: Transaction form module (add / edit / delete)

**Files:**
- Create: `lib/app/modules/transaction_form/bindings/transaction_form_binding.dart`, `controllers/transaction_form_controller.dart`, `views/transaction_form_view.dart`, `widgets/kind_toggle.dart`, `widgets/amount_display.dart`, `widgets/category_grid.dart`
- Test: `test/modules/transaction_form/transaction_form_controller_test.dart`

**Interfaces:**
- Consumes: `TransactionRepository`, `CategoryRepository`, `SettingsService`, `AmountInput`, `Money`, shared widgets.
- Produces: `TransactionFormController({required TransactionRepository transactions, required CategoryRepository categories, required SettingsService settings, int? editId})` with `.ready` (`Future<void>`), `.kind`, `.amountText`, `.categoryId`, `.date`, `.noteController`, `.isEditing` (`RxBool`), `.amount`, `.canSave`, `.visibleCategories`, `.currency`, `setKind`, `pressKey`, `backspace`, `selectCategory`, `setDate`, `save() → Future<bool>`, `delete() → Future<void>`. Route `Routes.transactionForm` takes an optional `int` id as `Get.arguments`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/transaction_form/transaction_form_controller_test.dart
import 'package:calculator/app/core/utils/date_utils.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/transaction_form/controllers/transaction_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<TransactionFormController> open({int? editId}) async {
    final controller = Get.put(TransactionFormController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      editId: editId,
    ));
    await controller.ready;
    return controller;
  }

  TransactionRepository repo() => Get.find<TransactionRepository>();

  test('starts as an empty expense that cannot be saved', () async {
    final c = await open();
    expect(c.kind.value, TransactionKind.expense);
    expect(c.amountText.value, '');
    expect(c.canSave, isFalse);
    expect(c.isEditing.value, isFalse);
    expect(c.visibleCategories, hasLength(8));
  });

  test('keypad input plus a category makes it savable', () async {
    final c = await open();
    for (final key in ['1', '.', '5']) {
      c.pressKey(key);
    }
    expect(c.amountText.value, '1.5');
    expect(c.amount, 1500);
    expect(c.canSave, isFalse);
    c.selectCategory(foodCategoryId);
    expect(c.canSave, isTrue);
    c.backspace();
    expect(c.amountText.value, '1.');
  });

  test('switching to income clears the category and shows income categories', () async {
    final c = await open();
    c.selectCategory(foodCategoryId);
    c.setKind(TransactionKind.income);
    expect(c.categoryId.value, isNull);
    expect(c.visibleCategories.map((x) => x.name), ['راتب', 'دخل آخر']);
  });

  test('save adds a dated expense with a trimmed note', () async {
    final c = await open();
    c.pressKey('5');
    c.selectCategory(foodCategoryId);
    c.noteController.text = '  غدا  ';
    expect(await c.save(), isTrue);
    final saved = (await repo().getAll()).single;
    expect(saved.amount, 5000);
    expect(saved.kind, TransactionKind.expense);
    expect(saved.note, 'غدا');
    expect(saved.date, DateKeys.dateOnly(DateTime.now()));
  });

  test('an empty note is stored as null', () async {
    final c = await open();
    c.pressKey('5');
    c.selectCategory(foodCategoryId);
    c.noteController.text = '   ';
    await c.save();
    expect((await repo().getAll()).single.note, isNull);
  });

  test('save refuses without a valid amount', () async {
    final c = await open();
    c.selectCategory(foodCategoryId);
    c.pressKey('0');
    expect(await c.save(), isFalse);
    expect(await repo().getAll(), isEmpty);
  });

  test('editing loads the record and saves it in place', () async {
    final existing = await repo().add(
        expense(12500, DateTime(2026, 9, 20), note: 'غدا'));
    final c = await open(editId: existing.id);
    expect(c.isEditing.value, isTrue);
    expect(c.amountText.value, '12.5');
    expect(c.categoryId.value, foodCategoryId);
    expect(c.noteController.text, 'غدا');
    expect(c.date.value, DateTime(2026, 9, 20));
    c.backspace();
    c.pressKey('7');
    expect(await c.save(), isTrue);
    final all = await repo().getAll();
    expect(all.single.id, existing.id);
    expect(all.single.amount, 12700);
    expect(all.single.createdAt, existing.createdAt);
  });

  test('delete removes the record being edited', () async {
    final existing = await repo().add(expense(5000, DateTime(2026, 9, 20)));
    final c = await open(editId: existing.id);
    await c.delete();
    expect(await repo().getAll(), isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/transaction_form`
Expected: FAIL — controller not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/modules/transaction_form/controllers/transaction_form_controller.dart
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/utils/amount_input.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../services/settings_service.dart';

/// Add a new transaction, or edit/delete the one with [editId].
class TransactionFormController extends GetxController {
  TransactionFormController({
    required this.transactions,
    required this.categories,
    required this.settings,
    this.editId,
  });

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final int? editId;

  final kind = TransactionKind.expense.obs;
  final amountText = ''.obs;
  final categoryId = RxnInt();
  final date = DateKeys.dateOnly(DateTime.now()).obs;
  final isEditing = false.obs;
  final _allCategories = <TransactionCategory>[].obs;
  final noteController = TextEditingController();

  TransactionRecord? _editing;

  /// Completes when categories (and the edited record) are loaded.
  late final Future<void> ready;

  Currency get currency => settings.currency;

  int? get amount => Money.parse(amountText.value, decimals: currency.decimals);

  bool get canSave => amount != null && categoryId.value != null;

  List<TransactionCategory> get visibleCategories =>
      _allCategories.where((c) => c.kind == kind.value).toList();

  @override
  void onInit() {
    super.onInit();
    ready = _load();
  }

  Future<void> _load() async {
    _allCategories.assignAll(await categories.getAll());
    if (editId == null) return;
    final record = await transactions.getById(editId!);
    if (record == null) return;
    _editing = record;
    isEditing.value = true;
    kind.value = record.kind;
    amountText.value = Money.toEditable(record.amount);
    categoryId.value = record.categoryId;
    noteController.text = record.note ?? '';
    date.value = record.date;
  }

  void setKind(TransactionKind value) {
    if (kind.value == value) return;
    kind.value = value;
    categoryId.value = null;
  }

  void pressKey(String key) => amountText.value =
      AmountInput.append(amountText.value, key, decimals: currency.decimals);

  void backspace() => amountText.value = AmountInput.backspace(amountText.value);

  void selectCategory(int id) => categoryId.value = id;

  void setDate(DateTime value) => date.value = DateKeys.dateOnly(value);

  /// Saves the form. Returns false (and saves nothing) when it is incomplete.
  Future<bool> save() async {
    final value = amount;
    final category = categoryId.value;
    if (value == null || category == null) return false;
    final note = noteController.text.trim();
    final record = TransactionRecord(
      id: _editing?.id,
      kind: kind.value,
      amount: value,
      categoryId: category,
      date: date.value,
      note: note.isEmpty ? null : note,
      recurringRuleId: _editing?.recurringRuleId,
      recurringDueDate: _editing?.recurringDueDate,
      createdAt: _editing?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(
              DateTime.now().millisecondsSinceEpoch),
    );
    if (_editing == null) {
      await transactions.add(record);
    } else {
      await transactions.update(record);
    }
    return true;
  }

  Future<void> delete() async {
    final id = _editing?.id;
    if (id != null) await transactions.delete(id);
  }

  @override
  void onClose() {
    noteController.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/transaction_form/bindings/transaction_form_binding.dart
import 'package:get/get.dart';

import '../controllers/transaction_form_controller.dart';

class TransactionFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.lazyPut(() => TransactionFormController(
          transactions: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          editId: args is int ? args : null,
        ));
  }
}
```

```dart
// file: lib/app/modules/transaction_form/widgets/kind_toggle.dart
import 'package:flutter/material.dart';

import '../../../data/models/enums.dart';

class KindToggle extends StatelessWidget {
  const KindToggle({super.key, required this.value, required this.onChanged});

  final TransactionKind value;
  final ValueChanged<TransactionKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<TransactionKind>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: TransactionKind.expense, label: Text('مصروف')),
          ButtonSegment(value: TransactionKind.income, label: Text('دخل')),
        ],
        selected: {value},
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/transaction_form/widgets/amount_display.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';

/// The amount being typed, e.g. "7.25 د.أ".
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.text, required this.currency});

  final String text;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final shown = text.isEmpty ? '0' : text;
    return Column(
      children: [
        const Text('المبلغ', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 4),
        Text(
          '⁦$shown⁩ ${currency.symbol}',
          style: const TextStyle(
              fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
      ],
    );
  }
}
```

```dart
// file: lib/app/modules/transaction_form/widgets/category_grid.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/category_icons.dart';
import '../../../data/models/transaction_category.dart';

class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<TransactionCategory> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.1,
      children: [
        for (final category in categories)
          _CategoryChoice(
            category: category,
            selected: category.id == selectedId,
            onTap: () => onSelected(category.id!),
          ),
      ],
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final TransactionCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CategoryIcons.of(category.iconKey),
                  color: Color(category.colorValue), size: 22),
              const SizedBox(height: 4),
              Text(category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/transaction_form/views/transaction_form_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/amount_keypad.dart';
import '../controllers/transaction_form_controller.dart';
import '../widgets/amount_display.dart';
import '../widgets/category_grid.dart';
import '../widgets/kind_toggle.dart';

class TransactionFormView extends GetView<TransactionFormController> {
  const TransactionFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() =>
            Text(controller.isEditing.value ? 'تعديل عملية' : 'عملية جديدة')),
        actions: [
          Obx(() => controller.isEditing.value
              ? IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context),
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  Obx(() => KindToggle(
                      value: controller.kind.value, onChanged: controller.setKind)),
                  const SizedBox(height: 20),
                  Obx(() => AmountDisplay(
                      text: controller.amountText.value,
                      currency: controller.currency)),
                  const SizedBox(height: 20),
                  const Text('التصنيف',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  Obx(() => CategoryGrid(
                        categories: controller.visibleCategories,
                        selectedId: controller.categoryId.value,
                        onSelected: controller.selectCategory,
                      )),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller.noteController,
                          decoration: const InputDecoration(
                            hintText: 'ملاحظة (اختياري)',
                            prefixIcon: Icon(Icons.edit_note),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Obx(() => OutlinedButton.icon(
                            onPressed: () => _pickDate(context),
                            icon: const Icon(Icons.calendar_today_outlined, size: 18),
                            label: Text(ArabicDates.relativeDay(
                                controller.date.value,
                                today: DateTime.now())),
                          )),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                children: [
                  AmountKeypad(
                    onKey: controller.pressKey,
                    onBackspace: controller.backspace,
                    showDot: controller.currency.decimals > 0,
                  ),
                  const SizedBox(height: 12),
                  Obx(() => FilledButton(
                        onPressed: controller.canSave ? _save : null,
                        child: const Text('حفظ'),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (await controller.save()) Get.back();
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.date.value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) controller.setDate(picked);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف العملية؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.delete();
      Get.back();
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/modules/transaction_form`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/transaction_form test/modules/transaction_form && git commit -m "feat: add transaction form for adding, editing and deleting"
```

---

### Task 9: Home module

**Files:**
- Create: `lib/app/modules/home/bindings/home_binding.dart`, `controllers/home_controller.dart`, `views/home_view.dart`, `widgets/balance_card.dart`, `widgets/recent_transactions.dart`
- Test: `test/modules/home/home_controller_test.dart`

**Interfaces:**
- Consumes: `TransactionRepository`, `CategoryRepository`, `SavingsRepository`, `SettingsService`, `DatabaseService`, `BalanceCalculator`, shared widgets, `Routes`.
- Produces: `HomeController({required ..., DateTime Function()? clock})` with `.summary` (`Rxn<BalanceSummary>`), `.period` (`Rxn<Period>`), `.recent` (`RxList<TransactionRecord>`), `.categoriesById` (`RxMap<int, TransactionCategory>`), `.currency`, `.today`, `load()`, `openAdd()`, `openEdit(TransactionRecord)`, `openAll()`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/home/home_controller_test.dart
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/home/controllers/home_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<HomeController> open(DateTime now) async {
    final controller = Get.put(HomeController(
      transactions: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => now,
    ));
    await controller.load();
    return controller;
  }

  TransactionRepository repo() => Get.find<TransactionRepository>();

  test('summarises the current period', () async {
    await repo().add(income(1250000, DateTime(2026, 10, 1)));
    await repo().add(expense(600000, DateTime(2026, 10, 5)));
    final c = await open(DateTime(2026, 10, 15));
    expect(c.period.value!.key, '2026-10');
    expect(c.summary.value!.remaining, 650000);
    expect(c.categoriesById[foodCategoryId]!.name, 'أكل');
  });

  test('reloads after a change anywhere in the database', () async {
    final c = await open(DateTime(2026, 10, 15));
    await repo().add(expense(5000, DateTime(2026, 10, 15)));
    await settle();
    expect(c.summary.value!.expenses, 5000);
    expect(c.recent, hasLength(1));
  });

  test('recent shows the newest five', () async {
    for (var day = 1; day <= 7; day++) {
      await repo().add(expense(1000, DateTime(2026, 10, day)));
    }
    final c = await open(DateTime(2026, 10, 15));
    expect(c.recent.map((t) => t.date.day), [7, 6, 5, 4, 3]);
  });

  test('follows the period start day from settings', () async {
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value.copyWith(periodStartDay: 25));
    final c = await open(DateTime(2026, 10, 10));
    expect(c.period.value!.start, DateTime(2026, 9, 25));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/home`
Expected: FAIL — controller not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/modules/home/controllers/home_controller.dart
import 'package:get/get.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/logic/period.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class HomeController extends GetxController {
  HomeController({
    required this.transactions,
    required this.categories,
    required this.savings,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SavingsRepository savings;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final summary = Rxn<BalanceSummary>();
  final period = Rxn<Period>();
  final recent = <TransactionRecord>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  DateTime get today => _clock();

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final current = settings.currentPeriod(_clock());
    final all = await transactions.getAll();
    final movements = await savings.getAllMovements();
    final allCategories = await categories.getAll(includeArchived: true);
    final latest = await transactions.getRecent(limit: 5);

    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    recent.assignAll(latest);
    period.value = current;
    summary.value = BalanceCalculator.calculate(
        period: current, transactions: all, movements: movements);
  }

  void openAdd() => Get.toNamed(Routes.transactionForm);

  void openEdit(TransactionRecord t) =>
      Get.toNamed(Routes.transactionForm, arguments: t.id);

  void openAll() => Get.offAllNamed(Routes.transactions);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/home/bindings/home_binding.dart
import 'package:get/get.dart';

import '../controllers/home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => HomeController(
          transactions: Get.find(),
          categories: Get.find(),
          savings: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/home/widgets/balance_card.dart
import 'package:flutter/material.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// "Remaining from salary" with this period's breakdown.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.summary, required this.currency});

  final BalanceSummary summary;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('المتبقي من الراتب',
              style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 13)),
          const SizedBox(height: 4),
          MoneyText(
            summary.remaining,
            currency: currency,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: summary.remaining < 0
                  ? AppColors.negativeOnDark
                  : Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                    label: 'الدخل',
                    amount: summary.income,
                    currency: currency,
                    showPlus: true),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                    label: 'المصاريف',
                    amount: -summary.expenses,
                    currency: currency),
              ),
            ],
          ),
          if (summary.carriedOver != 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('مرحّل من الفترة الماضية: ',
                    style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12)),
                MoneyText(summary.carriedOver,
                    currency: currency,
                    showPlus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.amount,
    required this.currency,
    this.showPlus = false,
  });

  final String label;
  final int amount;
  final Currency currency;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12)),
          const SizedBox(height: 2),
          MoneyText(amount,
              currency: currency,
              showPlus: showPlus,
              showSymbol: false,
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/home/widgets/recent_transactions.dart
import 'package:flutter/material.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/transaction_tile.dart';

class RecentTransactions extends StatelessWidget {
  const RecentTransactions({
    super.key,
    required this.transactions,
    required this.categoriesById,
    required this.currency,
    required this.today,
    required this.onTap,
  });

  final List<TransactionRecord> transactions;
  final Map<int, TransactionCategory> categoriesById;
  final Currency currency;
  final DateTime today;
  final ValueChanged<TransactionRecord> onTap;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'لسا ما سجلت أي عملية. اضغط + لتبدأ',
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (index, t) in transactions.indexed) ...[
            if (index > 0) const Divider(indent: 16, endIndent: 16),
            TransactionTile(
              transaction: t,
              category: categoriesById[t.categoryId],
              currency: currency,
              subtitle: ArabicDates.relativeDay(t.date, today: today),
              onTap: () => onTap(t),
            ),
          ],
        ],
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/home/views/home_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/section_header.dart';
import '../controllers/home_controller.dart';
import '../widgets/balance_card.dart';
import '../widgets/recent_transactions.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final summary = controller.summary.value;
          final period = controller.period.value;
          if (summary == null || period == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              const Text('الشهر المالي',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              Text(period.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              BalanceCard(summary: summary, currency: controller.currency),
              const SizedBox(height: 24),
              SectionHeader(
                title: 'آخر العمليات',
                actionLabel: 'عرض الكل',
                onAction: controller.openAll,
              ),
              const SizedBox(height: 8),
              RecentTransactions(
                transactions: controller.recent.toList(),
                categoriesById: Map.of(controller.categoriesById),
                currency: controller.currency,
                today: controller.today,
                onTap: controller.openEdit,
              ),
            ],
          );
        }),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'إضافة عملية',
        onPressed: controller.openAdd,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const AppBottomNav(current: Routes.home),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/modules/home`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/home test/modules/home && git commit -m "feat: add home screen with period balance and recent transactions"
```

---

### Task 10: Transactions list module

**Files:**
- Create: `lib/app/modules/transactions/bindings/transactions_binding.dart`, `controllers/transactions_controller.dart`, `views/transactions_view.dart`
- Test: `test/modules/transactions/transactions_controller_test.dart`

**Interfaces:**
- Consumes: `TransactionRepository`, `CategoryRepository`, `SettingsService`, `DatabaseService`, `DayGroup`, `Period`, shared widgets.
- Produces: `TransactionsController({required ..., DateTime Function()? clock})` with `.period`, `.groups` (`RxList<DayGroup>`), `.categoriesById`, `.currency`, `load()`, `previousPeriod()`, `nextPeriod()`, `delete(TransactionRecord)` (removes from `groups` synchronously before awaiting), `undoDelete(TransactionRecord)`, `openEdit(TransactionRecord)`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/transactions/transactions_controller_test.dart
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/transactions/controllers/transactions_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<TransactionsController> open(DateTime now) async {
    final controller = Get.put(TransactionsController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => now,
    ));
    await controller.load();
    return controller;
  }

  TransactionRepository repo() => Get.find<TransactionRepository>();

  Future<void> seed() async {
    await repo().add(expense(2000, DateTime(2026, 10, 3)));
    await repo().add(expense(1000, DateTime(2026, 10, 3)));
    await repo().add(income(10000, DateTime(2026, 10, 5)));
    await repo().add(expense(3000, DateTime(2026, 10, 5)));
    await repo().add(expense(9000, DateTime(2026, 9, 20)));
  }

  test('groups the current period by day, newest first', () async {
    await seed();
    final c = await open(DateTime(2026, 10, 15));
    expect(c.groups.map((g) => g.day), [DateTime(2026, 10, 5), DateTime(2026, 10, 3)]);
    expect(c.groups.first.net, 7000);
    expect(c.groups.last.transactions, hasLength(2));
  });

  test('moves to the previous and next period', () async {
    await seed();
    final c = await open(DateTime(2026, 10, 15));
    await c.previousPeriod();
    expect(c.period.value!.key, '2026-09');
    expect(c.groups.single.transactions.single.amount, 9000);
    await c.nextPeriod();
    expect(c.period.value!.key, '2026-10');
  });

  test('delete hides the row at once and undo restores the same record', () async {
    await seed();
    final c = await open(DateTime(2026, 10, 15));
    final target = c.groups.first.transactions.first;
    final pending = c.delete(target);
    expect(c.groups.expand((g) => g.transactions).map((t) => t.id),
        isNot(contains(target.id)));
    await pending;
    expect(await repo().getById(target.id!), isNull);
    await c.undoDelete(target);
    expect(await repo().getById(target.id!), target);
    await settle();
    expect(c.groups.expand((g) => g.transactions).map((t) => t.id), contains(target.id));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/transactions`
Expected: FAIL — controller not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/modules/transactions/controllers/transactions_controller.dart
import 'package:get/get.dart';

import '../../../core/logic/day_group.dart';
import '../../../core/logic/period.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class TransactionsController extends GetxController {
  TransactionsController({
    required this.transactions,
    required this.categories,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final period = Rxn<Period>();
  final groups = <DayGroup>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;

  List<TransactionRecord> _items = const [];
  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  DateTime get today => _clock();

  @override
  void onInit() {
    super.onInit();
    period.value = settings.currentPeriod(_clock());
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final current = period.value ??= settings.currentPeriod(_clock());
    final items = await transactions.getBetween(current.start, current.end);
    final allCategories = await categories.getAll(includeArchived: true);
    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    _items = items;
    groups.assignAll(DayGroup.group(items));
  }

  Future<void> previousPeriod() {
    period.value = period.value!.previous;
    return load();
  }

  Future<void> nextPeriod() {
    period.value = period.value!.next;
    return load();
  }

  /// Removes the row immediately (so a swipe-to-dismiss can finish), then
  /// deletes it from the database.
  Future<void> delete(TransactionRecord record) {
    _items = _items.where((t) => t.id != record.id).toList();
    groups.assignAll(DayGroup.group(_items));
    return transactions.delete(record.id!);
  }

  Future<void> undoDelete(TransactionRecord record) =>
      transactions.restore(record);

  void openEdit(TransactionRecord record) =>
      Get.toNamed(Routes.transactionForm, arguments: record.id);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/transactions/bindings/transactions_binding.dart
import 'package:get/get.dart';

import '../controllers/transactions_controller.dart';

class TransactionsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => TransactionsController(
          transactions: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/transactions/views/transactions_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/logic/day_group.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/transaction_record.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../../../widgets/period_switcher.dart';
import '../../../widgets/transaction_tile.dart';
import '../controllers/transactions_controller.dart';

class TransactionsView extends GetView<TransactionsController> {
  const TransactionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final period = controller.period.value;
          return period == null
              ? const Text('العمليات')
              : PeriodSwitcher(
                  period: period,
                  onPrevious: controller.previousPeriod,
                  onNext: controller.nextPeriod,
                );
        }),
      ),
      body: Obx(() {
        final groups = controller.groups.toList();
        if (groups.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'ما في عمليات بهالفترة',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: groups.length,
          itemBuilder: (context, index) => _DaySection(
            group: groups[index],
            controller: controller,
            onDismissed: (t) => _deleteWithUndo(context, t),
          ),
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.transactions),
    );
  }

  void _deleteWithUndo(BuildContext context, TransactionRecord record) {
    controller.delete(record);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('انحذفت العملية'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () => controller.undoDelete(record),
        ),
      ));
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.group,
    required this.controller,
    required this.onDismissed,
  });

  final DayGroup group;
  final TransactionsController controller;
  final ValueChanged<TransactionRecord> onDismissed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ArabicDates.relativeDay(group.day, today: controller.today),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                MoneyText(group.net,
                    currency: controller.currency,
                    showPlus: true,
                    showSymbol: false,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, t) in group.transactions.indexed) ...[
                  if (index > 0) const Divider(indent: 16, endIndent: 16),
                  Dismissible(
                    key: ValueKey(t.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: AppColors.danger,
                      alignment: AlignmentDirectional.centerEnd,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                    onDismissed: (_) => onDismissed(t),
                    child: TransactionTile(
                      transaction: t,
                      category: controller.categoriesById[t.categoryId],
                      currency: controller.currency,
                      subtitle: t.note ?? (t.isAuto ? 'تلقائي' : ''),
                      onTap: () => controller.openEdit(t),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/modules/transactions`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/transactions test/modules/transactions && git commit -m "feat: add transactions list grouped by day with swipe delete and undo"
```

---

### Task 11: Settings module

**Files:**
- Create: `lib/app/modules/settings/bindings/settings_binding.dart`, `controllers/settings_controller.dart`, `views/settings_view.dart`
- Test: `test/modules/settings/settings_controller_test.dart`

**Interfaces:**
- Consumes: `SettingsService`, `Currencies`, `TransactionRepository` (test only).
- Produces: `SettingsController({required SettingsService settingsService})` with `.settings` (getter, current `AppSettings`), `setStartDay(int)`, `setCurrency(String code)`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/settings/settings_controller_test.dart
import 'package:calculator/app/core/utils/money.dart';
import 'package:calculator/app/data/repositories/settings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  SettingsController open() =>
      Get.put(SettingsController(settingsService: Get.find()));

  test('changing the start day is saved and shared', () async {
    await open().setStartDay(25);
    expect(Get.find<SettingsService>().settings.value.periodStartDay, 25);
    expect((await Get.find<SettingsRepository>().load()).periodStartDay, 25);
  });

  test('changing currency stores its code and decimals', () async {
    final c = open();
    await c.setCurrency('USD');
    expect(c.settings.currencyCode, 'USD');
    expect(c.settings.currencyDecimals, 2);
  });

  test('switching currency keeps the meaning of saved amounts', () async {
    final saved = await Get.find<TransactionRepository>()
        .add(expense(1250, DateTime(2026, 10, 1)));
    await open().setCurrency('USD');
    final reloaded = await Get.find<TransactionRepository>().getById(saved.id!);
    expect(reloaded!.amount, 1250);
    expect(Money.format(reloaded.amount, decimals: 2), '1.25');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/settings`
Expected: FAIL — controller not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/modules/settings/controllers/settings_controller.dart
import 'package:get/get.dart';

import '../../../core/utils/currencies.dart';
import '../../../data/models/app_settings.dart';
import '../../../services/settings_service.dart';

class SettingsController extends GetxController {
  SettingsController({required this.settingsService});

  final SettingsService settingsService;

  /// Reads the reactive value, so an `Obx` that uses it rebuilds on change.
  AppSettings get settings => settingsService.settings.value;

  Future<void> setStartDay(int day) =>
      settingsService.update(settings.copyWith(periodStartDay: day));

  Future<void> setCurrency(String code) {
    final currency = Currencies.byCode(code);
    return settingsService.update(settings.copyWith(
      currencyCode: currency.code,
      currencyDecimals: currency.decimals,
    ));
  }
}
```

```dart
// file: lib/app/modules/settings/bindings/settings_binding.dart
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SettingsController(settingsService: Get.find()));
  }
}
```

```dart
// file: lib/app/modules/settings/views/settings_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: Obx(() {
        final settings = controller.settings;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            const _SectionTitle('الشهر المالي'),
            Card(
              child: ListTile(
                title: const Text('يبدأ الشهر يوم'),
                subtitle: const Text('مثلاً يوم نزول الراتب'),
                trailing: DropdownButton<int>(
                  value: settings.periodStartDay,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var day = 1; day <= 28; day++)
                      DropdownMenuItem(value: day, child: Text('$day')),
                  ],
                  onChanged: (day) {
                    if (day != null) controller.setStartDay(day);
                  },
                ),
              ),
            ),
            const _SectionTitle('العملة'),
            Card(
              child: ListTile(
                title: const Text('العملة'),
                trailing: DropdownButton<String>(
                  value: settings.currencyCode,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final currency in Currencies.all)
                      DropdownMenuItem(
                        value: currency.code,
                        child: Text('${currency.name} (${currency.symbol})'),
                      ),
                  ],
                  onChanged: (code) {
                    if (code != null) controller.setCurrency(code);
                  },
                ),
              ),
            ),
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.settings),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/modules/settings`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/modules/settings test/modules/settings && git commit -m "feat: add settings for period start day and currency"
```

---

### Task 12: Wire the app together, end-to-end test, README

**Files:**
- Create: `lib/app/routes/app_pages.dart`, `lib/app/app_widget.dart`, `test/app_test.dart`, `README.md` (replace)
- Modify: `lib/main.dart`, `android/app/src/main/AndroidManifest.xml` (label), `ios/Runner/Info.plist` (display name)

**Interfaces:**
- Consumes: every module binding and view, `InitialBinding`, `AppTheme`.
- Produces: `AppPages.pages`, `AppWidget`, runnable app.

- [ ] **Step 1: Write the failing end-to-end widget test**

```dart
// file: test/app_test.dart
import 'package:calculator/app/app_widget.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_services.dart';

Future<void> boot(WidgetTester tester) async {
  await tester.runAsync(setUpTestServices);
  await tester.runAsync(() async {
    await tester.pumpWidget(const AppWidget());
    await settle();
  });
  await tester.pump();
}

/// Lets real database work finish, then draws the result.
Future<void> idle(WidgetTester tester) async {
  await tester.runAsync(settle);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('opens on Home with an empty month', (tester) async {
    await boot(tester);
    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.textContaining('لسا ما سجلت'), findsOneWidget);
  });

  testWidgets('adding an expense from the keypad updates Home', (tester) async {
    await boot(tester);

    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);
    expect(find.text('عملية جديدة'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.tap(find.text('أكل'));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    expect(find.text('المتبقي من الراتب'), findsOneWidget);
    expect(find.text('أكل'), findsOneWidget);
    expect(find.textContaining('-5.000'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/app_test.dart`
Expected: FAIL — `app_widget.dart` not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/routes/app_pages.dart
import 'package:get/get.dart';

import '../modules/home/bindings/home_binding.dart';
import '../modules/home/views/home_view.dart';
import '../modules/settings/bindings/settings_binding.dart';
import '../modules/settings/views/settings_view.dart';
import '../modules/transaction_form/bindings/transaction_form_binding.dart';
import '../modules/transaction_form/views/transaction_form_view.dart';
import '../modules/transactions/bindings/transactions_binding.dart';
import '../modules/transactions/views/transactions_view.dart';
import 'app_routes.dart';

abstract final class AppPages {
  static const initial = Routes.home;

  static final pages = [
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: HomeBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.transactions,
      page: () => const TransactionsView(),
      binding: TransactionsBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.settings,
      page: () => const SettingsView(),
      binding: SettingsBinding(),
      transition: Transition.noTransition,
    ),
    GetPage(
      name: Routes.transactionForm,
      page: () => const TransactionFormView(),
      binding: TransactionFormBinding(),
      fullscreenDialog: true,
    ),
  ];
}
```

```dart
// file: lib/app/app_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';

import 'core/theme/app_theme.dart';
import 'routes/app_pages.dart';

class AppWidget extends StatelessWidget {
  const AppWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'مصاريفي',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      initialRoute: AppPages.initial,
      getPages: AppPages.pages,
    );
  }
}
```

```dart
// file: lib/main.dart
import 'package:flutter/material.dart';

import 'app/app_widget.dart';
import 'app/bindings/initial_binding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await InitialBinding.initServices();
  runApp(const AppWidget());
}
```

App name on the home screen:

```bash
sed -i '' 's/android:label="calculator"/android:label="مصاريفي"/' android/app/src/main/AndroidManifest.xml
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName مصاريفي" ios/Runner/Info.plist
```

README (replace the template):

```markdown
// file: README.md
# مصاريفي — Personal Expense Tracker

A personal, fully offline Flutter app for tracking monthly income and expenses.
Arabic (RTL) interface, no accounts, no internet: all data stays on the device in SQLite.

## Features (Phase 1)
- Add, edit and delete income and expenses with a fast keypad and category grid
- Home: "Remaining from salary" for the current financial month, with carry-over from earlier months
- Transactions grouped by day, swipe to delete with Undo, browse previous months
- Settings: the day the financial month starts (1–28) and the currency

Planned: budgets and alerts, recurring fixed costs, daily reminder, quick favorites,
reports, savings goals, month-end savings prompt, backup and restore.
See [the design spec](docs/superpowers/specs/2026-10-01-expense-tracker-design.md).

## Architecture — GetX Pattern

```
lib/app/
  modules/<feature>/
    bindings/     dependency injection for the screen (Get.lazyPut)
    controllers/  GetxController: screen state (.obs) and actions
    views/        GetView: layout only, rebuilt by Obx
    widgets/      widgets used only by this screen
  services/       GetxService singletons (database, settings)
  data/
    models/       plain data classes with toMap / fromMap
    providers/    sqflite database: schema, seed, migrations
    repositories/ the only code that reads or writes data
  core/
    logic/        pure Dart money math (periods, balance) — fully unit-tested
    utils/        money parsing/formatting, dates, currencies
    theme/        colors, theme, category icons
  widgets/        widgets shared by several screens
  routes/         named routes and GetPages
```

Data flows one way: **View → Controller → Repository → sqflite**.
After every write, `DatabaseService.revision` increases; controllers listen with
`ever(...)` and reload, so every open screen stays up to date.

Money is stored as integers in thousandths (1 JOD = 1000 fils) — never as `double`.

## Running

```bash
flutter pub get
flutter run
flutter test
```
```

- [ ] **Step 4: Run the whole suite and analysis**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: wire GetX app with routes, RTL Arabic UI and end-to-end test"
```

- [ ] **Step 6: Run on the iOS simulator and check Home, Add, List and Settings by eye**

Build and launch in the simulator; add an expense and an income, swipe-delete and undo, change the start day and currency.
