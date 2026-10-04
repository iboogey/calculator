# Phase 2 — Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Help the user control spending: per-category monthly budgets with in-app and push alerts, recurring fixed income/expenses created automatically, a daily reminder notification, and one-tap favorites, plus two follow-ups from the Phase 1 review (refresh on resume, database error messages).

**Architecture:** Same GetX Pattern as Phase 1. New pure logic in `core/logic` (`BudgetCalculator`, `RecurringGenerator`), new repositories over the existing schema (no migration), new `GetxService`s (`MessageService`, `NotificationService`, `BudgetAlertService`, `StartupService`), and new modules (`budgets`, `recurring`, `recurring_form`, `templates`). The device notification plugin sits behind a `NotificationProvider` interface in `data/providers` so tests use a fake.

**Tech Stack:** Flutter 3.44.8, `get`, `sqflite`, `flutter_local_notifications` 22.3.1, `timezone` 0.11.1, `flutter_timezone` 5.1.1 (all offline).

**Spec:** `docs/superpowers/specs/2026-10-01-expense-tracker-design.md` (§6.5 recurring, §6.6 budgets, §6.7 reminder, §9 screens, §10 Phase 2, §11 errors)

## Global Constraints

- Everything from the Phase 1 plan's Global Constraints still holds (offline, int thousandths, `YYYY-MM-DD` dates, Arabic RTL UI, GetX rules, `TransactionCategory` name).
- No schema change: tables `budgets`, `recurring_rules`, `quick_templates`, `budget_alerts_sent` already exist (Phase 1, schema version 1).
- Budget thresholds: warning at ≥ 80 %, over at ≥ 100 %; each threshold alerts at most once per category per period (`budget_alerts_sent`).
- Recurring day of month 1–28; generation happens on app start and on resume (no background work); unique `(recurring_rule_id, recurring_due_date)` plus `last_generated_date` prevent duplicates.
- Daily reminder default 21:00, text "سجّلت مصاريف اليوم؟"; Android uses `AndroidScheduleMode.inexactAllowWhileIdle` (no exact-alarm permission).
- Controllers report database failures through `Get.find<MessageService>().showError(...)`; they never let a `DatabaseException` escape to the UI.
- Bottom navigation (Phase 2): الرئيسية · العمليات · الميزانية · الإعدادات.

## Review Focus

1. App closed for weeks, or opened twice in a row → each missed recurring entry appears exactly once. *(Task 3 `recurring_generator_test.dart`, Task 4 `recurring_repository_test.dart`)*
2. Many edits around a budget limit, or one expense that jumps straight past 100 % → one notification per threshold per period, never two at once. *(Task 5 `budget_alert_service_test.dart`)*
3. Notifications refused by the user → the app keeps working, nothing is scheduled, Settings explains why. *(Task 5 `notification_service_test.dart`, Task 10 `settings_controller_test.dart`)*
4. A database failure while saving or deleting → a message appears, a swiped row comes back, nothing is half-saved. *(Task 6 tests)*
5. App left open across the period start day → returning to it shows the new period. *(Task 5 `startup_service_test.dart`)*

---

### Task 1: Platform setup for local notifications

**Files:**
- Modify: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/AppDelegate.swift`
- (Dependencies `flutter_local_notifications`, `timezone`, `flutter_timezone` were added when the branch was created.)

**Interfaces:**
- Produces: a project that builds with the notification plugin on Android and iOS.

- [ ] **Step 1: Enable core library desugaring (Android)** — in `android/app/build.gradle.kts` add inside `android { compileOptions { … } }`:

```kotlin
        isCoreLibraryDesugaringEnabled = true
```

and at the end of the file:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

- [ ] **Step 2: Manifest permissions and receivers (Android)** — in `android/app/src/main/AndroidManifest.xml` add before `<application`:

```xml
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

and inside `<application>` (after the `</activity>`):

```xml
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
```

- [ ] **Step 3: Show notifications while the app is open (iOS)** — in `ios/Runner/AppDelegate.swift`, inside `application(_:didFinishLaunchingWithOptions:)` before `return`:

```swift
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
```

- [ ] **Step 4: Verify**

Run: `grep -c INTERNET android/app/src/main/AndroidManifest.xml; flutter analyze; flutter test`
Expected: `0`, `No issues found!`, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: add local notification packages and platform setup"
```

---

### Task 2: Models for budgets, recurring rules and favorites

**Files:**
- Modify: `lib/app/data/models/enums.dart`
- Create: `lib/app/data/models/budget.dart`, `recurring_rule.dart`, `quick_template.dart`
- Test: `test/data/models/phase2_models_test.dart`

**Interfaces:**
- Produces:
  - `enum RecurringKind { income, expense, saving }`
  - `Budget({int? id, required int categoryId, required int limitAmount})`, `fromMap`, `toMap`
  - `RecurringRule({int? id, required String label, required RecurringKind kind, required int amount, int? categoryId, int? goalId, required int dayOfMonth, required DateTime startDate, DateTime? lastGeneratedDate, bool isActive = true})`, `fromMap`, `toMap`, `withId(int)`, `copyWith({String? label, RecurringKind? kind, int? amount, int? categoryId, int? dayOfMonth, bool? isActive})`
  - `QuickTemplate({int? id, required String label, required TransactionKind kind, required int amount, required int categoryId, int sortOrder = 0})`, `fromMap`, `toMap`, `withId(int)`

- [ ] **Step 1: Write the failing test**

```dart
// file: test/data/models/phase2_models_test.dart
import 'package:calculator/app/data/models/budget.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/quick_template.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Budget round-trips', () {
    const budget = Budget(id: 2, categoryId: 1, limitAmount: 200000);
    expect(budget.toMap()['limit_amount'], 200000);
    expect(Budget.fromMap(budget.toMap()), budget);
  });

  test('RecurringRule round-trips with dates as text', () {
    final rule = RecurringRule(
      id: 3,
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: 1,
      startDate: DateTime(2026, 10, 1),
      lastGeneratedDate: DateTime(2026, 10, 1),
      isActive: false,
    );
    final map = rule.toMap();
    expect(map['start_date'], '2026-10-01');
    expect(map['kind'], 'expense');
    expect(map['is_active'], 0);
    expect(RecurringRule.fromMap(map), rule);
  });

  test('RecurringRule copyWith keeps the generation state', () {
    final rule = RecurringRule(
      label: 'نت',
      kind: RecurringKind.expense,
      amount: 25000,
      categoryId: 3,
      dayOfMonth: 5,
      startDate: DateTime(2026, 1, 1),
      lastGeneratedDate: DateTime(2026, 9, 5),
    ).withId(9);
    final changed = rule.copyWith(amount: 30000, isActive: false);
    expect(changed.id, 9);
    expect(changed.amount, 30000);
    expect(changed.isActive, isFalse);
    expect(changed.lastGeneratedDate, DateTime(2026, 9, 5));
    expect(changed.startDate, DateTime(2026, 1, 1));
  });

  test('QuickTemplate round-trips', () {
    const template = QuickTemplate(
        id: 1, label: 'قهوة', kind: TransactionKind.expense, amount: 1500, categoryId: 1, sortOrder: 2);
    expect(QuickTemplate.fromMap(template.toMap()), template);
    expect(template.withId(5).id, 5);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/phase2_models_test.dart`
Expected: FAIL — files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/data/models/enums.dart
enum TransactionKind { income, expense }

enum SavingsSource { manual, monthEnd, recurring }

/// What a recurring rule creates: a transaction, or a savings movement.
enum RecurringKind { income, expense, saving }
```

```dart
// file: lib/app/data/models/budget.dart
/// A monthly spending limit for one expense category.
class Budget {
  const Budget({this.id, required this.categoryId, required this.limitAmount});

  factory Budget.fromMap(Map<String, Object?> map) => Budget(
        id: map['id'] as int?,
        categoryId: map['category_id'] as int,
        limitAmount: map['limit_amount'] as int,
      );

  final int? id;
  final int categoryId;
  final int limitAmount;

  Map<String, Object?> toMap() => {
        'id': id,
        'category_id': categoryId,
        'limit_amount': limitAmount,
      };

  @override
  bool operator ==(Object other) =>
      other is Budget &&
      other.id == id &&
      other.categoryId == categoryId &&
      other.limitAmount == limitAmount;

  @override
  int get hashCode => Object.hash(id, categoryId, limitAmount);
}
```

```dart
// file: lib/app/data/models/recurring_rule.dart
import '../../core/utils/date_utils.dart';
import 'enums.dart';

/// "Rent 350 every month on day 1". Income and expense rules need a
/// [categoryId]; saving rules need a [goalId].
class RecurringRule {
  const RecurringRule({
    this.id,
    required this.label,
    required this.kind,
    required this.amount,
    this.categoryId,
    this.goalId,
    required this.dayOfMonth,
    required this.startDate,
    this.lastGeneratedDate,
    this.isActive = true,
  });

  factory RecurringRule.fromMap(Map<String, Object?> map) {
    final last = map['last_generated_date'] as String?;
    return RecurringRule(
      id: map['id'] as int?,
      label: map['label'] as String,
      kind: RecurringKind.values.byName(map['kind'] as String),
      amount: map['amount'] as int,
      categoryId: map['category_id'] as int?,
      goalId: map['goal_id'] as int?,
      dayOfMonth: map['day_of_month'] as int,
      startDate: DateKeys.toDate(map['start_date'] as String),
      lastGeneratedDate: last == null ? null : DateKeys.toDate(last),
      isActive: map['is_active'] == 1,
    );
  }

  final int? id;
  final String label;
  final RecurringKind kind;
  final int amount;
  final int? categoryId;
  final int? goalId;
  final int dayOfMonth;
  final DateTime startDate;

  /// The due date of the last entry this rule created.
  final DateTime? lastGeneratedDate;
  final bool isActive;

  RecurringRule withId(int id) => RecurringRule(
        id: id,
        label: label,
        kind: kind,
        amount: amount,
        categoryId: categoryId,
        goalId: goalId,
        dayOfMonth: dayOfMonth,
        startDate: startDate,
        lastGeneratedDate: lastGeneratedDate,
        isActive: isActive,
      );

  RecurringRule copyWith({
    String? label,
    RecurringKind? kind,
    int? amount,
    int? categoryId,
    int? dayOfMonth,
    bool? isActive,
  }) =>
      RecurringRule(
        id: id,
        label: label ?? this.label,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        goalId: goalId,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        startDate: startDate,
        lastGeneratedDate: lastGeneratedDate,
        isActive: isActive ?? this.isActive,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'goal_id': goalId,
        'day_of_month': dayOfMonth,
        'start_date': DateKeys.fromDate(startDate),
        'last_generated_date': lastGeneratedDate == null
            ? null
            : DateKeys.fromDate(lastGeneratedDate!),
        'is_active': isActive ? 1 : 0,
      };

  @override
  bool operator ==(Object other) =>
      other is RecurringRule &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.amount == amount &&
      other.categoryId == categoryId &&
      other.goalId == goalId &&
      other.dayOfMonth == dayOfMonth &&
      other.startDate == startDate &&
      other.lastGeneratedDate == lastGeneratedDate &&
      other.isActive == isActive;

  @override
  int get hashCode => Object.hash(id, label, kind, amount, categoryId, goalId,
      dayOfMonth, startDate, lastGeneratedDate, isActive);
}
```

```dart
// file: lib/app/data/models/quick_template.dart
import 'enums.dart';

/// A favorite ("قهوة · 1.500") that adds a transaction with one tap.
class QuickTemplate {
  const QuickTemplate({
    this.id,
    required this.label,
    required this.kind,
    required this.amount,
    required this.categoryId,
    this.sortOrder = 0,
  });

  factory QuickTemplate.fromMap(Map<String, Object?> map) => QuickTemplate(
        id: map['id'] as int?,
        label: map['label'] as String,
        kind: TransactionKind.values.byName(map['kind'] as String),
        amount: map['amount'] as int,
        categoryId: map['category_id'] as int,
        sortOrder: map['sort_order'] as int,
      );

  final int? id;
  final String label;
  final TransactionKind kind;
  final int amount;
  final int categoryId;
  final int sortOrder;

  QuickTemplate withId(int id) => QuickTemplate(
        id: id,
        label: label,
        kind: kind,
        amount: amount,
        categoryId: categoryId,
        sortOrder: sortOrder,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'amount': amount,
        'category_id': categoryId,
        'sort_order': sortOrder,
      };

  @override
  bool operator ==(Object other) =>
      other is QuickTemplate &&
      other.id == id &&
      other.label == label &&
      other.kind == kind &&
      other.amount == amount &&
      other.categoryId == categoryId &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(id, label, kind, amount, categoryId, sortOrder);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/models test/data/models && git commit -m "feat: add budget, recurring rule and favorite models"
```

---

### Task 3: Budget status and recurring date logic

**Files:**
- Create: `lib/app/core/logic/budget_status.dart`, `lib/app/core/logic/recurring_generator.dart`
- Test: `test/core/logic/budget_status_test.dart`, `test/core/logic/recurring_generator_test.dart`

**Interfaces:**
- Consumes: `Period`, `Budget`, `TransactionCategory`, `TransactionRecord`, `RecurringRule`, `DateKeys`.
- Produces:
  - `enum BudgetLevel { normal, warning, over }`
  - `BudgetStatus({required TransactionCategory category, required int limit, required int spent})` with `level`, `progress` (0–1), `percent` (int), `remaining`, `reachedThresholds` (`List<int>` ⊆ [80, 100])
  - `BudgetCalculator.calculate({required Period period, required Iterable<Budget> budgets, required Map<int, TransactionCategory> categoriesById, required Iterable<TransactionRecord> transactions}) → List<BudgetStatus>` sorted most-used first; `BudgetCalculator.mostUrgent(List<BudgetStatus>) → BudgetStatus?`
  - `RecurringGenerator.dueDates(RecurringRule, DateTime today) → List<DateTime>`, `RecurringGenerator.nextDueDate(RecurringRule, DateTime today) → DateTime`

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/core/logic/budget_status_test.dart
import 'package:calculator/app/core/logic/budget_status.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:calculator/app/data/models/budget.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

const food = TransactionCategory(
    id: 1, name: 'أكل', iconKey: 'food', colorValue: 0, kind: TransactionKind.expense);
const transport = TransactionCategory(
    id: 2, name: 'مواصلات', iconKey: 'transport', colorValue: 0, kind: TransactionKind.expense);

BudgetStatus status(int spent, {int limit = 100000}) =>
    BudgetStatus(category: food, limit: limit, spent: spent);

void main() {
  group('BudgetStatus', () {
    test('levels switch at 80 % and 100 %', () {
      expect(status(79999).level, BudgetLevel.normal);
      expect(status(80000).level, BudgetLevel.warning);
      expect(status(99999).level, BudgetLevel.warning);
      expect(status(100000).level, BudgetLevel.over);
      expect(status(150000).level, BudgetLevel.over);
    });

    test('reached thresholds', () {
      expect(status(50000).reachedThresholds, isEmpty);
      expect(status(88000).reachedThresholds, [80]);
      expect(status(120000).reachedThresholds, [80, 100]);
    });

    test('progress is capped at 1 while percent and remaining are not', () {
      final over = status(150000);
      expect(over.progress, 1.0);
      expect(over.percent, 150);
      expect(over.remaining, -50000);
      expect(status(88000).progress, closeTo(0.88, 0.0001));
    });
  });

  group('BudgetCalculator', () {
    final october = Period.containing(DateTime(2026, 10, 10), startDay: 1);
    const byId = {1: food, 2: transport};

    test('sums this period expenses per budgeted category, most used first', () {
      final statuses = BudgetCalculator.calculate(
        period: october,
        budgets: const [
          Budget(categoryId: 1, limitAmount: 200000),
          Budget(categoryId: 2, limitAmount: 80000),
        ],
        categoriesById: byId,
        transactions: [
          expense(176000, DateTime(2026, 10, 3)),
          expense(42000, DateTime(2026, 10, 4), categoryId: 2),
          expense(99000, DateTime(2026, 9, 30)),
          income(500000, DateTime(2026, 10, 1), categoryId: 1),
        ],
      );
      expect(statuses.map((s) => s.category.name), ['أكل', 'مواصلات']);
      expect(statuses.first.spent, 176000);
      expect(statuses.last.spent, 42000);
    });

    test('a budget without spending shows zero', () {
      final statuses = BudgetCalculator.calculate(
        period: october,
        budgets: const [Budget(categoryId: 2, limitAmount: 80000)],
        categoriesById: byId,
        transactions: const [],
      );
      expect(statuses.single.spent, 0);
      expect(statuses.single.level, BudgetLevel.normal);
    });

    test('mostUrgent picks the highest status at warning or over', () {
      expect(BudgetCalculator.mostUrgent([status(10000)]), isNull);
      final urgent = BudgetCalculator.mostUrgent([status(120000), status(85000)]);
      expect(urgent!.spent, 120000);
    });
  });
}
```

```dart
// file: test/core/logic/recurring_generator_test.dart
import 'package:calculator/app/core/logic/recurring_generator.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringRule rule({
  int day = 1,
  required DateTime start,
  DateTime? last,
  bool active = true,
}) =>
    RecurringRule(
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: day,
      startDate: start,
      lastGeneratedDate: last,
      isActive: active,
    );

void main() {
  group('dueDates', () {
    test('every missed month since the start date, up to today', () {
      expect(
        RecurringGenerator.dueDates(rule(start: DateTime(2026, 8, 15)), DateTime(2026, 10, 4)),
        [DateTime(2026, 9, 1), DateTime(2026, 10, 1)],
      );
    });

    test('the start date itself counts when it is the due day', () {
      expect(
        RecurringGenerator.dueDates(rule(start: DateTime(2026, 10, 1)), DateTime(2026, 10, 1, 23)),
        [DateTime(2026, 10, 1)],
      );
    });

    test('nothing before the start date', () {
      expect(RecurringGenerator.dueDates(rule(start: DateTime(2026, 10, 5)), DateTime(2026, 10, 4)),
          isEmpty);
    });

    test('nothing again after the last generated date', () {
      final generated = rule(start: DateTime(2026, 1, 1), last: DateTime(2026, 10, 1));
      expect(RecurringGenerator.dueDates(generated, DateTime(2026, 10, 4)), isEmpty);
      expect(RecurringGenerator.dueDates(generated, DateTime(2026, 11, 1)), [DateTime(2026, 11, 1)]);
    });

    test('catches up across a year boundary', () {
      expect(
        RecurringGenerator.dueDates(
            rule(day: 28, start: DateTime(2026, 1, 1), last: DateTime(2026, 11, 28)),
            DateTime(2027, 2, 28)),
        [DateTime(2026, 12, 28), DateTime(2027, 1, 28), DateTime(2027, 2, 28)],
      );
    });

    test('a paused rule creates nothing', () {
      expect(
        RecurringGenerator.dueDates(rule(start: DateTime(2026, 1, 1), active: false), DateTime(2026, 10, 4)),
        isEmpty,
      );
    });
  });

  group('nextDueDate', () {
    test('the next due day after today', () {
      expect(
        RecurringGenerator.nextDueDate(
            rule(day: 25, start: DateTime(2026, 1, 1), last: DateTime(2026, 9, 25)), DateTime(2026, 10, 4)),
        DateTime(2026, 10, 25),
      );
    });

    test('moves to next month once today was generated', () {
      expect(
        RecurringGenerator.nextDueDate(
            rule(day: 25, start: DateTime(2026, 1, 1), last: DateTime(2026, 10, 25)), DateTime(2026, 10, 25)),
        DateTime(2026, 11, 25),
      );
    });

    test('waits for a future start date', () {
      expect(
        RecurringGenerator.nextDueDate(rule(day: 5, start: DateTime(2026, 12, 10)), DateTime(2026, 10, 4)),
        DateTime(2027, 1, 5),
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/logic/budget_status_test.dart test/core/logic/recurring_generator_test.dart`
Expected: FAIL — files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/core/logic/budget_status.dart
import '../../data/models/budget.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction_category.dart';
import '../../data/models/transaction_record.dart';
import 'period.dart';

enum BudgetLevel { normal, warning, over }

/// How much of one category's monthly budget is used (spec §6.6).
class BudgetStatus {
  const BudgetStatus({
    required this.category,
    required this.limit,
    required this.spent,
  });

  static const warningPercent = 80;

  final TransactionCategory category;
  final int limit;
  final int spent;

  BudgetLevel get level {
    if (spent >= limit) return BudgetLevel.over;
    if (spent * 100 >= limit * warningPercent) return BudgetLevel.warning;
    return BudgetLevel.normal;
  }

  /// 0.0–1.0, for progress bars.
  double get progress => limit <= 0 ? 0 : (spent / limit).clamp(0.0, 1.0);

  int get percent => limit <= 0 ? 0 : spent * 100 ~/ limit;

  /// Negative when over budget.
  int get remaining => limit - spent;

  /// The alert thresholds (80 and/or 100) this status has reached.
  List<int> get reachedThresholds => [
        if (level != BudgetLevel.normal) warningPercent,
        if (level == BudgetLevel.over) 100,
      ];
}

abstract final class BudgetCalculator {
  /// One status per budget whose category exists, most used (by ratio) first.
  static List<BudgetStatus> calculate({
    required Period period,
    required Iterable<Budget> budgets,
    required Map<int, TransactionCategory> categoriesById,
    required Iterable<TransactionRecord> transactions,
  }) {
    final spent = <int, int>{};
    for (final t in transactions) {
      if (t.kind != TransactionKind.expense || !period.contains(t.date)) continue;
      spent[t.categoryId] = (spent[t.categoryId] ?? 0) + t.amount;
    }
    final statuses = [
      for (final budget in budgets)
        if (categoriesById[budget.categoryId] case final category?)
          BudgetStatus(
            category: category,
            limit: budget.limitAmount,
            spent: spent[budget.categoryId] ?? 0,
          ),
    ];
    statuses.sort((a, b) => (b.spent * a.limit).compareTo(a.spent * b.limit));
    return statuses;
  }

  /// The most used status that is at warning or over, if any.
  static BudgetStatus? mostUrgent(List<BudgetStatus> statuses) {
    BudgetStatus? urgent;
    for (final status in statuses) {
      if (status.level == BudgetLevel.normal) continue;
      if (urgent == null || status.spent * urgent.limit > urgent.spent * status.limit) {
        urgent = status;
      }
    }
    return urgent;
  }
}
```

```dart
// file: lib/app/core/logic/recurring_generator.dart
import '../../data/models/recurring_rule.dart';
import '../utils/date_utils.dart';

/// When recurring rules are due (spec §6.5). There is no background work: the
/// app asks on start and on resume which entries are due and creates them.
abstract final class RecurringGenerator {
  /// The rule's due dates that have not been created yet, up to and including
  /// [today]. Empty for a paused rule.
  static List<DateTime> dueDates(RecurringRule rule, DateTime today) {
    if (!rule.isActive) return const [];
    final end = DateKeys.dateOnly(today);
    final dates = <DateTime>[];
    var due = _onOrAfter(_firstCandidate(rule), rule.dayOfMonth);
    while (!due.isAfter(end)) {
      dates.add(due);
      due = DateTime(due.year, due.month + 1, rule.dayOfMonth);
    }
    return dates;
  }

  /// The next date the rule will create an entry, counting from [today].
  static DateTime nextDueDate(RecurringRule rule, DateTime today) {
    final candidate = _firstCandidate(rule);
    final now = DateKeys.dateOnly(today);
    return _onOrAfter(candidate.isAfter(now) ? candidate : now, rule.dayOfMonth);
  }

  static DateTime _firstCandidate(RecurringRule rule) {
    final last = rule.lastGeneratedDate;
    final start = DateKeys.dateOnly(rule.startDate);
    if (last == null) return start;
    final afterLast = DateTime(last.year, last.month, last.day + 1);
    return afterLast.isAfter(start) ? afterLast : start;
  }

  static DateTime _onOrAfter(DateTime from, int day) {
    final sameMonth = DateTime(from.year, from.month, day);
    return sameMonth.isBefore(from)
        ? DateTime(from.year, from.month + 1, day)
        : sameMonth;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/core/logic`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/core/logic test/core/logic && git commit -m "feat: add budget status and recurring due-date logic"
```

---

### Task 4: Budget, recurring and favorite repositories

**Files:**
- Create: `lib/app/data/repositories/budget_repository.dart`, `recurring_repository.dart`, `template_repository.dart`
- Test: `test/data/repositories/budget_repository_test.dart`, `recurring_repository_test.dart`, `template_repository_test.dart`

**Interfaces:**
- Consumes: `DatabaseService`, models (Task 2), `RecurringGenerator` (Task 3), `DateKeys`.
- Produces:
  - `BudgetRepository(DatabaseService)`: `getAll()`, `setLimit(int categoryId, int limitAmount)`, `remove(int categoryId)` (both notify), `markAlertSent(int categoryId, String periodKey, int threshold) → Future<bool>` (true only the first time; does not notify)
  - `RecurringRepository(DatabaseService)`: `getAll()` (active first, then by day), `add(RecurringRule) → Future<RecurringRule>`, `update`, `delete(int id)`, `setActive(int id, bool)`, `applyDue(DateTime today) → Future<int>` (count created; notifies only when > 0)
  - `TemplateRepository(DatabaseService)`: `getAll()`, `add(QuickTemplate) → Future<QuickTemplate>`, `delete(int id)`

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/data/repositories/budget_repository_test.dart
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  late DatabaseService database;
  late BudgetRepository repo;

  setUp(() async {
    database = await openTestDatabase();
    repo = BudgetRepository(database);
  });

  test('setLimit creates, then replaces, one budget per category', () async {
    await repo.setLimit(1, 200000);
    await repo.setLimit(1, 150000);
    final all = await repo.getAll();
    expect(all.single.categoryId, 1);
    expect(all.single.limitAmount, 150000);
  });

  test('setLimit and remove announce the change', () async {
    final before = database.revision.value;
    await repo.setLimit(2, 80000);
    await repo.remove(2);
    expect(database.revision.value, before + 2);
    expect(await repo.getAll(), isEmpty);
  });

  test('an alert is marked as sent only once per category, period and threshold', () async {
    expect(await repo.markAlertSent(1, '2026-10', 80), isTrue);
    expect(await repo.markAlertSent(1, '2026-10', 80), isFalse);
    expect(await repo.markAlertSent(1, '2026-10', 100), isTrue);
    expect(await repo.markAlertSent(1, '2026-11', 80), isTrue);
    expect(await repo.markAlertSent(2, '2026-10', 80), isTrue);
  });
}
```

```dart
// file: test/data/repositories/recurring_repository_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

RecurringRule rent({DateTime? start, bool active = true}) => RecurringRule(
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: 1,
      startDate: start ?? DateTime(2026, 8, 15),
      isActive: active,
    );

void main() {
  late DatabaseService database;
  late RecurringRepository repo;
  late TransactionRepository transactions;

  setUp(() async {
    database = await openTestDatabase();
    repo = RecurringRepository(database);
    transactions = TransactionRepository(database);
  });

  test('add, list (active first) and update', () async {
    final paused = await repo.add(rent(active: false).copyWith(label: 'نادي'));
    final active = await repo.add(rent());
    expect((await repo.getAll()).map((r) => r.id), [active.id, paused.id]);
    await repo.update(active.copyWith(amount: 360000));
    expect((await repo.getAll()).first.amount, 360000);
  });

  test('applyDue creates each missed month once, as auto entries', () async {
    final rule = await repo.add(rent());
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 2);
    final created = await transactions.getAll();
    expect(created.map((t) => t.date), [DateTime(2026, 10, 1), DateTime(2026, 9, 1)]);
    expect(created.every((t) => t.isAuto && t.note == 'إيجار' && t.amount == 350000), isTrue);
    expect(created.first.recurringRuleId, rule.id);
    expect((await repo.getAll()).single.lastGeneratedDate, DateTime(2026, 10, 1));
  });

  test('running applyDue again creates nothing and does not announce', () async {
    await repo.add(rent());
    await repo.applyDue(DateTime(2026, 10, 4));
    final before = database.revision.value;
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 0);
    expect(await transactions.getAll(), hasLength(2));
    expect(database.revision.value, before);
  });

  test('a paused rule creates nothing until it is resumed', () async {
    final rule = await repo.add(rent(active: false));
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 0);
    await repo.setActive(rule.id!, true);
    expect(await repo.applyDue(DateTime(2026, 10, 4)), 2);
  });

  test('a saving rule creates savings movements', () async {
    await repo.add(RecurringRule(
      label: 'لابتوب',
      kind: RecurringKind.saving,
      amount: 50000,
      goalId: 1,
      dayOfMonth: 1,
      startDate: DateTime(2026, 10, 1),
    ));
    await repo.applyDue(DateTime(2026, 10, 4));
    final movements = await SavingsRepository(database).getAllMovements();
    expect(movements.single.amount, 50000);
    expect(movements.single.source, SavingsSource.recurring);
    expect(await transactions.getAll(), isEmpty);
  });

  test('deleting a rule keeps the entries it created', () async {
    final rule = await repo.add(rent());
    await repo.applyDue(DateTime(2026, 10, 4));
    await repo.delete(rule.id!);
    expect(await repo.getAll(), isEmpty);
    final kept = await transactions.getAll();
    expect(kept, hasLength(2));
    expect(kept.every((t) => !t.isAuto), isTrue);
  });
}
```

```dart
// file: test/data/repositories/template_repository_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/quick_template.dart';
import 'package:calculator/app/data/repositories/template_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  test('add appends in order, delete removes', () async {
    final database = await openTestDatabase();
    final repo = TemplateRepository(database);
    final coffee = await repo.add(const QuickTemplate(
        label: 'قهوة', kind: TransactionKind.expense, amount: 1500, categoryId: 1));
    final taxi = await repo.add(const QuickTemplate(
        label: 'تكسي', kind: TransactionKind.expense, amount: 3000, categoryId: 2));
    expect((await repo.getAll()).map((t) => t.label), ['قهوة', 'تكسي']);
    expect(taxi.sortOrder, greaterThan(coffee.sortOrder));
    await repo.delete(coffee.id!);
    expect((await repo.getAll()).single.label, 'تكسي');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/repositories`
Expected: FAIL — repository files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/data/repositories/budget_repository.dart
import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/budget.dart';

class BudgetRepository {
  BudgetRepository(this._database);

  final DatabaseService _database;

  Future<List<Budget>> getAll() async {
    final rows = await _database.db.query('budgets', orderBy: 'id');
    return rows.map(Budget.fromMap).toList();
  }

  /// Creates or replaces the monthly limit of [categoryId].
  Future<void> setLimit(int categoryId, int limitAmount) async {
    await _database.db.insert(
      'budgets',
      {'category_id': categoryId, 'limit_amount': limitAmount},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _database.notifyChanged();
  }

  Future<void> remove(int categoryId) async {
    await _database.db
        .delete('budgets', where: 'category_id = ?', whereArgs: [categoryId]);
    _database.notifyChanged();
  }

  /// Records that the [threshold] alert of [categoryId] went out in
  /// [periodKey]. Returns false when it had already been sent. Bookkeeping
  /// only, so it does not announce a change.
  Future<bool> markAlertSent(int categoryId, String periodKey, int threshold) {
    return _database.db.transaction((txn) async {
      final args = [categoryId, periodKey, threshold];
      final existing = await txn.query(
        'budget_alerts_sent',
        where: 'category_id = ? AND period_key = ? AND threshold = ?',
        whereArgs: args,
      );
      if (existing.isNotEmpty) return false;
      await txn.insert('budget_alerts_sent', {
        'category_id': categoryId,
        'period_key': periodKey,
        'threshold': threshold,
      });
      return true;
    });
  }
}
```

```dart
// file: lib/app/data/repositories/recurring_repository.dart
import 'package:sqflite/sqflite.dart';

import '../../core/logic/recurring_generator.dart';
import '../../core/utils/date_utils.dart';
import '../../services/database_service.dart';
import '../models/enums.dart';
import '../models/recurring_rule.dart';

class RecurringRepository {
  RecurringRepository(this._database);

  final DatabaseService _database;

  static const _table = 'recurring_rules';

  Future<List<RecurringRule>> getAll() async {
    final rows = await _database.db
        .query(_table, orderBy: 'is_active DESC, day_of_month, id');
    return rows.map(RecurringRule.fromMap).toList();
  }

  Future<RecurringRule> add(RecurringRule rule) async {
    final id = await _database.db.insert(_table, rule.toMap()..remove('id'));
    _database.notifyChanged();
    return rule.withId(id);
  }

  Future<void> update(RecurringRule rule) async {
    await _database.db
        .update(_table, rule.toMap(), where: 'id = ?', whereArgs: [rule.id]);
    _database.notifyChanged();
  }

  /// Deletes the rule. Entries it already created stay (they lose their
  /// "auto" link through ON DELETE SET NULL).
  Future<void> delete(int id) async {
    await _database.db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  Future<void> setActive(int id, bool isActive) async {
    await _database.db.update(_table, {'is_active': isActive ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Creates every due entry up to [today] that was not created yet, in one
  /// database transaction. Returns how many entries were created.
  Future<int> applyDue(DateTime today) async {
    final rules = await getAll();
    var created = 0;
    await _database.db.transaction((txn) async {
      for (final rule in rules) {
        final dates = RecurringGenerator.dueDates(rule, today);
        if (dates.isEmpty) continue;
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final due in dates) {
          final dueKey = DateKeys.fromDate(due);
          if (rule.kind == RecurringKind.saving) {
            await txn.insert(
              'savings_movements',
              {
                'goal_id': rule.goalId,
                'amount': rule.amount,
                'date': dueKey,
                'source': SavingsSource.recurring.name,
                'recurring_rule_id': rule.id,
                'recurring_due_date': dueKey,
                'note': rule.label,
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          } else {
            await txn.insert(
              'transactions',
              {
                'kind': rule.kind.name,
                'amount': rule.amount,
                'category_id': rule.categoryId,
                'date': dueKey,
                'note': rule.label,
                'recurring_rule_id': rule.id,
                'recurring_due_date': dueKey,
                'created_at': now,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
          created++;
        }
        await txn.update(
          _table,
          {'last_generated_date': DateKeys.fromDate(dates.last)},
          where: 'id = ?',
          whereArgs: [rule.id],
        );
      }
    });
    if (created > 0) _database.notifyChanged();
    return created;
  }
}
```

```dart
// file: lib/app/data/repositories/template_repository.dart
import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/quick_template.dart';

class TemplateRepository {
  TemplateRepository(this._database);

  final DatabaseService _database;

  static const _table = 'quick_templates';

  Future<List<QuickTemplate>> getAll() async {
    final rows = await _database.db.query(_table, orderBy: 'sort_order, id');
    return rows.map(QuickTemplate.fromMap).toList();
  }

  /// Adds [template] after the existing favorites.
  Future<QuickTemplate> add(QuickTemplate template) async {
    final next = Sqflite.firstIntValue(await _database.db
            .rawQuery('SELECT COALESCE(MAX(sort_order), -1) + 1 FROM $_table')) ??
        0;
    final row = template.toMap()
      ..remove('id')
      ..['sort_order'] = next;
    final id = await _database.db.insert(_table, row);
    _database.notifyChanged();
    return QuickTemplate.fromMap({...row, 'id': id});
  }

  Future<void> delete(int id) async {
    await _database.db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/app/data/repositories test/data/repositories && git commit -m "feat: add budget, recurring and favorite repositories"
```

---

### Task 5: Messages, notifications, budget alerts and startup services

**Files:**
- Create: `lib/app/services/message_service.dart`, `lib/app/data/providers/notification_provider.dart`, `lib/app/services/notification_service.dart`, `lib/app/services/budget_alert_service.dart`, `lib/app/services/startup_service.dart`, `test/helpers/fake_notifications.dart`
- Modify (full replacement): `lib/app/bindings/initial_binding.dart`, `test/helpers/test_services.dart`
- Test: `test/services/notification_service_test.dart`, `test/services/budget_alert_service_test.dart`, `test/services/startup_service_test.dart`

**Interfaces:**
- Consumes: repositories (Tasks 4 and Phase 1), `SettingsService`, `DatabaseService`, `BudgetCalculator`.
- Produces:
  - `MessageService`: `lastMessage` (`RxnString`), `showError(String)`
  - `abstract class NotificationProvider { init(); requestPermission() → Future<bool>; scheduleDaily({required int id, required int hour, required int minute, required String title, required String body}); show({required int id, required String title, required String body}); cancel(int id); }`, `LocalNotificationProvider`
  - `NotificationService(NotificationProvider, SettingsService)`: `init()`, `permissionGranted` (`RxBool`), `syncReminder()`, `showBudgetAlert(BudgetStatus, int threshold)`, `reminderId = 1`, reminder body `'سجّلت مصاريف اليوم؟'`
  - `BudgetAlertService({required DatabaseService database, required BudgetRepository budgets, required TransactionRepository transactions, required CategoryRepository categories, required SettingsService settings, required NotificationService notifications, DateTime Function()? clock})`: `check()`
  - `StartupService({required RecurringRepository recurring, required DatabaseService database, DateTime Function()? clock})`: `init()`, `refresh()`
  - `InitialBinding.initServices({DatabaseFactory? factory, String? path, NotificationProvider? notifications})` — registers all of the above plus `BudgetRepository`, `RecurringRepository`, `TemplateRepository`
  - test helper `setUpTestServices() → Future<FakeNotificationProvider>`

- [ ] **Step 1: Write the fake, the new test helper and the failing tests**

```dart
// file: test/helpers/fake_notifications.dart
import 'package:calculator/app/data/providers/notification_provider.dart';

/// Records what the app asked the notification system to do.
class FakeNotificationProvider implements NotificationProvider {
  bool granted = true;
  final scheduled = <int, ({int hour, int minute, String body})>{};
  final shown = <({int id, String title, String body})>[];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async =>
      scheduled[id] = (hour: hour, minute: minute, body: body);

  @override
  Future<void> show({required int id, required String title, required String body}) async =>
      shown.add((id: id, title: title, body: body));

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
}
```

```dart
// file: test/helpers/test_services.dart
import 'package:calculator/app/bindings/initial_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_notifications.dart';

/// Registers every app service and repository against a fresh in-memory
/// database and a fake notification system, which it returns.
Future<FakeNotificationProvider> setUpTestServices() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  Get.reset();
  sqfliteFfiInit();
  final notifications = FakeNotificationProvider();
  await InitialBinding.initServices(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    notifications: notifications,
  );
  return notifications;
}

/// Lets `ever` workers and the reloads they start finish.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
```

```dart
// file: test/services/notification_service_test.dart
import 'package:calculator/app/services/notification_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/test_services.dart';

void main() {
  test('schedules the daily reminder at 21:00 by default', () async {
    final fake = await setUpTestServices();
    final reminder = fake.scheduled[NotificationService.reminderId]!;
    expect((reminder.hour, reminder.minute), (21, 0));
    expect(reminder.body, 'سجّلت مصاريف اليوم؟');
    expect(Get.find<NotificationService>().permissionGranted.value, isTrue);
  });

  test('follows the reminder settings', () async {
    final fake = await setUpTestServices();
    final settings = Get.find<SettingsService>();
    await settings.update(settings.settings.value.copyWith(reminderMinutes: 8 * 60 + 30));
    await settle();
    expect(fake.scheduled[NotificationService.reminderId]!.hour, 8);
    expect(fake.scheduled[NotificationService.reminderId]!.minute, 30);
    await settings.update(settings.settings.value.copyWith(reminderEnabled: false));
    await settle();
    expect(fake.scheduled, isEmpty);
  });

  test('schedules nothing when notifications are refused', () async {
    final fake = await setUpTestServices();
    fake.granted = false;
    final service = Get.find<NotificationService>();
    await service.init();
    fake.scheduled.clear();
    await service.syncReminder();
    expect(service.permissionGranted.value, isFalse);
    expect(fake.scheduled, isEmpty);
  });
}
```

```dart
// file: test/services/budget_alert_service_test.dart
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_notifications.dart';
import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  late FakeNotificationProvider fake;
  late TransactionRepository transactions;
  final today = DateTime.now();

  setUp(() async {
    fake = await setUpTestServices();
    transactions = Get.find<TransactionRepository>();
    await Get.find<BudgetRepository>().setLimit(foodCategoryId, 10000);
    await settle();
  });

  test('warns once at 80 % and once more at 100 %', () async {
    await transactions.add(expense(8000, today));
    await settle();
    expect(fake.shown.map((n) => n.title), ['قرّبت تخلص ميزانية أكل']);

    await transactions.add(expense(1000, today));
    await settle();
    expect(fake.shown, hasLength(1));

    await transactions.add(expense(2000, today));
    await settle();
    expect(fake.shown.map((n) => n.title).last, 'تجاوزت ميزانية أكل');
    expect(fake.shown, hasLength(2));
  });

  test('jumping straight past the limit sends a single alert', () async {
    await transactions.add(expense(15000, today));
    await settle();
    expect(fake.shown.single.title, 'تجاوزت ميزانية أكل');
  });

  test('categories without a budget never alert', () async {
    await transactions.add(expense(999000, today, categoryId: 2));
    await settle();
    expect(fake.shown, isEmpty);
  });
}
```

```dart
// file: test/services/startup_service_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/startup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  test('refresh creates due recurring entries', () async {
    final now = DateTime.now();
    await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'إيجار',
      kind: RecurringKind.expense,
      amount: 350000,
      categoryId: 4,
      dayOfMonth: 1,
      startDate: DateTime(now.year, now.month - 1, 1),
    ));
    await Get.find<StartupService>().refresh();
    final created = await Get.find<TransactionRepository>().getAll();
    expect(created, hasLength(2));
    expect(created.every((t) => t.isAuto), isTrue);
  });

  test('refresh tells every screen to reload, even with nothing due', () async {
    final database = Get.find<DatabaseService>();
    final before = database.revision.value;
    await Get.find<StartupService>().refresh();
    expect(database.revision.value, greaterThan(before));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services`
Expected: FAIL — `notification_provider.dart` and the new services not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/services/message_service.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shows short error messages from anywhere (spec §11).
class MessageService extends GetxService {
  /// The last message, kept so tests can check it.
  final lastMessage = RxnString();

  void showError(String message) {
    lastMessage.value = message;
    if (Get.overlayContext == null) return;
    Get.snackbar(
      'صار خطأ',
      message,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
    );
  }
}
```

```dart
// file: lib/app/data/providers/notification_provider.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The device's local notifications. An interface so tests can use a fake.
abstract class NotificationProvider {
  Future<void> init();

  /// Asks the user (once; later calls return the current answer).
  Future<bool> requestPermission();

  /// Repeats every day at [hour]:[minute] local time.
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  });

  Future<void> show({required int id, required String title, required String body});

  Future<void> cancel(int id);
}

/// [NotificationProvider] backed by flutter_local_notifications. Everything
/// is scheduled on the device; nothing uses the network.
class LocalNotificationProvider implements NotificationProvider {
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_reminder',
      'التذكير اليومي',
      channelDescription: 'تذكير يومي لتسجيل المصاريف',
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _alertDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'budget_alerts',
      'تنبيهات الميزانية',
      channelDescription: 'لما تقرّب أو تتجاوز ميزانية تصنيف',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> init() async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Unknown zone name: keep the default (UTC) rather than fail start-up.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: next,
      notificationDetails: _reminderDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> show({required int id, required String title, required String body}) =>
      _plugin.show(id: id, title: title, body: body, notificationDetails: _alertDetails);

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
```

```dart
// file: lib/app/services/notification_service.dart
import 'package:get/get.dart';

import '../core/logic/budget_status.dart';
import '../data/providers/notification_provider.dart';
import 'settings_service.dart';

/// The daily reminder (spec §6.7) and budget alerts (§6.6).
class NotificationService extends GetxService {
  NotificationService(this._provider, this._settings);

  static const reminderId = 1;

  final NotificationProvider _provider;
  final SettingsService _settings;

  /// False when the user refused notifications; Settings shows a hint.
  final permissionGranted = false.obs;

  Worker? _syncOnChange;

  Future<NotificationService> init() async {
    try {
      await _provider.init();
      permissionGranted.value = await _provider.requestPermission();
    } catch (_) {
      permissionGranted.value = false;
    }
    await syncReminder();
    _syncOnChange ??= ever(_settings.settings, (_) => syncReminder());
    return this;
  }

  /// Schedules or cancels the reminder to match the current settings.
  Future<void> syncReminder() async {
    final settings = _settings.settings.value;
    try {
      if (!settings.reminderEnabled || !permissionGranted.value) {
        await _provider.cancel(reminderId);
        return;
      }
      await _provider.scheduleDaily(
        id: reminderId,
        hour: settings.reminderMinutes ~/ 60,
        minute: settings.reminderMinutes % 60,
        title: 'مصاريفي',
        body: 'سجّلت مصاريف اليوم؟',
      );
    } catch (_) {
      // A notification failure must never break the app.
    }
  }

  Future<void> showBudgetAlert(BudgetStatus status, int threshold) async {
    if (!permissionGranted.value) return;
    final name = status.category.name;
    final over = threshold >= 100;
    try {
      await _provider.show(
        id: 1000 + status.category.id! * 10 + (over ? 1 : 0),
        title: over ? 'تجاوزت ميزانية $name' : 'قرّبت تخلص ميزانية $name',
        body: 'صرفت ${status.percent}% من ميزانية هالشهر.',
      );
    } catch (_) {
      // Ignore: the in-app banner still shows the warning.
    }
  }

  @override
  void onClose() {
    _syncOnChange?.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/services/budget_alert_service.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../core/logic/budget_status.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/transaction_repository.dart';
import 'database_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// Sends a notification the first time a category reaches 80 % or 100 % of
/// its budget in a period.
class BudgetAlertService extends GetxService {
  BudgetAlertService({
    required this.database,
    required this.budgets,
    required this.transactions,
    required this.categories,
    required this.settings,
    required this.notifications,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DatabaseService database;
  final BudgetRepository budgets;
  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final NotificationService notifications;
  final DateTime Function() _clock;

  late final Worker _checkOnChange;

  @override
  void onInit() {
    super.onInit();
    _checkOnChange = ever(database.revision, (_) => check());
  }

  Future<void> check() async {
    try {
      final period = settings.currentPeriod(_clock());
      final allCategories = await categories.getAll(includeArchived: true);
      final statuses = BudgetCalculator.calculate(
        period: period,
        budgets: await budgets.getAll(),
        categoriesById: {for (final c in allCategories) c.id!: c},
        transactions: await transactions.getBetween(period.start, period.end),
      );
      for (final status in statuses) {
        var newest = 0;
        for (final threshold in status.reachedThresholds) {
          if (await budgets.markAlertSent(status.category.id!, period.key, threshold)) {
            newest = threshold;
          }
        }
        // Only the highest new threshold, so one expense never sends two.
        if (newest > 0) await notifications.showBudgetAlert(status, newest);
      }
    } on DatabaseException {
      // The database is closing or busy; the next change checks again.
    }
  }

  @override
  void onClose() {
    _checkOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/services/startup_service.dart
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/repositories/recurring_repository.dart';
import 'database_service.dart';

/// Work that happens when the app starts or comes back to the foreground
/// (spec §8.4): create due recurring entries, then refresh every screen so a
/// newly started period shows up.
class StartupService extends GetxService with WidgetsBindingObserver {
  StartupService({
    required this.recurring,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final DatabaseService database;
  final DateTime Function() _clock;

  Future<StartupService> init() async {
    await refresh();
    WidgetsBinding.instance.addObserver(this);
    return this;
  }

  Future<void> refresh() async {
    try {
      await recurring.applyDue(_clock());
    } on DatabaseException {
      // Try again on the next resume.
    }
    database.notifyChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
```

```dart
// file: lib/app/bindings/initial_binding.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/providers/notification_provider.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/savings_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/template_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/budget_alert_service.dart';
import '../services/database_service.dart';
import '../services/message_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/startup_service.dart';

/// Registers the app-wide services and repositories before the first screen.
/// Async because the database has to open first, so it runs from `main()`
/// instead of a synchronous `Bindings.dependencies()`.
abstract final class InitialBinding {
  static Future<void> initServices({
    DatabaseFactory? factory,
    String? path,
    NotificationProvider? notifications,
  }) async {
    final database = await Get.putAsync(
        () => DatabaseService(factory: factory, path: path).init(),
        permanent: true);
    final settingsRepository =
        Get.put(SettingsRepository(database), permanent: true);
    final categories = Get.put(CategoryRepository(database), permanent: true);
    final transactions =
        Get.put(TransactionRepository(database), permanent: true);
    Get.put(SavingsRepository(database), permanent: true);
    final budgets = Get.put(BudgetRepository(database), permanent: true);
    final recurring = Get.put(RecurringRepository(database), permanent: true);
    Get.put(TemplateRepository(database), permanent: true);

    final settings = await Get.putAsync(
        () => SettingsService(settingsRepository, database).init(),
        permanent: true);
    Get.put(MessageService(), permanent: true);
    final notificationService = await Get.putAsync(
        () => NotificationService(
                notifications ?? LocalNotificationProvider(), settings)
            .init(),
        permanent: true);
    Get.put(
      BudgetAlertService(
        database: database,
        budgets: budgets,
        transactions: transactions,
        categories: categories,
        settings: settings,
        notifications: notificationService,
      ),
      permanent: true,
    );
    await Get.putAsync(
        () => StartupService(recurring: recurring, database: database).init(),
        permanent: true);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass, then the whole suite**

Run: `flutter test test/services && flutter test`
Expected: PASS (all Phase 1 tests still pass with the new helper).

- [ ] **Step 5: Commit**

```bash
git add lib/app test/helpers test/services && git commit -m "feat: add notification, budget alert, startup and message services"
```

---

### Task 6: Error messages on database failures; shared form widgets

**Files:**
- Move: `lib/app/modules/transaction_form/widgets/kind_toggle.dart` → `lib/app/widgets/kind_toggle.dart`; `lib/app/modules/transaction_form/widgets/category_grid.dart` → `lib/app/widgets/category_grid.dart` (update imports in `transaction_form_view.dart`)
- Modify: `lib/app/modules/transaction_form/controllers/transaction_form_controller.dart`, `lib/app/modules/transactions/controllers/transactions_controller.dart`, `lib/app/modules/settings/controllers/settings_controller.dart`
- Test: `test/modules/error_handling_test.dart`

**Interfaces:**
- Consumes: `MessageService` (Task 5).
- Produces: controllers that return `false` / restore state and call `showError` instead of throwing. Error texts: `'ما قدرنا نحفظ العملية، جرّب مرة ثانية'`, `'ما قدرنا نحذف العملية، جرّب مرة ثانية'`, `'ما قدرنا نحفظ الإعدادات'`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/error_handling_test.dart
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/modules/transaction_form/controllers/transaction_form_controller.dart';
import 'package:calculator/app/modules/transactions/controllers/transactions_controller.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

/// Makes every following database call fail.
Future<void> breakDatabase() => Get.find<DatabaseService>().db.close();

String? lastMessage() => Get.find<MessageService>().lastMessage.value;

void main() {
  setUp(setUpTestServices);

  test('a failed save shows a message and reports false', () async {
    final c = Get.put(TransactionFormController(
        transactions: Get.find(), categories: Get.find(), settings: Get.find()));
    await c.ready;
    c.pressKey('5');
    c.selectCategory(foodCategoryId);
    await breakDatabase();
    expect(await c.save(), isFalse);
    expect(lastMessage(), 'ما قدرنا نحفظ العملية، جرّب مرة ثانية');
    expect(c.isSaving.value, isFalse);
  });

  test('a failed delete in the list brings the row back with a message', () async {
    final saved = await Get.find<TransactionRepository>().add(expense(5000, DateTime.now()));
    final c = Get.put(TransactionsController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
    ));
    await c.load();
    final shown = c.groups.expand((g) => g.transactions).single;
    await breakDatabase();
    await c.delete(shown);
    expect(lastMessage(), 'ما قدرنا نحذف العملية، جرّب مرة ثانية');
    expect(c.groups.expand((g) => g.transactions).map((t) => t.id), [saved.id]);
  });

  test('a failed settings change keeps the old value and shows a message', () async {
    final c = Get.put(SettingsController(settingsService: Get.find()));
    await breakDatabase();
    await c.setStartDay(25);
    expect(Get.find<SettingsService>().settings.value.periodStartDay, 1);
    expect(lastMessage(), 'ما قدرنا نحفظ الإعدادات');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/error_handling_test.dart`
Expected: FAIL — `DatabaseException` escapes / no message.

- [ ] **Step 3: Implement**

Move the two widgets and fix imports:

```bash
git mv lib/app/modules/transaction_form/widgets/kind_toggle.dart lib/app/widgets/kind_toggle.dart
git mv lib/app/modules/transaction_form/widgets/category_grid.dart lib/app/widgets/category_grid.dart
sed -i '' "s#import '../../../data/models/enums.dart';#import '../data/models/enums.dart';#" lib/app/widgets/kind_toggle.dart
sed -i '' "s#import '../../../core/theme/#import '../core/theme/#; s#import '../../../data/models/#import '../data/models/#" lib/app/widgets/category_grid.dart
sed -i '' "s#import '../widgets/category_grid.dart';#import '../../../widgets/category_grid.dart';#; s#import '../widgets/kind_toggle.dart';#import '../../../widgets/kind_toggle.dart';#" lib/app/modules/transaction_form/views/transaction_form_view.dart
```

In `transaction_form_controller.dart` add imports `package:sqflite/sqflite.dart` and `../../../services/message_service.dart`, and replace `save()` and `delete()` with:

```dart
  /// Saves the form. Returns false (and saves nothing) when it is incomplete,
  /// a save is already running, or the database fails (a message is shown).
  Future<bool> save() async {
    if (!canSave) return false;
    isSaving.value = true;
    try {
      return await _save();
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ العملية، جرّب مرة ثانية');
      return false;
    } finally {
      isSaving.value = false;
    }
  }
```

```dart
  /// Deletes the edited record. Returns false when there is nothing to
  /// delete, a save/delete is already running, or the database fails.
  Future<bool> delete() async {
    final id = _editing?.id;
    if (id == null || isSaving.value) return false;
    isSaving.value = true;
    try {
      await transactions.delete(id);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف العملية، جرّب مرة ثانية');
      return false;
    } finally {
      isSaving.value = false;
    }
  }
```

In `transactions_controller.dart` add the same two imports and replace `delete` / `undoDelete` with:

```dart
  /// Removes the row immediately (so a swipe-to-dismiss can finish), then
  /// deletes it from the database. On failure the row comes back.
  Future<void> delete(TransactionRecord record) async {
    final before = _items;
    _items = _items.where((t) => t.id != record.id).toList();
    groups.assignAll(DayGroup.group(_items));
    try {
      await transactions.delete(record.id!);
    } on DatabaseException {
      _items = before;
      groups.assignAll(DayGroup.group(_items));
      Get.find<MessageService>().showError('ما قدرنا نحذف العملية، جرّب مرة ثانية');
    }
  }

  Future<void> undoDelete(TransactionRecord record) async {
    try {
      await transactions.restore(record);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نرجّع العملية');
    }
  }
```

In `settings_controller.dart` add the same two imports and route both setters through one guarded helper:

```dart
  Future<void> setStartDay(int day) =>
      _update(settings.copyWith(periodStartDay: day));

  Future<void> setCurrency(String code) {
    final currency = Currencies.byCode(code);
    return _update(settings.copyWith(
      currencyCode: currency.code,
      currencyDecimals: currency.decimals,
    ));
  }

  Future<void> _update(AppSettings value) async {
    try {
      await settingsService.update(value);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الإعدادات');
    }
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: show a message when saving or deleting fails; share form widgets"
```

---

### Task 7: Budgets screen and the fourth tab

**Files:**
- Modify (full replacement): `lib/app/routes/app_routes.dart`, `lib/app/widgets/app_bottom_nav.dart`, `lib/app/widgets/money_text.dart`
- Modify: `lib/app/routes/app_pages.dart` (add the budgets page)
- Create: `lib/app/modules/budgets/bindings/budgets_binding.dart`, `controllers/budgets_controller.dart`, `views/budgets_view.dart`, `widgets/budget_progress_tile.dart`, `widgets/recurring_summary.dart`
- Test: `test/modules/budgets/budgets_controller_test.dart`

**Interfaces:**
- Consumes: `BudgetRepository`, `CategoryRepository`, `TransactionRepository`, `RecurringRepository`, `SettingsService`, `DatabaseService`, `BudgetCalculator`, `RecurringGenerator`, `MessageService`.
- Produces: `Routes.budgets/recurring/recurringForm/templates`; `MoneyText.label(int, Currency) → String`; `BudgetsController({required BudgetRepository budgets, required CategoryRepository categories, required TransactionRepository transactions, required RecurringRepository recurring, required SettingsService settings, required DatabaseService database, DateTime Function()? clock})` with `statuses`, `unbudgeted`, `rules`, `period`, `currency`, `today`, `daysLeft`, `load()`, `setLimit(int categoryId, String text) → Future<bool>`, `removeLimit(int)`, `nextDue(RecurringRule)`, `openRecurring()`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/budgets/budgets_controller_test.dart
import 'package:calculator/app/core/logic/budget_status.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/budgets/controllers/budgets_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<BudgetsController> open(DateTime now) async {
    final c = Get.put(BudgetsController(
      budgets: Get.find(),
      categories: Get.find(),
      transactions: Get.find(),
      recurring: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => now,
    ));
    await c.load();
    return c;
  }

  test('setting a limit shows its status and removes it from the add list', () async {
    await Get.find<TransactionRepository>().add(expense(176000, DateTime(2026, 10, 3)));
    final c = await open(DateTime(2026, 10, 10));
    expect(c.unbudgeted, hasLength(8));
    expect(await c.setLimit(foodCategoryId, '200'), isTrue);
    await settle();
    final food = c.statuses.single;
    expect(food.limit, 200000);
    expect(food.spent, 176000);
    expect(food.level, BudgetLevel.warning);
    expect(c.unbudgeted.map((x) => x.id), isNot(contains(foodCategoryId)));
  });

  test('an invalid limit is refused', () async {
    final c = await open(DateTime(2026, 10, 10));
    expect(await c.setLimit(foodCategoryId, '0'), isFalse);
    expect(await c.setLimit(foodCategoryId, 'abc'), isFalse);
    expect(c.statuses, isEmpty);
  });

  test('removing a limit', () async {
    final c = await open(DateTime(2026, 10, 10));
    await c.setLimit(foodCategoryId, '50');
    await c.removeLimit(foodCategoryId);
    await settle();
    expect(c.statuses, isEmpty);
  });

  test('lists active recurring rules with their next date and days left', () async {
    await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'نت',
      kind: RecurringKind.expense,
      amount: 25000,
      categoryId: 3,
      dayOfMonth: 15,
      startDate: DateTime(2026, 10, 15),
    ));
    final c = await open(DateTime(2026, 10, 10));
    expect(c.rules.single.label, 'نت');
    expect(c.nextDue(c.rules.single), DateTime(2026, 10, 15));
    expect(c.daysLeft, 22);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/modules/budgets`
Expected: FAIL — controller not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/routes/app_routes.dart
abstract final class Routes {
  static const home = '/home';
  static const transactionForm = '/transaction-form';
  static const transactions = '/transactions';
  static const budgets = '/budgets';
  static const recurring = '/recurring';
  static const recurringForm = '/recurring-form';
  static const templates = '/templates';
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
    (Routes.budgets, Icons.donut_large_outlined, Icons.donut_large, 'الميزانية'),
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

  /// The same text as a plain string, for use inside a sentence.
  static String label(
    int amount,
    Currency currency, {
    bool showPlus = false,
    bool showSymbol = true,
  }) {
    final number =
        Money.format(amount, decimals: currency.decimals, showPlus: showPlus);
    final text = '\u2066$number\u2069';
    return showSymbol ? '$text ${currency.symbol}' : text;
  }

  @override
  Widget build(BuildContext context) => Text(
        label(amount, currency, showPlus: showPlus, showSymbol: showSymbol),
        style: style,
      );
}
```

```dart
// file: lib/app/modules/budgets/controllers/budgets_controller.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/logic/period.dart';
import '../../../core/logic/recurring_generator.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class BudgetsController extends GetxController {
  BudgetsController({
    required this.budgets,
    required this.categories,
    required this.transactions,
    required this.recurring,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BudgetRepository budgets;
  final CategoryRepository categories;
  final TransactionRepository transactions;
  final RecurringRepository recurring;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final statuses = <BudgetStatus>[].obs;

  /// Expense categories that have no budget yet.
  final unbudgeted = <TransactionCategory>[].obs;
  final rules = <RecurringRule>[].obs;
  final period = Rxn<Period>();

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  DateTime get today => _clock();

  /// Days until the period ends, counting today.
  int get daysLeft {
    final p = period.value;
    if (p == null) return 0;
    return p.end.difference(DateKeys.dateOnly(_clock())).inDays;
  }

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final current = settings.currentPeriod(_clock());
    final all = await budgets.getAll();
    final allCategories = await categories.getAll(includeArchived: true);
    final expenseCategories =
        await categories.getAll(kind: TransactionKind.expense);
    final inPeriod = await transactions.getBetween(current.start, current.end);
    final activeRules = (await recurring.getAll()).where((r) => r.isActive);

    final budgeted = {for (final b in all) b.categoryId};
    period.value = current;
    statuses.assignAll(BudgetCalculator.calculate(
      period: current,
      budgets: all,
      categoriesById: {for (final c in allCategories) c.id!: c},
      transactions: inPeriod,
    ));
    unbudgeted.assignAll(
        expenseCategories.where((c) => !budgeted.contains(c.id)));
    rules.assignAll(activeRules);
  }

  /// Saves the limit typed as [text]. Returns false for an invalid amount or
  /// a database failure.
  Future<bool> setLimit(int categoryId, String text) async {
    final limit = Money.parse(text, decimals: currency.decimals);
    if (limit == null) return false;
    try {
      await budgets.setLimit(categoryId, limit);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الميزانية');
      return false;
    }
  }

  Future<void> removeLimit(int categoryId) async {
    try {
      await budgets.remove(categoryId);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف الميزانية');
    }
  }

  DateTime nextDue(RecurringRule rule) =>
      RecurringGenerator.nextDueDate(rule, _clock());

  void openRecurring() => Get.toNamed(Routes.recurring);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/budgets/bindings/budgets_binding.dart
import 'package:get/get.dart';

import '../controllers/budgets_controller.dart';

class BudgetsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => BudgetsController(
          budgets: Get.find(),
          categories: Get.find(),
          transactions: Get.find(),
          recurring: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/budgets/widgets/budget_progress_tile.dart
import 'package:flutter/material.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/category_avatar.dart';
import '../../../widgets/money_text.dart';

/// One category's budget: spent / limit, a colored bar and a hint.
class BudgetProgressTile extends StatelessWidget {
  const BudgetProgressTile({
    super.key,
    required this.status,
    required this.currency,
    this.onTap,
  });

  final BudgetStatus status;
  final Currency currency;
  final VoidCallback? onTap;

  Color get _color => switch (status.level) {
        BudgetLevel.normal => AppColors.primary,
        BudgetLevel.warning => AppColors.warning,
        BudgetLevel.over => AppColors.danger,
      };

  String? get _hint => switch (status.level) {
        BudgetLevel.normal => null,
        BudgetLevel.warning =>
          'قرّبت توصل للحد — باقي ${MoneyText.label(status.remaining, currency)}',
        BudgetLevel.over =>
          'تجاوزت الميزانية بـ ${MoneyText.label(-status.remaining, currency)}',
      };

  @override
  Widget build(BuildContext context) {
    final hint = _hint;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryAvatar(category: status.category, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(status.category.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(
                  '${MoneyText.label(status.spent, currency, showSymbol: false)} / '
                  '${MoneyText.label(status.limit, currency, showSymbol: false)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: status.progress,
                minHeight: 8,
                color: _color,
                backgroundColor: AppColors.divider,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint, style: TextStyle(color: _color, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/budgets/widgets/recurring_summary.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';

/// Active fixed costs with the next date each one is added.
class RecurringSummary extends StatelessWidget {
  const RecurringSummary({
    super.key,
    required this.rules,
    required this.currency,
    required this.nextDue,
    required this.today,
  });

  final List<RecurringRule> rules;
  final Currency currency;
  final DateTime Function(RecurringRule) nextDue;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return const EmptyState(
        icon: Icons.event_repeat_outlined,
        message: 'ما في مصاريف ثابتة. أضف الإيجار أو الاشتراكات لتنحسب لحالها.',
      );
    }
    return Card(
      child: Column(
        children: [
          for (final (index, rule) in rules.indexed) ...[
            if (index > 0) const Divider(indent: 16, endIndent: 16),
            ListTile(
              title: Text(rule.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'كل شهر يوم ${rule.dayOfMonth} · الجاي: '
                '${ArabicDates.relativeDay(nextDue(rule), today: today)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              trailing: MoneyText(rule.amount,
                  currency: currency,
                  showSymbol: false,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/budgets/views/budgets_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/transaction_category.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/category_avatar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/section_header.dart';
import '../controllers/budgets_controller.dart';
import '../widgets/budget_progress_tile.dart';
import '../widgets/recurring_summary.dart';

class BudgetsView extends GetView<BudgetsController> {
  const BudgetsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الميزانية')),
      body: Obx(() {
        final period = controller.period.value;
        if (period == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final statuses = controller.statuses.toList();
        final rules = controller.rules.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text('${period.label} · باقي ${controller.daysLeft} يوم',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            if (statuses.isEmpty)
              const EmptyState(
                icon: Icons.donut_large_outlined,
                message: 'ما حطيت ميزانية لأي تصنيف لسا.',
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final (index, status) in statuses.indexed) ...[
                      if (index > 0) const Divider(indent: 16, endIndent: 16),
                      BudgetProgressTile(
                        status: status,
                        currency: controller.currency,
                        onTap: () => _editLimit(context, status.category, status),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (controller.unbudgeted.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _pickCategory(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة ميزانية'),
              ),
            const SizedBox(height: 24),
            SectionHeader(
              title: 'مصاريف ثابتة — تنحسب تلقائياً',
              actionLabel: 'إدارة',
              onAction: controller.openRecurring,
            ),
            const SizedBox(height: 8),
            RecurringSummary(
              rules: rules,
              currency: controller.currency,
              nextDue: controller.nextDue,
              today: controller.today,
            ),
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.budgets),
    );
  }

  Future<void> _pickCategory(BuildContext context) async {
    final category = await showModalBottomSheet<TransactionCategory>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final category in controller.unbudgeted)
              ListTile(
                leading: CategoryAvatar(category: category, size: 36),
                title: Text(category.name),
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
    if (category != null && context.mounted) {
      await _editLimit(context, category, null);
    }
  }

  Future<void> _editLimit(
    BuildContext context,
    TransactionCategory category,
    BudgetStatus? current,
  ) async {
    final input = TextEditingController(
        text: current == null ? '' : Money.toEditable(current.limit));
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ميزانية ${category.name} الشهرية'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'المبلغ',
            suffixText: controller.currency.symbol,
          ),
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('حذف الميزانية'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('حفظ')),
        ],
      ),
    );
    final text = input.text;
    input.dispose();
    if (action == 'remove') {
      await controller.removeLimit(category.id!);
    } else if (action == 'save') {
      final saved = await controller.setLimit(category.id!, text);
      if (!saved && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اكتب مبلغ أكبر من صفر')));
      }
    }
  }
}
```

Add to `lib/app/routes/app_pages.dart` (imports + entry after the transactions page):

```dart
import '../modules/budgets/bindings/budgets_binding.dart';
import '../modules/budgets/views/budgets_view.dart';
```

```dart
    GetPage(
      name: Routes.budgets,
      page: () => const BudgetsView(),
      binding: BudgetsBinding(),
      transition: Transition.noTransition,
    ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze && flutter test test/modules/budgets test/widgets`
Expected: `No issues found!`, PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add budgets screen with progress, limits and fixed costs summary"
```

---

### Task 8: Recurring rules — list and form

**Files:**
- Create: `lib/app/modules/recurring/bindings/recurring_binding.dart`, `controllers/recurring_controller.dart`, `views/recurring_view.dart`; `lib/app/modules/recurring_form/bindings/recurring_form_binding.dart`, `controllers/recurring_form_controller.dart`, `views/recurring_form_view.dart`
- Modify: `lib/app/routes/app_pages.dart`
- Test: `test/modules/recurring/recurring_controller_test.dart`, `test/modules/recurring_form/recurring_form_controller_test.dart`

**Interfaces:**
- Consumes: `RecurringRepository`, `CategoryRepository`, `SettingsService`, `DatabaseService`, `RecurringGenerator`, shared `KindToggle`, `CategoryGrid`, `CategoryAvatar`, `MoneyText`.
- Produces:
  - `RecurringController({required RecurringRepository recurring, required CategoryRepository categories, required SettingsService settings, required DatabaseService database, DateTime Function()? clock})`: `rules`, `categoriesById`, `currency`, `today`, `load()`, `toggleActive(RecurringRule)`, `nextDue(RecurringRule)`, `openAdd()`, `openEdit(RecurringRule)`
  - `RecurringFormController({required RecurringRepository recurring, required CategoryRepository categories, required SettingsService settings, int? editId, DateTime Function()? clock})`: `ready`, `kind` (`Rx<TransactionKind>`), `labelController`, `amountController`, `amountText`, `categoryId`, `dayOfMonth` (`RxInt`), `isEditing`, `isSaving`, `amount`, `canSave`, `visibleCategories`, `currency`, `setKind`, `selectCategory`, `setDay`, `save() → Future<bool>`, `delete() → Future<bool>`

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/modules/recurring_form/recurring_form_controller_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/recurring_form/controllers/recurring_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  final today = DateTime(2026, 10, 4);

  Future<RecurringFormController> open({int? editId}) async {
    final c = Get.put(RecurringFormController(
      recurring: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      editId: editId,
      clock: () => today,
    ));
    await c.ready;
    return c;
  }

  test('defaults to an expense due on today\'s day of the month', () async {
    final c = await open();
    expect(c.kind.value, TransactionKind.expense);
    expect(c.dayOfMonth.value, 4);
    expect(c.canSave, isFalse);
  });

  test('saving a rule due today creates today\'s entry right away', () async {
    final c = await open();
    c.labelController.text = 'نت';
    c.amountController.text = '25';
    c.amountText.value = '25';
    c.selectCategory(3);
    expect(await c.save(), isTrue);
    final rule = (await Get.find<RecurringRepository>().getAll()).single;
    expect(rule.label, 'نت');
    expect(rule.amount, 25000);
    expect(rule.dayOfMonth, 4);
    expect(rule.startDate, today);
    final created = await Get.find<TransactionRepository>().getAll();
    expect(created.single.date, today);
    expect(created.single.isAuto, isTrue);
  });

  test('an empty name falls back to the category name', () async {
    final c = await open();
    c.amountText.value = '350';
    c.selectCategory(4);
    c.setDay(1);
    await c.save();
    expect((await Get.find<RecurringRepository>().getAll()).single.label, 'سكن');
  });

  test('editing keeps the start date and does not duplicate entries', () async {
    final c = await open();
    c.amountText.value = '25';
    c.selectCategory(3);
    await c.save();
    final id = (await Get.find<RecurringRepository>().getAll()).single.id;
    Get.delete<RecurringFormController>();

    final edit = await open(editId: id);
    expect(edit.isEditing.value, isTrue);
    expect(edit.amountText.value, '25');
    edit.amountText.value = '30';
    await edit.save();
    final rules = await Get.find<RecurringRepository>().getAll();
    expect(rules.single.amount, 30000);
    expect(rules.single.lastGeneratedDate, today);
    expect(await Get.find<TransactionRepository>().getAll(), hasLength(1));
  });

  test('switching to income clears the category', () async {
    final c = await open();
    c.selectCategory(3);
    c.setKind(TransactionKind.income);
    expect(c.categoryId.value, isNull);
    expect(c.visibleCategories.map((x) => x.name), ['راتب', 'دخل آخر']);
  });
}
```

```dart
// file: test/modules/recurring/recurring_controller_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/recurring_rule.dart';
import 'package:calculator/app/data/repositories/recurring_repository.dart';
import 'package:calculator/app/modules/recurring/controllers/recurring_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  test('pausing and resuming a rule', () async {
    await Get.find<RecurringRepository>().add(RecurringRule(
      label: 'نادي',
      kind: RecurringKind.expense,
      amount: 30000,
      categoryId: 6,
      dayOfMonth: 15,
      startDate: DateTime(2026, 10, 15),
    ));
    final c = Get.put(RecurringController(
      recurring: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => DateTime(2026, 10, 4),
    ));
    await c.load();
    expect(c.nextDue(c.rules.single), DateTime(2026, 10, 15));
    await c.toggleActive(c.rules.single);
    await settle();
    expect(c.rules.single.isActive, isFalse);
    await c.toggleActive(c.rules.single);
    await settle();
    expect(c.rules.single.isActive, isTrue);
    expect(c.categoriesById[6]!.name, 'ترفيه');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/modules/recurring test/modules/recurring_form`
Expected: FAIL — controllers not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/modules/recurring/controllers/recurring_controller.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/recurring_generator.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class RecurringController extends GetxController {
  RecurringController({
    required this.recurring,
    required this.categories,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final rules = <RecurringRule>[].obs;
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
    final allCategories = await categories.getAll(includeArchived: true);
    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    rules.assignAll(await recurring.getAll());
  }

  Future<void> toggleActive(RecurringRule rule) async {
    try {
      await recurring.setActive(rule.id!, !rule.isActive);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نغيّر حالة القاعدة');
    }
  }

  DateTime nextDue(RecurringRule rule) =>
      RecurringGenerator.nextDueDate(rule, _clock());

  void openAdd() => Get.toNamed(Routes.recurringForm);

  void openEdit(RecurringRule rule) =>
      Get.toNamed(Routes.recurringForm, arguments: rule.id);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/recurring/bindings/recurring_binding.dart
import 'package:get/get.dart';

import '../controllers/recurring_controller.dart';

class RecurringBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => RecurringController(
          recurring: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/recurring/views/recurring_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/enums.dart';
import '../../../widgets/category_avatar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/recurring_controller.dart';

class RecurringView extends GetView<RecurringController> {
  const RecurringView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المصاريف الثابتة')),
      body: Obx(() {
        final rules = controller.rules.toList();
        final categories = Map.of(controller.categoriesById);
        if (rules.isEmpty) {
          return const EmptyState(
            icon: Icons.event_repeat_outlined,
            message: 'أضف الإيجار، الإنترنت أو الراتب مرة وحدة، والتطبيق بيسجّلها كل شهر لحاله.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            Card(
              child: Column(
                children: [
                  for (final (index, rule) in rules.indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      onTap: () => controller.openEdit(rule),
                      leading: categories[rule.categoryId] == null
                          ? null
                          : CategoryAvatar(category: categories[rule.categoryId]!),
                      title: Text(rule.label,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        rule.isActive
                            ? 'كل شهر يوم ${rule.dayOfMonth} · الجاي: '
                                '${ArabicDates.relativeDay(controller.nextDue(rule), today: controller.today)}'
                            : 'موقوفة',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(
                            rule.kind == RecurringKind.income ? rule.amount : -rule.amount,
                            currency: controller.currency,
                            showPlus: true,
                            showSymbol: false,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: rule.kind == RecurringKind.income
                                  ? AppColors.income
                                  : AppColors.expense,
                            ),
                          ),
                          Switch(
                            value: rule.isActive,
                            onChanged: (_) => controller.toggleActive(rule),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
      floatingActionButton: FloatingActionButton(
        tooltip: 'إضافة مصروف ثابت',
        onPressed: controller.openAdd,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/recurring_form/controllers/recurring_form_controller.dart
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Add a fixed monthly income or expense, or edit/delete the one with
/// [editId].
class RecurringFormController extends GetxController {
  RecurringFormController({
    required this.recurring,
    required this.categories,
    required this.settings,
    this.editId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final CategoryRepository categories;
  final SettingsService settings;
  final int? editId;
  final DateTime Function() _clock;

  final kind = TransactionKind.expense.obs;
  final amountText = ''.obs;
  final categoryId = RxnInt();
  late final RxInt dayOfMonth = min(_clock().day, 28).obs;
  final isEditing = false.obs;
  final isSaving = false.obs;
  final labelController = TextEditingController();
  final amountController = TextEditingController();
  final _allCategories = <TransactionCategory>[].obs;

  RecurringRule? _editing;
  int _editingDecimals = 0;

  late final Future<void> ready;

  Currency get currency => settings.currency;

  int? get amount => Money.parse(amountText.value,
      decimals: max(currency.decimals, _editingDecimals));

  bool get canSave =>
      !isSaving.value && amount != null && categoryId.value != null;

  List<TransactionCategory> get visibleCategories =>
      _allCategories.where((c) => c.kind == kind.value).toList();

  @override
  void onInit() {
    super.onInit();
    amountController.addListener(() => amountText.value = amountController.text);
    ready = _load();
  }

  Future<void> _load() async {
    _allCategories.assignAll(await categories.getAll());
    if (editId == null) return;
    final rule = (await recurring.getAll()).where((r) => r.id == editId).firstOrNull;
    if (rule == null) return;
    _editing = rule;
    isEditing.value = true;
    kind.value = rule.kind == RecurringKind.income
        ? TransactionKind.income
        : TransactionKind.expense;
    labelController.text = rule.label;
    amountController.text = Money.toEditable(rule.amount);
    final dot = amountController.text.indexOf('.');
    _editingDecimals = dot == -1 ? 0 : amountController.text.length - dot - 1;
    categoryId.value = rule.categoryId;
    dayOfMonth.value = rule.dayOfMonth;
  }

  void setKind(TransactionKind value) {
    if (kind.value == value) return;
    kind.value = value;
    categoryId.value = null;
  }

  void selectCategory(int id) => categoryId.value = id;

  void setDay(int day) => dayOfMonth.value = day;

  /// Saves the rule and immediately creates any entry that is already due.
  Future<bool> save() async {
    final value = amount;
    final category = categoryId.value;
    if (!canSave || value == null || category == null) return false;
    isSaving.value = true;
    try {
      final typed = labelController.text.trim();
      final label = typed.isNotEmpty
          ? typed
          : _allCategories.firstWhere((c) => c.id == category).name;
      final recurringKind = kind.value == TransactionKind.income
          ? RecurringKind.income
          : RecurringKind.expense;
      final editing = _editing;
      if (editing == null) {
        await recurring.add(RecurringRule(
          label: label,
          kind: recurringKind,
          amount: value,
          categoryId: category,
          dayOfMonth: dayOfMonth.value,
          startDate: DateKeys.dateOnly(_clock()),
        ));
      } else {
        await recurring.update(editing.copyWith(
          label: label,
          kind: recurringKind,
          amount: value,
          categoryId: category,
          dayOfMonth: dayOfMonth.value,
        ));
      }
      await recurring.applyDue(_clock());
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ المصروف الثابت');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Deletes the rule; entries it already created stay.
  Future<bool> delete() async {
    final id = _editing?.id;
    if (id == null || isSaving.value) return false;
    isSaving.value = true;
    try {
      await recurring.delete(id);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف المصروف الثابت');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  @override
  void onClose() {
    labelController.dispose();
    amountController.dispose();
    super.onClose();
  }
}
```

Note for the tests: they set `amountText` directly (the view sets it through `amountController`'s listener).

```dart
// file: lib/app/modules/recurring_form/bindings/recurring_form_binding.dart
import 'package:get/get.dart';

import '../controllers/recurring_form_controller.dart';

class RecurringFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.lazyPut(() => RecurringFormController(
          recurring: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          editId: args is int ? args : null,
        ));
  }
}
```

```dart
// file: lib/app/modules/recurring_form/views/recurring_form_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/category_grid.dart';
import '../../../widgets/kind_toggle.dart';
import '../controllers/recurring_form_controller.dart';

class RecurringFormView extends GetView<RecurringFormController> {
  const RecurringFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(
            controller.isEditing.value ? 'تعديل مصروف ثابت' : 'مصروف ثابت جديد')),
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Obx(() => KindToggle(
                value: controller.kind.value, onChanged: controller.setKind)),
            const SizedBox(height: 16),
            TextField(
              controller: controller.labelController,
              decoration: const InputDecoration(
                labelText: 'الاسم (اختياري)',
                hintText: 'مثلاً إيجار',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ',
                suffixText: controller.currency.symbol,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('ينحسب كل شهر يوم')),
                Obx(() => DropdownButton<int>(
                      value: controller.dayOfMonth.value,
                      items: [
                        for (var day = 1; day <= 28; day++)
                          DropdownMenuItem(value: day, child: Text('$day')),
                      ],
                      onChanged: (day) {
                        if (day != null) controller.setDay(day);
                      },
                    )),
              ],
            ),
            const SizedBox(height: 12),
            const Text('التصنيف',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Obx(() => CategoryGrid(
                  categories: controller.visibleCategories,
                  selectedId: controller.categoryId.value,
                  onSelected: controller.selectCategory,
                )),
            const SizedBox(height: 20),
            Obx(() => FilledButton(
                  onPressed: controller.canSave ? _save : null,
                  child: const Text('حفظ'),
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (await controller.save()) Get.back();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المصروف الثابت؟'),
        content: const Text('العمليات اللي انسجلت قبل بتضل موجودة.'),
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
    if (confirmed == true && await controller.delete()) Get.back();
  }
}
```

Add to `lib/app/routes/app_pages.dart`:

```dart
import '../modules/recurring/bindings/recurring_binding.dart';
import '../modules/recurring/views/recurring_view.dart';
import '../modules/recurring_form/bindings/recurring_form_binding.dart';
import '../modules/recurring_form/views/recurring_form_view.dart';
```

```dart
    GetPage(
      name: Routes.recurring,
      page: () => const RecurringView(),
      binding: RecurringBinding(),
    ),
    GetPage(
      name: Routes.recurringForm,
      page: () => const RecurringFormView(),
      binding: RecurringFormBinding(),
      fullscreenDialog: true,
    ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze && flutter test test/modules/recurring test/modules/recurring_form`
Expected: `No issues found!`, PASS

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add recurring rules list and form with immediate catch-up"
```

---

### Task 9: Favorites — save from the form, one tap on Home, manage list; Home budget banner

**Files:**
- Modify: `lib/app/modules/transaction_form/controllers/transaction_form_controller.dart`, `views/transaction_form_view.dart`, `bindings/transaction_form_binding.dart`, `test/modules/transaction_form/transaction_form_controller_test.dart` (helper `open`), `test/modules/error_handling_test.dart` (form construction)
- Modify: `lib/app/modules/home/controllers/home_controller.dart`, `bindings/home_binding.dart`, `views/home_view.dart`, `test/modules/home/home_controller_test.dart` (helper `open`)
- Create: `lib/app/modules/home/widgets/quick_templates_row.dart`, `lib/app/modules/home/widgets/budget_alert_banner.dart`, `lib/app/modules/templates/bindings/templates_binding.dart`, `controllers/templates_controller.dart`, `views/templates_view.dart`
- Modify: `lib/app/routes/app_pages.dart`
- Test: `test/modules/favorites_test.dart`

**Interfaces:**
- Consumes: `TemplateRepository`, `BudgetRepository`, `BudgetCalculator`.
- Produces:
  - `TransactionFormController` gains required `TemplateRepository templates` and `saveAsFavorite` (`RxBool`); a new transaction saved with it on also adds a `QuickTemplate` labelled with the note, or the category name when the note is empty.
  - `HomeController` gains required `TemplateRepository templates`, `BudgetRepository budgets`; fields `favorites` (`RxList<QuickTemplate>`), `urgentBudget` (`Rxn<BudgetStatus>`); methods `addFavorite(QuickTemplate) → Future<TransactionRecord?>`, `undoFavorite(TransactionRecord)`, `openBudgets()`, `openFavorites()`.
  - `TemplatesController({required TemplateRepository templates, required CategoryRepository categories, required SettingsService settings, required DatabaseService database})`: `templates`, `categoriesById`, `currency`, `load()`, `delete(QuickTemplate)`.

- [ ] **Step 1: Write the failing test; update construction helpers**

In `test/modules/transaction_form/transaction_form_controller_test.dart` and `test/modules/error_handling_test.dart`, pass `templates: Get.find()` wherever `TransactionFormController(` is constructed. In `test/modules/home/home_controller_test.dart` pass `templates: Get.find(), budgets: Get.find()` to `HomeController(`.

```dart
// file: test/modules/favorites_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/quick_template.dart';
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/template_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/home/controllers/home_controller.dart';
import 'package:calculator/app/modules/templates/controllers/templates_controller.dart';
import 'package:calculator/app/modules/transaction_form/controllers/transaction_form_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<HomeController> openHome() async {
    final c = Get.put(HomeController(
      transactions: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      templates: Get.find(),
      budgets: Get.find(),
      settings: Get.find(),
      database: Get.find(),
    ));
    await c.load();
    return c;
  }

  test('saving with "save as favorite" also creates a favorite', () async {
    final form = Get.put(TransactionFormController(
        transactions: Get.find(), categories: Get.find(), templates: Get.find(), settings: Get.find()));
    await form.ready;
    for (final key in ['1', '.', '5']) {
      form.pressKey(key);
    }
    form.selectCategory(foodCategoryId);
    form.noteController.text = 'قهوة';
    form.saveAsFavorite.value = true;
    await form.save();
    final favorite = (await Get.find<TemplateRepository>().getAll()).single;
    expect(favorite.label, 'قهوة');
    expect(favorite.amount, 1500);
    expect(favorite.categoryId, foodCategoryId);
  });

  test('a favorite without a note is named after its category', () async {
    final form = Get.put(TransactionFormController(
        transactions: Get.find(), categories: Get.find(), templates: Get.find(), settings: Get.find()));
    await form.ready;
    form.pressKey('3');
    form.selectCategory(2);
    form.saveAsFavorite.value = true;
    await form.save();
    expect((await Get.find<TemplateRepository>().getAll()).single.label, 'مواصلات');
  });

  test('one tap on a favorite adds today\'s transaction, and undo removes it', () async {
    await Get.find<TemplateRepository>().add(const QuickTemplate(
        label: 'قهوة', kind: TransactionKind.expense, amount: 1500, categoryId: 1));
    final home = await openHome();
    expect(home.favorites.single.label, 'قهوة');
    final added = await home.addFavorite(home.favorites.single);
    final all = await Get.find<TransactionRepository>().getAll();
    expect(all.single.amount, 1500);
    expect(all.single.note, 'قهوة');
    expect(all.single.date.day, DateTime.now().day);
    await home.undoFavorite(added!);
    expect(await Get.find<TransactionRepository>().getAll(), isEmpty);
  });

  test('Home shows the most urgent budget', () async {
    await Get.find<BudgetRepository>().setLimit(foodCategoryId, 10000);
    await Get.find<TransactionRepository>().add(expense(8800, DateTime.now()));
    final home = await openHome();
    expect(home.urgentBudget.value!.category.name, 'أكل');
    expect(home.urgentBudget.value!.percent, 88);
  });

  test('favorites can be deleted from the manage list', () async {
    await Get.find<TemplateRepository>().add(const QuickTemplate(
        label: 'تكسي', kind: TransactionKind.expense, amount: 3000, categoryId: 2));
    final c = Get.put(TemplatesController(
        templates: Get.find(), categories: Get.find(), settings: Get.find(), database: Get.find()));
    await c.load();
    await c.delete(c.items.single);
    await settle();
    expect(c.items, isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/modules`
Expected: FAIL — `templates`/`budgets` parameters and `TemplatesController` do not exist.

- [ ] **Step 3: Implement**

`transaction_form_controller.dart`: add imports `../../../data/models/quick_template.dart` and `../../../data/repositories/template_repository.dart`; add the constructor parameter `required this.templates,` and field `final TemplateRepository templates;`; add `final saveAsFavorite = false.obs;`; and in `_save()` replace

```dart
    if (_editing == null) {
      await transactions.add(record);
    } else {
```

with

```dart
    if (_editing == null) {
      await transactions.add(record);
      if (saveAsFavorite.value) {
        await templates.add(QuickTemplate(
          label: note.isNotEmpty
              ? note
              : _allCategories.firstWhere((c) => c.id == category).name,
          kind: record.kind,
          amount: value,
          categoryId: category,
        ));
      }
    } else {
```

`transaction_form_binding.dart`: add `templates: Get.find(),`.

`transaction_form_view.dart`: after the note/date `Row`, add

```dart
                  Obx(() => controller.isEditing.value
                      ? const SizedBox.shrink()
                      : CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: controller.saveAsFavorite.value,
                          onChanged: (v) => controller.saveAsFavorite.value = v ?? false,
                          title: const Text('احفظها كمفضّلة (زر بضغطة وحدة بالرئيسية)'),
                        )),
```

`home_controller.dart` — full replacement:

```dart
// file: lib/app/modules/home/controllers/home_controller.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/logic/budget_status.dart';
import '../../../core/logic/period.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/quick_template.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class HomeController extends GetxController {
  HomeController({
    required this.transactions,
    required this.categories,
    required this.savings,
    required this.templates,
    required this.budgets,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SavingsRepository savings;
  final TemplateRepository templates;
  final BudgetRepository budgets;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final summary = Rxn<BalanceSummary>();
  final period = Rxn<Period>();
  final recent = <TransactionRecord>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;
  final favorites = <QuickTemplate>[].obs;

  /// The budget closest to (or furthest past) its limit, when one is at
  /// 80 % or more.
  final urgentBudget = Rxn<BudgetStatus>();

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
    final favoriteList = await templates.getAll();
    final budgetList = await budgets.getAll();

    final byId = {for (final c in allCategories) c.id!: c};
    categoriesById.assignAll(byId);
    recent.assignAll(latest);
    favorites.assignAll(favoriteList);
    period.value = current;
    summary.value = BalanceCalculator.calculate(
        period: current, transactions: all, movements: movements);
    urgentBudget.value = BudgetCalculator.mostUrgent(BudgetCalculator.calculate(
      period: current,
      budgets: budgetList,
      categoriesById: byId,
      transactions: all,
    ));
  }

  /// Adds today's transaction from [favorite]. Returns it (for Undo), or null
  /// when saving failed.
  Future<TransactionRecord?> addFavorite(QuickTemplate favorite) async {
    try {
      return await transactions.add(TransactionRecord(
        kind: favorite.kind,
        amount: favorite.amount,
        categoryId: favorite.categoryId,
        date: DateKeys.dateOnly(_clock()),
        note: favorite.label,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            DateTime.now().millisecondsSinceEpoch),
      ));
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ العملية، جرّب مرة ثانية');
      return null;
    }
  }

  Future<void> undoFavorite(TransactionRecord record) async {
    try {
      await transactions.delete(record.id!);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف العملية، جرّب مرة ثانية');
    }
  }

  void openAdd() => Get.toNamed(Routes.transactionForm);

  void openEdit(TransactionRecord t) =>
      Get.toNamed(Routes.transactionForm, arguments: t.id);

  void openAll() => Get.offAllNamed(Routes.transactions);

  void openBudgets() => Get.offAllNamed(Routes.budgets);

  void openFavorites() => Get.toNamed(Routes.templates);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

`home_binding.dart`: add `templates: Get.find(), budgets: Get.find(),`.

```dart
// file: lib/app/modules/home/widgets/budget_alert_banner.dart
import 'package:flutter/material.dart';

import '../../../core/logic/budget_status.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

class BudgetAlertBanner extends StatelessWidget {
  const BudgetAlertBanner({
    super.key,
    required this.status,
    required this.currency,
    required this.onTap,
  });

  final BudgetStatus status;
  final Currency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final over = status.level == BudgetLevel.over;
    final message = over
        ? 'تجاوزت ميزانية ${status.category.name} بـ ${MoneyText.label(-status.remaining, currency)}'
        : 'صرفت ${status.percent}% من ميزانية ${status.category.name}';
    return Material(
      color: AppColors.warningSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFF5C9A6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: over ? AppColors.danger : AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/home/widgets/quick_templates_row.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/quick_template.dart';
import '../../../widgets/money_text.dart';

/// One-tap favorites: "قهوة · 1.500".
class QuickTemplatesRow extends StatelessWidget {
  const QuickTemplatesRow({
    super.key,
    required this.favorites,
    required this.currency,
    required this.onTap,
  });

  final List<QuickTemplate> favorites;
  final Currency currency;
  final ValueChanged<QuickTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final favorite = favorites[index];
          return ActionChip(
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
            shape: const StadiumBorder(),
            label: Text(
                '${favorite.label} · ${MoneyText.label(favorite.amount, currency, showSymbol: false)}'),
            onPressed: () => onTap(favorite),
          );
        },
      ),
    );
  }
}
```

`home_view.dart` — full replacement:

```dart
// file: lib/app/modules/home/views/home_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/quick_template.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/section_header.dart';
import '../controllers/home_controller.dart';
import '../widgets/balance_card.dart';
import '../widgets/budget_alert_banner.dart';
import '../widgets/quick_templates_row.dart';
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
          final urgent = controller.urgentBudget.value;
          final favorites = controller.favorites.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            children: [
              const Text('الشهر المالي',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              Text(period.label,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              BalanceCard(summary: summary, currency: controller.currency),
              if (urgent != null) ...[
                const SizedBox(height: 12),
                BudgetAlertBanner(
                  status: urgent,
                  currency: controller.currency,
                  onTap: controller.openBudgets,
                ),
              ],
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 20),
                SectionHeader(
                  title: 'مفضّلة — بضغطة وحدة',
                  actionLabel: 'تعديل',
                  onAction: controller.openFavorites,
                ),
                const SizedBox(height: 4),
                QuickTemplatesRow(
                  favorites: favorites,
                  currency: controller.currency,
                  onTap: (favorite) => _addFavorite(context, favorite),
                ),
              ],
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

  Future<void> _addFavorite(BuildContext context, QuickTemplate favorite) async {
    final home = controller;
    final messenger = ScaffoldMessenger.of(context);
    final added = await home.addFavorite(favorite);
    if (added == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('انضافت: ${favorite.label}'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () => home.undoFavorite(added),
        ),
      ));
  }
}
```

Templates module:

```dart
// file: lib/app/modules/templates/controllers/templates_controller.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../data/models/quick_template.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class TemplatesController extends GetxController {
  TemplatesController({
    required this.templates,
    required this.categories,
    required this.settings,
    required this.database,
  });

  final TemplateRepository templates;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;

  final items = <QuickTemplate>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final allCategories = await categories.getAll(includeArchived: true);
    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    items.assignAll(await templates.getAll());
  }

  Future<void> delete(QuickTemplate template) async {
    try {
      await templates.delete(template.id!);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف المفضّلة');
    }
  }

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

The list field is named `items` because `templates` is already the repository field.

```dart
// file: lib/app/modules/templates/bindings/templates_binding.dart
import 'package:get/get.dart';

import '../controllers/templates_controller.dart';

class TemplatesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => TemplatesController(
          templates: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/templates/views/templates_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../widgets/category_avatar.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/templates_controller.dart';

class TemplatesView extends GetView<TemplatesController> {
  const TemplatesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضّلة')),
      body: Obx(() {
        final items = controller.items.toList();
        final categories = Map.of(controller.categoriesById);
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.star_outline,
            message: 'لما تضيف عملية، اختار "احفظها كمفضّلة" لتصير زر بضغطة وحدة بالرئيسية.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Card(
              child: Column(
                children: [
                  for (final (index, item) in items.indexed) ...[
                    if (index > 0) const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: categories[item.categoryId] == null
                          ? null
                          : CategoryAvatar(category: categories[item.categoryId]!),
                      title: Text(item.label),
                      subtitle: MoneyText(item.amount, currency: controller.currency),
                      trailing: IconButton(
                        tooltip: 'حذف ${item.label}',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => controller.delete(item),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}
```

Add to `lib/app/routes/app_pages.dart`:

```dart
import '../modules/templates/bindings/templates_binding.dart';
import '../modules/templates/views/templates_view.dart';
```

```dart
    GetPage(
      name: Routes.templates,
      page: () => const TemplatesView(),
      binding: TemplatesBinding(),
    ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add favorites (save from form, one tap on Home, manage) and Home budget banner"
```

---

### Task 10: Settings — daily reminder and links

**Files:**
- Modify: `lib/app/modules/settings/controllers/settings_controller.dart`, `bindings/settings_binding.dart`, `views/settings_view.dart`, `test/modules/settings/settings_controller_test.dart` and `test/modules/error_handling_test.dart` (construction)
- Test: `test/modules/settings/reminder_settings_test.dart`

**Interfaces:**
- Consumes: `NotificationService` (Task 5), `Routes`.
- Produces: `SettingsController({required SettingsService settingsService, required NotificationService notifications})` with `permissionGranted` getter, `setReminderEnabled(bool)`, `setReminderTime(int hour, int minute)`, `reminderLabel` (`'21:00'`), `openRecurring()`, `openFavorites()`.

- [ ] **Step 1: Write the failing test; update construction**

In `settings_controller_test.dart` and `error_handling_test.dart`, construct with `SettingsController(settingsService: Get.find(), notifications: Get.find())`.

```dart
// file: test/modules/settings/reminder_settings_test.dart
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_notifications.dart';
import '../../helpers/test_services.dart';

void main() {
  late FakeNotificationProvider fake;

  setUp(() async => fake = await setUpTestServices());

  SettingsController open() => Get.put(
      SettingsController(settingsService: Get.find(), notifications: Get.find()));

  test('shows the reminder time as HH:MM', () {
    expect(open().reminderLabel, '21:00');
  });

  test('changing the time reschedules the reminder', () async {
    final c = open();
    await c.setReminderTime(7, 5);
    await settle();
    expect(c.reminderLabel, '07:05');
    final reminder = fake.scheduled[NotificationService.reminderId]!;
    expect((reminder.hour, reminder.minute), (7, 5));
  });

  test('turning the reminder off cancels it', () async {
    final c = open();
    await c.setReminderEnabled(false);
    await settle();
    expect(c.settings.reminderEnabled, isFalse);
    expect(fake.scheduled, isEmpty);
  });

  test('reports when notifications are refused', () async {
    fake.granted = false;
    await Get.find<NotificationService>().init();
    expect(open().permissionGranted, isFalse);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/modules/settings`
Expected: FAIL — `notifications` parameter and reminder methods do not exist.

- [ ] **Step 3: Implement** — `settings_controller.dart` full replacement:

```dart
// file: lib/app/modules/settings/controllers/settings_controller.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../data/models/app_settings.dart';
import '../../../routes/app_routes.dart';
import '../../../services/message_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/settings_service.dart';

class SettingsController extends GetxController {
  SettingsController({
    required this.settingsService,
    required this.notifications,
  });

  final SettingsService settingsService;
  final NotificationService notifications;

  /// Reads the reactive value, so an `Obx` that uses it rebuilds on change.
  AppSettings get settings => settingsService.settings.value;

  bool get permissionGranted => notifications.permissionGranted.value;

  /// "21:00"
  String get reminderLabel {
    final minutes = settings.reminderMinutes;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }

  Future<void> setStartDay(int day) =>
      _update(settings.copyWith(periodStartDay: day));

  Future<void> setCurrency(String code) {
    final currency = Currencies.byCode(code);
    return _update(settings.copyWith(
      currencyCode: currency.code,
      currencyDecimals: currency.decimals,
    ));
  }

  Future<void> setReminderEnabled(bool enabled) =>
      _update(settings.copyWith(reminderEnabled: enabled));

  Future<void> setReminderTime(int hour, int minute) =>
      _update(settings.copyWith(reminderMinutes: hour * 60 + minute));

  void openRecurring() => Get.toNamed(Routes.recurring);

  void openFavorites() => Get.toNamed(Routes.templates);

  Future<void> _update(AppSettings value) async {
    try {
      await settingsService.update(value);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الإعدادات');
    }
  }
}
```

`settings_binding.dart`: `SettingsController(settingsService: Get.find(), notifications: Get.find())`.

`settings_view.dart`: after the currency `Card`, add:

```dart
            const _SectionTitle('التذكير اليومي'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('ذكّرني أسجّل مصاريفي'),
                    value: settings.reminderEnabled,
                    onChanged: controller.setReminderEnabled,
                  ),
                  ListTile(
                    enabled: settings.reminderEnabled,
                    title: const Text('الساعة'),
                    trailing: Text(controller.reminderLabel,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => _pickTime(context, settings.reminderMinutes),
                  ),
                  if (!controller.permissionGranted)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'الإشعارات مطفية للتطبيق. فعّلها من إعدادات الجهاز لتوصلك التذكيرات وتنبيهات الميزانية.',
                        style: TextStyle(color: AppColors.warning, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const _SectionTitle('إدارة'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_repeat_outlined),
                    title: const Text('المصاريف الثابتة'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: controller.openRecurring,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('المفضّلة'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: controller.openFavorites,
                  ),
                ],
              ),
            ),
```

and add to `SettingsView`:

```dart
  Future<void> _pickTime(BuildContext context, int minutes) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked != null) controller.setReminderTime(picked.hour, picked.minute);
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add daily reminder settings and links to fixed costs and favorites"
```

---

### Task 11: End-to-end checks, README, build

**Files:**
- Modify: `test/app_test.dart` (add Phase 2 flows), `README.md`

- [ ] **Step 1: Write the failing end-to-end tests** — append to `test/app_test.dart` (and import `budget_repository.dart`):

```dart
  testWidgets('the budgets tab shows a budget set from the repository', (tester) async {
    await boot(tester);
    await tester.runAsync(() => Get.find<BudgetRepository>().setLimit(1, 200000));
    await tester.tap(find.text('الميزانية'));
    await idle(tester);
    expect(find.text('إضافة ميزانية'), findsOneWidget);
    expect(find.text('أكل'), findsOneWidget);
  });

  testWidgets('Home warns when a budget is nearly used up', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      await Get.find<BudgetRepository>().setLimit(1, 10000);
      await Get.find<TransactionRepository>().add(expense(9000, DateTime.now()));
    });
    await idle(tester);
    expect(find.text('صرفت 90% من ميزانية أكل'), findsOneWidget);
  });

  testWidgets('saving a favorite puts a one-tap button on Home', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('إضافة عملية'));
    await idle(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('.'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('أكل'));
    await tester.enterText(find.byType(TextField), 'قهوة');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('حفظ'));
    await idle(tester);
    await idle(tester);

    final chip = find.textContaining('قهوة ·');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await brief(tester);
    expect(find.text('انضافت: قهوة'), findsOneWidget);
    final all = await tester.runAsync(Get.find<TransactionRepository>().getAll);
    expect(all, hasLength(2));
  });
```

Run: `flutter test test/app_test.dart --timeout 60s`
Expected: before Tasks 7–10 these would fail; at this point they should PASS. If one fails, debug (systematic-debugging) — do not weaken the assertion.

- [ ] **Step 2: README** — replace the "Features (Phase 1)" section with:

```markdown
## Features
- Add, edit and delete income and expenses with a fast keypad and category grid
- Home: "Remaining from salary" for the current financial month, carry-over from earlier months,
  a warning when a budget is nearly used up, and one-tap favorites
- Transactions grouped by day, swipe to delete with Undo, browse previous months
- Budgets per category with progress bars and alerts at 80 % and 100 %
- Fixed monthly income and expenses (rent, internet, salary) added automatically
- Daily reminder notification (default 21:00), all scheduled on the device
- Settings: month start day, currency, reminder, fixed costs and favorites

Planned: reports and charts, savings goals, month-end savings prompt, backup and restore.
```

and add `services/` notes: `notification, budget alerts, startup (recurring catch-up on start/resume), messages`.

- [ ] **Step 3: Full verification and simulator build**

Run: `flutter analyze && flutter test --timeout 60s && flutter build ios --simulator --debug`
Expected: `No issues found!`, all tests pass, `✓ Built build/ios/iphonesimulator/Runner.app`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "test: end-to-end checks for budgets, Home warning and favorites; update README"
```
