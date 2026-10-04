# Phase 3 — Insight and Goals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the spec: savings goals with the hybrid flow (manual add/withdraw, month-end leftover prompt, recurring savings, General Savings), Home totals ("مجموع المدخرات", "الكلي معك"), reports (spending by category and 6-period comparison), and local JSON backup/restore.

**Architecture:** Same GetX Pattern. New pure logic in `core/logic` (`GoalProjection`, `ReportCalculator`, `MonthEndCheck`), `SavingsRepository` grows goal and movement operations, a `BackupService` over the existing schema, device file access behind a `FileExchangeProvider` interface (faked in tests), and new modules `savings`, `goal_form`, `goal_detail`, `month_end`, `reports`. The shared `AmountDialog` replaces the budgets-only dialog.

**Tech Stack:** Flutter 3.44.8, `get`, `sqflite`, `fl_chart` 1.2.0, `path_provider`, `share_plus` 13 (`SharePlus.instance.share(ShareParams(files: [XFile]))`), `file_picker` 13 (`FilePicker.pickFiles(...)` static), all offline.

**Spec:** `docs/superpowers/specs/2026-10-01-expense-tracker-design.md` (§6.3, §6.4, §6.8, §9, §10 Phase 3, §11, §12)

## Global Constraints

- All earlier Global Constraints hold (offline, int thousandths, `YYYY-MM-DD`, Arabic RTL, GetX rules, controllers report `DatabaseException` via `MessageService`).
- No schema change (schema version 1 already has `savings_goals`, `savings_movements`, `settings.last_month_end_prompt_period`, `settings.last_backup_at`).
- A withdrawal can never take a goal below zero; a goal can be removed only when it holds 0 (deleted if it has no history, archived otherwise); General Savings can never be removed.
- Month-end: offer only the previous period's positive Remaining, once per period (`last_month_end_prompt_period`); allocations go in one database transaction as `source = monthEnd`.
- Backup file: `{"format":"masarifi-backup","schemaVersion":1,"exportedAt":…,"tables":{…}}`; restore rejects other formats and newer schema versions, needs exactly one settings row, and replaces everything inside one transaction.
- Bottom navigation (Phase 3): الرئيسية · العمليات · التقارير · الميزانية · الإعدادات. Savings opens from Home and Reports.
- Dialogs that hold a `TextEditingController` own it in their own `State` (lesson from the Phase 2 crash).

## Review Focus

1. Withdrawing more than a goal holds, or two quick withdrawals → refused with a message, balance never negative. *(Task 3 repository test, Task 6 goal detail test)*
2. Month-end allocation that exceeds the leftover, or a failure half-way → nothing saved, prompt still pending. *(Task 3 atomic batch test, Task 7 month-end tests)*
3. A corrupt, foreign or newer backup file → clear message, current data untouched. *(Task 4 backup tests)*
4. Goal target date in the past or in the current period → projection asks for the full remaining amount now, never divides by zero. *(Task 2 projection tests)*
5. Reports for a period with no expenses → empty state, no chart crash, no "0 %" division. *(Task 2 report tests, Task 9 controller test)*

---

### Task 1: Savings goal model and settings fields

**Files:**
- Create: `lib/app/data/models/savings_goal.dart`
- Modify: `lib/app/data/models/app_settings.dart` (`copyWith` gains `lastMonthEndPromptPeriod`, `lastBackupAt`)
- Test: `test/data/models/phase3_models_test.dart`

**Interfaces:**
- Produces: `SavingsGoal({int? id, required String name, int? targetAmount, DateTime? targetDate, bool isGeneral = false, bool isArchived = false, required DateTime createdAt})`, `fromMap`, `toMap`, `withId(int)`; `AppSettings.copyWith(..., String? lastMonthEndPromptPeriod, DateTime? lastBackupAt)`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/data/models/phase3_models_test.dart
import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SavingsGoal round-trips with an optional target', () {
    final goal = SavingsGoal(
      id: 2,
      name: 'لابتوب',
      targetAmount: 900000,
      targetDate: DateTime(2027, 3, 10),
      createdAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    expect(goal.toMap()['target_date'], '2027-03-10');
    expect(SavingsGoal.fromMap(goal.toMap()), goal);

    final general = SavingsGoal(
      id: 1,
      name: 'ادخار عام',
      isGeneral: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );
    expect(SavingsGoal.fromMap(general.toMap()), general);
    expect(general.withId(7).id, 7);
  });

  test('AppSettings copyWith sets the month-end and backup fields', () {
    final changed = const AppSettings().copyWith(
      lastMonthEndPromptPeriod: '2026-09',
      lastBackupAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
    );
    expect(changed.lastMonthEndPromptPeriod, '2026-09');
    expect(changed.copyWith(periodStartDay: 5).lastBackupAt,
        DateTime.fromMillisecondsSinceEpoch(1790000000000));
    expect(AppSettings.fromMap(changed.toMap()), changed);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/phase3_models_test.dart`
Expected: FAIL — `savings_goal.dart` not found / no named parameter `lastMonthEndPromptPeriod`.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/data/models/savings_goal.dart
import '../../core/utils/date_utils.dart';

/// A savings pot. Exactly one is [isGeneral] ("ادخار عام") and has no target.
class SavingsGoal {
  const SavingsGoal({
    this.id,
    required this.name,
    this.targetAmount,
    this.targetDate,
    this.isGeneral = false,
    this.isArchived = false,
    required this.createdAt,
  });

  factory SavingsGoal.fromMap(Map<String, Object?> map) {
    final date = map['target_date'] as String?;
    return SavingsGoal(
      id: map['id'] as int?,
      name: map['name'] as String,
      targetAmount: map['target_amount'] as int?,
      targetDate: date == null ? null : DateKeys.toDate(date),
      isGeneral: map['is_general'] == 1,
      isArchived: map['is_archived'] == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  final int? id;
  final String name;
  final int? targetAmount;
  final DateTime? targetDate;
  final bool isGeneral;
  final bool isArchived;
  final DateTime createdAt;

  SavingsGoal withId(int id) => SavingsGoal(
        id: id,
        name: name,
        targetAmount: targetAmount,
        targetDate: targetDate,
        isGeneral: isGeneral,
        isArchived: isArchived,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'target_amount': targetAmount,
        'target_date': targetDate == null ? null : DateKeys.fromDate(targetDate!),
        'is_general': isGeneral ? 1 : 0,
        'is_archived': isArchived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is SavingsGoal &&
      other.id == id &&
      other.name == name &&
      other.targetAmount == targetAmount &&
      other.targetDate == targetDate &&
      other.isGeneral == isGeneral &&
      other.isArchived == isArchived &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
      id, name, targetAmount, targetDate, isGeneral, isArchived, createdAt);
}
```

In `app_settings.dart`, extend `copyWith`:

```dart
  AppSettings copyWith({
    int? periodStartDay,
    String? currencyCode,
    int? currencyDecimals,
    bool? reminderEnabled,
    int? reminderMinutes,
    String? lastMonthEndPromptPeriod,
    DateTime? lastBackupAt,
  }) =>
      AppSettings(
        periodStartDay: periodStartDay ?? this.periodStartDay,
        currencyCode: currencyCode ?? this.currencyCode,
        currencyDecimals: currencyDecimals ?? this.currencyDecimals,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        lastMonthEndPromptPeriod:
            lastMonthEndPromptPeriod ?? this.lastMonthEndPromptPeriod,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      );
```

- [ ] **Step 4: Run tests** — Run: `flutter test test/data/models` — Expected: PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add savings goal model and month-end/backup settings fields"`

---

### Task 2: Goal projection, reports and month-end logic

**Files:**
- Create: `lib/app/core/logic/goal_projection.dart`, `lib/app/core/logic/report_calculator.dart`, `lib/app/core/logic/month_end_check.dart`
- Test: `test/core/logic/goal_projection_test.dart`, `report_calculator_test.dart`, `month_end_check_test.dart`

**Interfaces:**
- Produces:
  - `GoalProgress({required SavingsGoal goal, required int saved})`: `target`, `progress` (0–1), `percent`, `isReached`, `remaining`
  - `GoalProjection.monthlyNeeded(GoalProgress, Period current) → int?`
  - `CategoryShare {category, amount, percent}`, `PeriodTotals {period, income, expenses}`
  - `ReportCalculator.byCategory({required Period period, required Iterable<TransactionRecord> transactions, required Map<int, TransactionCategory> categoriesById}) → List<CategoryShare>`; `ReportCalculator.totals({required Period last, required int count, required Iterable<TransactionRecord> transactions}) → List<PeriodTotals>` (oldest first); `ReportCalculator.changePercent({required int previous, required int current}) → int?`
  - `MonthEndCheck.leftoverToOffer({required Period current, required String? lastPromptedKey, required Iterable<TransactionRecord> transactions, required Iterable<SavingsMovement> movements}) → int?`

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/core/logic/goal_projection_test.dart
import 'package:calculator/app/core/logic/goal_projection.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:flutter_test/flutter_test.dart';

GoalProgress laptop({int saved = 540000, int? target = 900000, DateTime? date}) =>
    GoalProgress(
      goal: SavingsGoal(
        id: 2,
        name: 'لابتوب',
        targetAmount: target,
        targetDate: date,
        createdAt: DateTime(2026),
      ),
      saved: saved,
    );

void main() {
  final october = Period.containing(DateTime(2026, 10, 4), startDay: 1);

  test('progress, percent and remaining', () {
    final p = laptop(date: DateTime(2027, 3, 10));
    expect(p.percent, 60);
    expect(p.progress, closeTo(0.6, 0.0001));
    expect(p.remaining, 360000);
    expect(p.isReached, isFalse);
    expect(laptop(saved: 950000).progress, 1.0);
    expect(laptop(saved: 950000).isReached, isTrue);
  });

  test('splits what is left across the periods up to the target date', () {
    // October to March = 6 periods; 360 / 6 = 60 a month.
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2027, 3, 10)), october), 60000);
  });

  test('rounds up so the goal is reached in time', () {
    // 360 over 7 periods (Oct–Apr) = 51.428… → 51.429
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2027, 4, 1)), october), 51429);
  });

  test('a date in this period or already passed asks for everything now', () {
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2026, 10, 20)), october), 360000);
    expect(GoalProjection.monthlyNeeded(laptop(date: DateTime(2026, 1, 1)), october), 360000);
  });

  test('no projection without a target, without a date, or once reached', () {
    expect(GoalProjection.monthlyNeeded(laptop(target: null, date: DateTime(2027)), october), isNull);
    expect(GoalProjection.monthlyNeeded(laptop(), october), isNull);
    expect(GoalProjection.monthlyNeeded(laptop(saved: 900000, date: DateTime(2027)), october), isNull);
  });
}
```

```dart
// file: test/core/logic/report_calculator_test.dart
import 'package:calculator/app/core/logic/period.dart';
import 'package:calculator/app/core/logic/report_calculator.dart';
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/transaction_category.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

const food = TransactionCategory(
    id: 1, name: 'أكل', iconKey: 'food', colorValue: 0, kind: TransactionKind.expense);
const bills = TransactionCategory(
    id: 3, name: 'فواتير', iconKey: 'bills', colorValue: 0, kind: TransactionKind.expense);

void main() {
  final october = Period.containing(DateTime(2026, 10, 4), startDay: 1);

  test('spending by category for the period, largest first, with percentages', () {
    final shares = ReportCalculator.byCategory(
      period: october,
      categoriesById: const {1: food, 3: bills},
      transactions: [
        expense(30000, DateTime(2026, 10, 2)),
        expense(70000, DateTime(2026, 10, 3), categoryId: 3),
        expense(999000, DateTime(2026, 9, 30)),
        income(500000, DateTime(2026, 10, 1)),
      ],
    );
    expect(shares.map((s) => s.category.name), ['فواتير', 'أكل']);
    expect(shares.map((s) => s.percent), [70, 30]);
    expect(shares.first.amount, 70000);
  });

  test('a period without expenses has no shares', () {
    expect(
      ReportCalculator.byCategory(
          period: october, categoriesById: const {1: food}, transactions: const []),
      isEmpty,
    );
  });

  test('totals for the last periods, oldest first', () {
    final totals = ReportCalculator.totals(
      last: october,
      count: 3,
      transactions: [
        expense(10000, DateTime(2026, 8, 5)),
        income(50000, DateTime(2026, 9, 1)),
        expense(20000, DateTime(2026, 10, 2)),
        expense(5000, DateTime(2026, 10, 3)),
      ],
    );
    expect(totals.map((t) => t.period.key), ['2026-08', '2026-09', '2026-10']);
    expect(totals.map((t) => t.expenses), [10000, 0, 25000]);
    expect(totals[1].income, 50000);
  });

  test('change from the previous period', () {
    expect(ReportCalculator.changePercent(previous: 100000, current: 112000), 12);
    expect(ReportCalculator.changePercent(previous: 100000, current: 75000), -25);
    expect(ReportCalculator.changePercent(previous: 0, current: 5000), isNull);
  });
}
```

```dart
// file: test/core/logic/month_end_check_test.dart
import 'package:calculator/app/core/logic/month_end_check.dart';
import 'package:calculator/app/core/logic/period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';

void main() {
  final october = Period.containing(DateTime(2026, 10, 4), startDay: 1);
  final september = [
    income(1250000, DateTime(2026, 9, 1)),
    expense(750000, DateTime(2026, 9, 10)),
  ];

  test('offers what was left at the end of the previous period', () {
    expect(
      MonthEndCheck.leftoverToOffer(
          current: october, lastPromptedKey: null, transactions: september, movements: const []),
      500000,
    );
  });

  test('money already saved last period is not offered again', () {
    expect(
      MonthEndCheck.leftoverToOffer(
        current: october,
        lastPromptedKey: '2026-08',
        transactions: september,
        movements: [saving(200000, DateTime(2026, 9, 20))],
      ),
      300000,
    );
  });

  test('nothing once the user answered for that period', () {
    expect(
      MonthEndCheck.leftoverToOffer(
          current: october, lastPromptedKey: '2026-09', transactions: september, movements: const []),
      isNull,
    );
  });

  test('nothing when the previous period ended at zero or below', () {
    expect(
      MonthEndCheck.leftoverToOffer(
        current: october,
        lastPromptedKey: null,
        transactions: [expense(1000, DateTime(2026, 9, 3))],
        movements: const [],
      ),
      isNull,
    );
    expect(
      MonthEndCheck.leftoverToOffer(
          current: october, lastPromptedKey: null, transactions: const [], movements: const []),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/logic`
Expected: FAIL — new files not found.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/core/logic/goal_projection.dart
import '../../data/models/savings_goal.dart';
import '../utils/date_utils.dart';
import 'period.dart';

/// How much a goal holds compared with its target.
class GoalProgress {
  const GoalProgress({required this.goal, required this.saved});

  final SavingsGoal goal;
  final int saved;

  int? get target => goal.targetAmount;

  bool get _hasTarget => target != null && target! > 0;

  double get progress => _hasTarget ? (saved / target!).clamp(0.0, 1.0) : 0;

  int get percent => _hasTarget ? saved * 100 ~/ target! : 0;

  bool get isReached => _hasTarget && saved >= target!;

  /// What is still missing (0 without a target or once reached).
  int get remaining => _hasTarget && !isReached ? target! - saved : 0;
}

abstract final class GoalProjection {
  /// The amount to put aside each period to reach the goal by its target
  /// date, rounded up (spec §6.4). Null without a target or a date, or once
  /// the goal is reached. A date in the current period or already past asks
  /// for the whole remaining amount now.
  static int? monthlyNeeded(GoalProgress progress, Period current) {
    final date = progress.goal.targetDate;
    if (date == null || progress.target == null || progress.isReached) {
      return null;
    }
    final day = DateKeys.dateOnly(date);
    var periods = 1;
    var period = current;
    while (!period.end.isAfter(day)) {
      period = period.next;
      periods++;
    }
    final left = progress.remaining;
    return (left + periods - 1) ~/ periods;
  }
}
```

```dart
// file: lib/app/core/logic/report_calculator.dart
import '../../data/models/enums.dart';
import '../../data/models/transaction_category.dart';
import '../../data/models/transaction_record.dart';
import 'period.dart';

class CategoryShare {
  const CategoryShare({
    required this.category,
    required this.amount,
    required this.percent,
  });

  final TransactionCategory category;
  final int amount;
  final int percent;
}

class PeriodTotals {
  const PeriodTotals({
    required this.period,
    required this.income,
    required this.expenses,
  });

  final Period period;
  final int income;
  final int expenses;
}

abstract final class ReportCalculator {
  /// Expenses of [period] per category, largest first. Empty when nothing
  /// was spent.
  static List<CategoryShare> byCategory({
    required Period period,
    required Iterable<TransactionRecord> transactions,
    required Map<int, TransactionCategory> categoriesById,
  }) {
    final sums = <int, int>{};
    for (final t in transactions) {
      if (t.kind != TransactionKind.expense || !period.contains(t.date)) continue;
      sums[t.categoryId] = (sums[t.categoryId] ?? 0) + t.amount;
    }
    final total = sums.values.fold(0, (a, b) => a + b);
    if (total == 0) return const [];
    final shares = [
      for (final MapEntry(key: id, value: amount) in sums.entries)
        if (categoriesById[id] case final category?)
          CategoryShare(
            category: category,
            amount: amount,
            percent: (amount * 100 / total).round(),
          ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return shares;
  }

  /// Income and expenses of the [count] periods ending with [last], oldest
  /// first.
  static List<PeriodTotals> totals({
    required Period last,
    required int count,
    required Iterable<TransactionRecord> transactions,
  }) {
    final periods = <Period>[last];
    while (periods.length < count) {
      periods.insert(0, periods.first.previous);
    }
    return [
      for (final period in periods)
        PeriodTotals(
          period: period,
          income: _sum(transactions, period, TransactionKind.income),
          expenses: _sum(transactions, period, TransactionKind.expense),
        ),
    ];
  }

  /// Percent change from [previous] to [current]; null when [previous] is 0.
  static int? changePercent({required int previous, required int current}) =>
      previous == 0 ? null : ((current - previous) * 100 / previous).round();

  static int _sum(
    Iterable<TransactionRecord> transactions,
    Period period,
    TransactionKind kind,
  ) =>
      transactions
          .where((t) => t.kind == kind && period.contains(t.date))
          .fold(0, (sum, t) => sum + t.amount);
}
```

```dart
// file: lib/app/core/logic/month_end_check.dart
import '../../data/models/savings_movement.dart';
import '../../data/models/transaction_record.dart';
import 'balance_calculator.dart';
import 'period.dart';

abstract final class MonthEndCheck {
  /// What was left at the end of the period before [current], when the user
  /// has not answered the month-end question for it yet (spec §6.4).
  static int? leftoverToOffer({
    required Period current,
    required String? lastPromptedKey,
    required Iterable<TransactionRecord> transactions,
    required Iterable<SavingsMovement> movements,
  }) {
    final previous = current.previous;
    if (lastPromptedKey == previous.key) return null;
    final remaining = BalanceCalculator.calculate(
      period: previous,
      transactions: transactions,
      movements: movements,
    ).remaining;
    return remaining > 0 ? remaining : null;
  }
}
```

- [ ] **Step 4: Run tests** — Run: `flutter test test/core/logic` — Expected: PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add goal projection, report and month-end logic"`

---

### Task 3: Savings goals and movements in the repository

**Files:**
- Modify (full replacement): `lib/app/data/repositories/savings_repository.dart`
- Test: `test/data/repositories/savings_repository_test.dart`

**Interfaces:**
- Produces: `InsufficientSavingsException(int available)`, `GoalNotEmptyException(int balance)`; `SavingsRepository`: `getAllMovements()` (unchanged), `getGoals({bool includeArchived = false})` (General first), `getGoal(int id) → Future<SavingsGoal?>`, `balances() → Future<Map<int, int>>`, `addGoal(SavingsGoal) → Future<SavingsGoal>`, `updateGoal(SavingsGoal)`, `removeGoal(SavingsGoal) → Future<bool>` (true = archived), `addMovements(List<SavingsMovement>)`, `addMovement(SavingsMovement)`, `getMovements(int goalId)` (newest first). Writes notify.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/data/repositories/savings_repository_test.dart
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_database.dart';

void main() {
  late DatabaseService database;
  late SavingsRepository repo;

  setUp(() async {
    database = await openTestDatabase();
    repo = SavingsRepository(database);
  });

  Future<SavingsGoal> laptop() => repo.addGoal(SavingsGoal(
      name: 'لابتوب', targetAmount: 900000, createdAt: DateTime(2026, 10, 1)));

  test('General Savings comes first, then goals', () async {
    await laptop();
    final goals = await repo.getGoals();
    expect(goals.map((g) => g.name), ['ادخار عام', 'لابتوب']);
    expect(goals.first.isGeneral, isTrue);
  });

  test('balances add up deposits and withdrawals per goal', () async {
    final goal = await laptop();
    await repo.addMovement(saving(100000, DateTime(2026, 10, 1), goalId: goal.id!));
    await repo.addMovement(saving(-30000, DateTime(2026, 10, 2), goalId: goal.id!));
    await repo.addMovement(saving(5000, DateTime(2026, 10, 2)));
    expect(await repo.balances(), {goal.id: 70000, 1: 5000});
    expect((await repo.getMovements(goal.id!)).map((m) => m.amount), [-30000, 100000]);
  });

  test('a withdrawal larger than the goal holds is refused and nothing is saved', () async {
    final goal = await laptop();
    await repo.addMovement(saving(10000, DateTime(2026, 10, 1), goalId: goal.id!));
    await expectLater(
      repo.addMovement(saving(-20000, DateTime(2026, 10, 2), goalId: goal.id!)),
      throwsA(isA<InsufficientSavingsException>()
          .having((e) => e.available, 'available', 10000)),
    );
    expect((await repo.balances())[goal.id], 10000);
  });

  test('a batch is all or nothing', () async {
    final goal = await laptop();
    await expectLater(
      repo.addMovements([
        saving(50000, DateTime(2026, 10, 1)),
        saving(-1, DateTime(2026, 10, 1), goalId: goal.id!),
      ]),
      throwsA(isA<InsufficientSavingsException>()),
    );
    expect(await repo.getAllMovements(), isEmpty);
  });

  test('a goal is deleted when unused, archived when it has history', () async {
    final unused = await laptop();
    expect(await repo.removeGoal(unused), isFalse);
    expect(await repo.getGoal(unused.id!), isNull);

    final used = await laptop();
    await repo.addMovement(saving(1000, DateTime(2026, 10, 1), goalId: used.id!));
    await repo.addMovement(saving(-1000, DateTime(2026, 10, 2), goalId: used.id!));
    expect(await repo.removeGoal(used), isTrue);
    expect((await repo.getGoal(used.id!))!.isArchived, isTrue);
    expect((await repo.getGoals()).map((g) => g.id), isNot(contains(used.id)));
  });

  test('a goal that still holds money cannot be removed', () async {
    final goal = await laptop();
    await repo.addMovement(saving(1000, DateTime(2026, 10, 1), goalId: goal.id!));
    await expectLater(repo.removeGoal(goal), throwsA(isA<GoalNotEmptyException>()));
  });

  test('General Savings can never be removed', () async {
    final general = (await repo.getGoals()).first;
    await expectLater(repo.removeGoal(general), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — Run: `flutter test test/data/repositories/savings_repository_test.dart` — Expected: FAIL (methods missing).

- [ ] **Step 3: Implement**

```dart
// file: lib/app/data/repositories/savings_repository.dart
import 'package:sqflite/sqflite.dart';

import '../../services/database_service.dart';
import '../models/savings_goal.dart';
import '../models/savings_movement.dart';

/// A withdrawal asked for more than the goal holds.
class InsufficientSavingsException implements Exception {
  const InsufficientSavingsException(this.available);

  final int available;
}

/// A goal can only be removed once it is empty.
class GoalNotEmptyException implements Exception {
  const GoalNotEmptyException(this.balance);

  final int balance;
}

class SavingsRepository {
  SavingsRepository(this._database);

  final DatabaseService _database;

  static const _goals = 'savings_goals';
  static const _movements = 'savings_movements';

  Future<List<SavingsMovement>> getAllMovements() async {
    final rows = await _database.db.query(_movements, orderBy: 'date, id');
    return rows.map(SavingsMovement.fromMap).toList();
  }

  /// Active goals, General Savings first.
  Future<List<SavingsGoal>> getGoals({bool includeArchived = false}) async {
    final rows = await _database.db.query(
      _goals,
      where: includeArchived ? null : 'is_archived = 0',
      orderBy: 'is_general DESC, id',
    );
    return rows.map(SavingsGoal.fromMap).toList();
  }

  Future<SavingsGoal?> getGoal(int id) async {
    final rows =
        await _database.db.query(_goals, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : SavingsGoal.fromMap(rows.single);
  }

  /// What each goal holds, by goal id (goals without movements are absent).
  Future<Map<int, int>> balances() async {
    final rows = await _database.db.rawQuery(
        'SELECT goal_id, SUM(amount) AS total FROM $_movements GROUP BY goal_id');
    return {for (final r in rows) r['goal_id'] as int: r['total'] as int};
  }

  Future<SavingsGoal> addGoal(SavingsGoal goal) async {
    final id = await _database.db.insert(_goals, goal.toMap()..remove('id'));
    _database.notifyChanged();
    return goal.withId(id);
  }

  Future<void> updateGoal(SavingsGoal goal) async {
    await _database.db
        .update(_goals, goal.toMap(), where: 'id = ?', whereArgs: [goal.id]);
    _database.notifyChanged();
  }

  /// Removes an empty goal: deleted when it has no history, archived when it
  /// has (returns true). General Savings is never removed.
  Future<bool> removeGoal(SavingsGoal goal) async {
    if (goal.isGeneral) {
      throw ArgumentError('General Savings cannot be removed');
    }
    final archived = await _database.db.transaction((txn) async {
      final args = [goal.id];
      final balance = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COALESCE(SUM(amount), 0) FROM $_movements WHERE goal_id = ?',
              args)) ??
          0;
      if (balance != 0) throw GoalNotEmptyException(balance);
      final used = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM $_movements WHERE goal_id = ?', args)) ??
          0;
      if (used == 0) {
        await txn.delete(_goals, where: 'id = ?', whereArgs: args);
        return false;
      }
      await txn.update(_goals, {'is_archived': 1},
          where: 'id = ?', whereArgs: args);
      return true;
    });
    _database.notifyChanged();
    return archived;
  }

  /// Saves [movements] in one transaction. A withdrawal larger than its goal
  /// holds throws [InsufficientSavingsException] and nothing is saved.
  Future<void> addMovements(List<SavingsMovement> movements) async {
    await _database.db.transaction((txn) async {
      for (final movement in movements) {
        if (movement.amount < 0) {
          final held = Sqflite.firstIntValue(await txn.rawQuery(
                  'SELECT COALESCE(SUM(amount), 0) FROM $_movements WHERE goal_id = ?',
                  [movement.goalId])) ??
              0;
          if (held + movement.amount < 0) {
            throw InsufficientSavingsException(held);
          }
        }
        await txn.insert(_movements, movement.toMap()..remove('id'));
      }
    });
    _database.notifyChanged();
  }

  Future<void> addMovement(SavingsMovement movement) =>
      addMovements([movement]);

  Future<List<SavingsMovement>> getMovements(int goalId) async {
    final rows = await _database.db.query(_movements,
        where: 'goal_id = ?', whereArgs: [goalId], orderBy: 'date DESC, id DESC');
    return rows.map(SavingsMovement.fromMap).toList();
  }
}
```

- [ ] **Step 4: Run tests** — Run: `flutter test test/data` — Expected: PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add savings goals, balances and safe movements to the repository"`

---

### Task 4: Backup and restore service

**Files:**
- Create: `lib/app/data/providers/file_exchange_provider.dart`, `lib/app/services/backup_service.dart`, `test/helpers/fake_files.dart`
- Modify: `lib/app/bindings/initial_binding.dart` (register `FileExchangeProvider` and `BackupService`; new `files` parameter), `test/helpers/test_services.dart` (pass a `FakeFileExchangeProvider`)
- Test: `test/services/backup_service_test.dart`

**Interfaces:**
- Produces:
  - `abstract class FileExchangeProvider { Future<void> shareFile(String path, {required String subject}); Future<String?> pickJsonText(); Future<String> tempDirectory(); }`, `DeviceFileExchangeProvider`
  - `BackupFormatException(String message)`; `BackupSummary {exportedAt, transactionCount, goalCount, tables}`
  - `BackupService({required DatabaseService database, required SettingsService settings, required FileExchangeProvider files})`: `exportJson(DateTime now) → Future<String>`, `shareBackup(DateTime now)`, `parse(String) → BackupSummary`, `restore(BackupSummary)`
  - `InitialBinding.initServices({…, FileExchangeProvider? files})`; tests reach the fake with `Get.find<FileExchangeProvider>() as FakeFileExchangeProvider`.

- [ ] **Step 1: Write the fake, update the helper, write the failing test**

```dart
// file: test/helpers/fake_files.dart
import 'dart:io';

import 'package:calculator/app/data/providers/file_exchange_provider.dart';

/// Records shared files and returns a chosen text when asked to pick one.
class FakeFileExchangeProvider implements FileExchangeProvider {
  final shared = <String>[];
  String? textToPick;
  final _dir = Directory.systemTemp.createTempSync('masarifi_test');

  @override
  Future<void> shareFile(String path, {required String subject}) async =>
      shared.add(path);

  @override
  Future<String?> pickJsonText() async => textToPick;

  @override
  Future<String> tempDirectory() async => _dir.path;
}
```

In `test/helpers/test_services.dart`, import `fake_files.dart` and pass `files: FakeFileExchangeProvider()` to `InitialBinding.initServices`.

```dart
// file: test/services/backup_service_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/providers/file_exchange_provider.dart';
import 'package:calculator/app/data/repositories/budget_repository.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/services/backup_service.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../helpers/fake_files.dart';
import '../helpers/fixtures.dart';
import '../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  BackupService backup() => Get.find<BackupService>();
  TransactionRepository transactions() => Get.find<TransactionRepository>();

  Future<void> seed() async {
    await transactions().add(expense(5000, DateTime(2026, 10, 1), note: 'قهوة'));
    await Get.find<BudgetRepository>().setLimit(1, 200000);
    final goal = await Get.find<SavingsRepository>().addGoal(
        SavingsGoal(name: 'لابتوب', targetAmount: 900000, createdAt: DateTime(2026, 10, 1)));
    await Get.find<SavingsRepository>()
        .addMovement(saving(100000, DateTime(2026, 10, 2), goalId: goal.id!));
  }

  test('export then restore brings back exactly the same data', () async {
    await seed();
    final before = await transactions().getAll();
    final json = await backup().exportJson(DateTime(2026, 10, 4));

    await transactions().add(expense(9999, DateTime(2026, 10, 3)));
    await Get.find<BudgetRepository>().remove(1);

    final summary = backup().parse(json);
    expect(summary.transactionCount, 1);
    expect(summary.goalCount, 2);
    await backup().restore(summary);

    expect(await transactions().getAll(), before);
    expect((await Get.find<BudgetRepository>().getAll()).single.limitAmount, 200000);
    expect((await Get.find<SavingsRepository>().balances()).values, [100000]);
  });

  test('a file that is not a backup is rejected', () {
    expect(() => backup().parse('hello'), throwsA(isA<BackupFormatException>()));
    expect(() => backup().parse(jsonEncode({'format': 'other'})),
        throwsA(isA<BackupFormatException>()));
  });

  test('a backup from a newer app version is rejected', () async {
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, Object?>;
    data['schemaVersion'] = 99;
    expect(
      () => backup().parse(jsonEncode(data)),
      throwsA(isA<BackupFormatException>().having(
          (e) => e.message, 'message', contains('أحدث'))),
    );
  });

  test('a backup without exactly one settings row is rejected', () async {
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    (data['tables'] as Map<String, dynamic>)['settings'] = [];
    expect(() => backup().parse(jsonEncode(data)), throwsA(isA<BackupFormatException>()));
  });

  test('a restore that fails half-way leaves the current data untouched', () async {
    await seed();
    final data = jsonDecode(await backup().exportJson(DateTime(2026, 10, 4)))
        as Map<String, dynamic>;
    final rows = (data['tables'] as Map<String, dynamic>)['transactions'] as List;
    (rows.first as Map<String, dynamic>)['category_id'] = 999;
    final summary = backup().parse(jsonEncode(data));

    final before = await transactions().getAll();
    await expectLater(backup().restore(summary), throwsA(anything));
    expect(await transactions().getAll(), before);
  });

  test('shareBackup writes the file, opens sharing and records the time', () async {
    await seed();
    await backup().shareBackup(DateTime(2026, 10, 4, 9));
    final fake = Get.find<FileExchangeProvider>() as FakeFileExchangeProvider;
    expect(fake.shared.single, endsWith('masarifi-backup-2026-10-04.json'));
    expect(jsonDecode(File(fake.shared.single).readAsStringSync())['format'],
        'masarifi-backup');
    expect(Get.find<SettingsService>().settings.value.lastBackupAt,
        DateTime(2026, 10, 4, 9));
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — Run: `flutter test test/services/backup_service_test.dart` — Expected: FAIL (files not found).

- [ ] **Step 3: Implement**

```dart
// file: lib/app/data/providers/file_exchange_provider.dart
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Moving files in and out of the app. An interface so tests can use a fake.
abstract class FileExchangeProvider {
  /// Opens the system share sheet (Files, Drive, email…) for [path].
  Future<void> shareFile(String path, {required String subject});

  /// Lets the user pick a JSON file; returns its text, or null if cancelled.
  Future<String?> pickJsonText();

  /// A folder for temporary files.
  Future<String> tempDirectory();
}

/// [FileExchangeProvider] using the device's share sheet and file picker.
/// The app itself never uploads anything.
class DeviceFileExchangeProvider implements FileExchangeProvider {
  @override
  Future<void> shareFile(String path, {required String subject}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'application/json')],
      subject: subject,
    ));
  }

  @override
  Future<String?> pickJsonText() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return null;
    return utf8.decode(await files.first.readAsBytes());
  }

  @override
  Future<String> tempDirectory() async => (await getTemporaryDirectory()).path;
}
```

```dart
// file: lib/app/services/backup_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../core/utils/date_utils.dart';
import '../data/providers/app_database.dart';
import '../data/providers/file_exchange_provider.dart';
import 'database_service.dart';
import 'settings_service.dart';

/// The chosen file cannot be restored; [message] is shown to the user.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;
}

/// A parsed backup, ready to confirm and restore.
class BackupSummary {
  const BackupSummary({
    required this.exportedAt,
    required this.transactionCount,
    required this.goalCount,
    required this.tables,
  });

  final DateTime exportedAt;
  final int transactionCount;
  final int goalCount;
  final Map<String, List<Map<String, Object?>>> tables;
}

/// Export to and restore from one JSON file (spec §6.8).
class BackupService extends GetxService {
  BackupService({
    required this.database,
    required this.settings,
    required this.files,
  });

  final DatabaseService database;
  final SettingsService settings;
  final FileExchangeProvider files;

  static const format = 'masarifi-backup';

  /// Every table, parents before children (the restore insert order).
  static const tables = [
    'categories',
    'savings_goals',
    'recurring_rules',
    'transactions',
    'budgets',
    'savings_movements',
    'quick_templates',
    'budget_alerts_sent',
    'settings',
  ];

  static const _notABackup = 'الملف مش نسخة احتياطية من مصاريفي';

  Future<String> exportJson(DateTime now) async {
    final data = <String, Object?>{};
    for (final table in tables) {
      data[table] = await database.db.query(table);
    }
    return jsonEncode({
      'format': format,
      'schemaVersion': AppDatabase.version,
      'exportedAt': now.toIso8601String(),
      'tables': data,
    });
  }

  /// Writes today's backup file, opens the share sheet and records the time.
  Future<void> shareBackup(DateTime now) async {
    final folder = await files.tempDirectory();
    final path =
        p.join(folder, 'masarifi-backup-${DateKeys.fromDate(now)}.json');
    await File(path).writeAsString(await exportJson(now));
    await files.shareFile(path, subject: 'نسخة احتياطية — مصاريفي');
    await settings.update(settings.settings.value.copyWith(lastBackupAt: now));
  }

  /// Checks [text] and returns what it contains, or throws
  /// [BackupFormatException] with a message for the user.
  BackupSummary parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const BackupFormatException(_notABackup);
    }
    if (decoded is! Map || decoded['format'] != format) {
      throw const BackupFormatException(_notABackup);
    }
    final version = decoded['schemaVersion'];
    if (version is! int) throw const BackupFormatException(_notABackup);
    if (version > AppDatabase.version) {
      throw const BackupFormatException(
          'النسخة من إصدار أحدث للتطبيق. حدّث التطبيق أول');
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map) throw const BackupFormatException(_notABackup);

    final parsed = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final rows = rawTables[table];
      if (rows is! List) throw const BackupFormatException(_notABackup);
      final list = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row is! Map) throw const BackupFormatException(_notABackup);
        list.add(Map<String, Object?>.from(row));
      }
      parsed[table] = list;
    }
    if (parsed['settings']!.length != 1) {
      throw const BackupFormatException(_notABackup);
    }
    final exportedAt = decoded['exportedAt'];
    return BackupSummary(
      exportedAt: (exportedAt is String ? DateTime.tryParse(exportedAt) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      transactionCount: parsed['transactions']!.length,
      goalCount: parsed['savings_goals']!.length,
      tables: parsed,
    );
  }

  /// Replaces all data with [backup] in one transaction: if anything fails,
  /// the current data stays exactly as it was.
  Future<void> restore(BackupSummary backup) async {
    await database.db.transaction((txn) async {
      for (final table in tables.reversed) {
        await txn.delete(table);
      }
      for (final table in tables) {
        for (final row in backup.tables[table]!) {
          await txn.insert(table, row);
        }
      }
    });
    await settings.init();
    database.notifyChanged();
  }
}
```

`initial_binding.dart`: add imports for `file_exchange_provider.dart` and `backup_service.dart`, the parameter `FileExchangeProvider? files`, and after the `StartupService` registration:

```dart
    final fileExchange = Get.put<FileExchangeProvider>(
        files ?? DeviceFileExchangeProvider(),
        permanent: true);
    Get.put(
      BackupService(database: database, settings: settings, files: fileExchange),
      permanent: true,
    );
```

- [ ] **Step 4: Run tests** — Run: `flutter test test/services && flutter test` — Expected: PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add JSON backup and atomic restore"`

---

### Task 5: Shared amount dialog, routes and the reports tab

**Files:**
- Create: `lib/app/widgets/amount_dialog.dart`
- Delete: `lib/app/modules/budgets/widgets/budget_limit_dialog.dart` (replaced)
- Modify: `lib/app/modules/budgets/views/budgets_view.dart` (use `AmountDialog`), `lib/app/routes/app_routes.dart`, `lib/app/widgets/app_bottom_nav.dart`
- Test: `test/widgets/amount_dialog_test.dart`

**Interfaces:**
- Produces: `sealed class AmountDialogResult`, `SaveAmount(String text)`, `RemoveAmount()`; `AmountDialog({required String title, required Currency currency, int? initialAmount, String? removeLabel})`; `Routes.reports`, `Routes.savings`, `Routes.goalForm`, `Routes.goalDetail`, `Routes.monthEnd`; five bottom tabs.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/widgets/amount_dialog_test.dart
import 'package:calculator/app/core/utils/currencies.dart';
import 'package:calculator/app/widgets/amount_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AmountDialogResult?> open(WidgetTester tester, {String? removeLabel, int? initial}) async {
    AmountDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<AmountDialogResult>(
            context: context,
            builder: (_) => AmountDialog(
              title: 'إضافة للهدف',
              currency: Currencies.jod,
              initialAmount: initial,
              removeLabel: removeLabel,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('returns the typed text and closes cleanly', (tester) async {
    AmountDialogResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<AmountDialogResult>(
            context: context,
            builder: (_) =>
                const AmountDialog(title: 'إضافة', currency: Currencies.jod),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '25');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((result as SaveAmount).text, '25');
  });

  testWidgets('shows the current amount and an optional remove action', (tester) async {
    await open(tester, initial: 12500, removeLabel: 'حذف');
    expect(find.text('12.5'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
  });

  testWidgets('no remove action unless asked', (tester) async {
    await open(tester);
    expect(find.text('حذف'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — Run: `flutter test test/widgets/amount_dialog_test.dart` — Expected: FAIL (file not found).

- [ ] **Step 3: Implement**

```dart
// file: lib/app/widgets/amount_dialog.dart
import 'package:flutter/material.dart';

import '../core/utils/currencies.dart';
import '../core/utils/money.dart';

/// What the user chose in [AmountDialog].
sealed class AmountDialogResult {
  const AmountDialogResult();
}

class SaveAmount extends AmountDialogResult {
  const SaveAmount(this.text);

  final String text;
}

class RemoveAmount extends AmountDialogResult {
  const RemoveAmount();
}

/// Asks for an amount. It owns its text controller, so the controller is
/// disposed only after the dialog has finished closing.
class AmountDialog extends StatefulWidget {
  const AmountDialog({
    super.key,
    required this.title,
    required this.currency,
    this.initialAmount,
    this.removeLabel,
  });

  final String title;
  final Currency currency;
  final int? initialAmount;

  /// Shows a remove action with this label when not null.
  final String? removeLabel;

  @override
  State<AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<AmountDialog> {
  late final _input = TextEditingController(
      text: widget.initialAmount == null
          ? ''
          : Money.toEditable(widget.initialAmount!));

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _input,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: 'المبلغ',
          suffixText: widget.currency.symbol,
        ),
      ),
      actions: [
        if (widget.removeLabel != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const RemoveAmount()),
            child: Text(widget.removeLabel!),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(context, SaveAmount(_input.text)),
            child: const Text('حفظ')),
      ],
    );
  }
}
```

In `budgets_view.dart`: import `../../../widgets/amount_dialog.dart` instead of `../widgets/budget_limit_dialog.dart`, and in `_editLimit` show

```dart
    final result = await showDialog<AmountDialogResult>(
      context: context,
      builder: (context) => AmountDialog(
        title: 'ميزانية ${category.name} الشهرية',
        currency: controller.currency,
        initialAmount: current?.limit,
        removeLabel: current == null ? null : 'حذف الميزانية',
      ),
    );
    switch (result) {
      case RemoveAmount():
        await controller.removeLimit(category.id!);
      case SaveAmount(:final text):
        final saved = await controller.setLimit(category.id!, text);
        if (!saved && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('اكتب مبلغ أكبر من صفر')));
        }
      case null:
        break;
    }
```

then `git rm lib/app/modules/budgets/widgets/budget_limit_dialog.dart`.

```dart
// file: lib/app/routes/app_routes.dart
abstract final class Routes {
  static const home = '/home';
  static const transactionForm = '/transaction-form';
  static const transactions = '/transactions';
  static const reports = '/reports';
  static const budgets = '/budgets';
  static const recurring = '/recurring';
  static const recurringForm = '/recurring-form';
  static const templates = '/templates';
  static const savings = '/savings';
  static const goalForm = '/goal-form';
  static const goalDetail = '/goal-detail';
  static const monthEnd = '/month-end';
  static const settings = '/settings';
}
```

In `app_bottom_nav.dart`, add after the transactions tab:

```dart
    (Routes.reports, Icons.pie_chart_outline, Icons.pie_chart, 'التقارير'),
```

- [ ] **Step 4: Run tests** — Run: `flutter analyze && flutter test` — Expected: no issues, PASS (the Phase 2 budget-dialog e2e test still passes through `AmountDialog`).
- [ ] **Step 5: Commit** — `git add -A && git commit -m "refactor: share one amount dialog; add phase 3 routes and the reports tab"`

---

### Task 6: Savings screens — list, goal form, goal detail

**Files:**
- Create: `lib/app/modules/savings/{bindings/savings_binding.dart, controllers/savings_controller.dart, views/savings_view.dart, widgets/goal_card.dart}`, `lib/app/modules/goal_form/{bindings/goal_form_binding.dart, controllers/goal_form_controller.dart, views/goal_form_view.dart}`, `lib/app/modules/goal_detail/{bindings/goal_detail_binding.dart, controllers/goal_detail_controller.dart, views/goal_detail_view.dart}`
- Modify: `lib/app/routes/app_pages.dart` (savings, goalForm, goalDetail)
- Test: `test/modules/savings/savings_controller_test.dart`, `test/modules/goal_form/goal_form_controller_test.dart`, `test/modules/goal_detail/goal_detail_controller_test.dart`

**Interfaces:**
- Produces:
  - `SavingsController({required SavingsRepository savings, required SettingsService settings, required DatabaseService database, DateTime Function()? clock})`: `goals` (`RxList<GoalProgress>`), `total` (`RxInt`), `currency`, `load()`, `monthlyNeeded(GoalProgress) → int?`, `openGoal(GoalProgress)`, `openAddGoal()`
  - `GoalFormController({required SavingsRepository savings, required SettingsService settings, int? editId})`: `ready`, `nameController`, `targetController`, `targetDate` (`Rxn<DateTime>`), `isEditing`, `canSave`, `setTargetDate(DateTime?)`, `save() → Future<bool>`, `remove() → Future<bool>`
  - `GoalDetailController({required SavingsRepository savings, required SettingsService settings, required DatabaseService database, required int goalId, DateTime Function()? clock})`: `goal` (`Rxn<SavingsGoal>`), `saved` (`RxInt`), `movements`, `currency`, `load()`, `deposit(String text) → Future<bool>`, `withdraw(String text) → Future<bool>`, `openEdit()`

- [ ] **Step 1: Write the failing tests**

```dart
// file: test/modules/savings/savings_controller_test.dart
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/modules/savings/controllers/savings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  test('lists General Savings and goals with what each holds and the total', () async {
    final repo = Get.find<SavingsRepository>();
    final goal = await repo.addGoal(SavingsGoal(
      name: 'لابتوب',
      targetAmount: 900000,
      targetDate: DateTime(2027, 3, 10),
      createdAt: DateTime(2026, 10, 1),
    ));
    await repo.addMovement(saving(540000, DateTime(2026, 10, 1), goalId: goal.id!));
    await repo.addMovement(saving(20000, DateTime(2026, 10, 1)));

    final c = Get.put(SavingsController(
      savings: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => DateTime(2026, 10, 4),
    ));
    await c.load();
    expect(c.goals.map((g) => g.goal.name), ['ادخار عام', 'لابتوب']);
    expect(c.goals.last.saved, 540000);
    expect(c.total.value, 560000);
    expect(c.monthlyNeeded(c.goals.last), 60000);
    expect(c.monthlyNeeded(c.goals.first), isNull);
  });
}
```

```dart
// file: test/modules/goal_form/goal_form_controller_test.dart
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/modules/goal_form/controllers/goal_form_controller.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<GoalFormController> open({int? editId}) async {
    final c = Get.put(GoalFormController(
        savings: Get.find(), settings: Get.find(), editId: editId));
    await c.ready;
    return c;
  }

  test('a name is required; the target is optional but must be valid', () async {
    final c = await open();
    expect(c.canSave, isFalse);
    c.nameController.text = 'سفرة';
    expect(c.canSave, isTrue);
    c.targetController.text = 'abc';
    expect(c.canSave, isFalse);
    c.targetController.text = '1000';
    expect(c.canSave, isTrue);
  });

  test('creates a goal with a target and a date', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    c.targetController.text = '1000';
    c.setTargetDate(DateTime(2027, 6, 1));
    expect(await c.save(), isTrue);
    final goal = (await Get.find<SavingsRepository>().getGoals()).last;
    expect(goal.name, 'سفرة');
    expect(goal.targetAmount, 1000000);
    expect(goal.targetDate, DateTime(2027, 6, 1));
  });

  test('editing keeps the id and can clear the target', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    c.targetController.text = '1000';
    await c.save();
    final id = (await Get.find<SavingsRepository>().getGoals()).last.id;
    Get.delete<GoalFormController>();

    final edit = await open(editId: id);
    expect(edit.nameController.text, 'سفرة');
    expect(edit.targetController.text, '1000');
    edit.targetController.text = '';
    await edit.save();
    final goal = await Get.find<SavingsRepository>().getGoal(id!);
    expect(goal!.targetAmount, isNull);
  });

  test('a goal that still holds money cannot be removed', () async {
    final c = await open();
    c.nameController.text = 'سفرة';
    await c.save();
    final goal = (await Get.find<SavingsRepository>().getGoals()).last;
    await Get.find<SavingsRepository>()
        .addMovement(saving(1000, DateTime(2026, 10, 1), goalId: goal.id!));
    Get.delete<GoalFormController>();

    final edit = await open(editId: goal.id);
    expect(await edit.remove(), isFalse);
    expect(Get.find<MessageService>().lastMessage.value, contains('اسحب'));
  });
}
```

```dart
// file: test/modules/goal_detail/goal_detail_controller_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/modules/goal_detail/controllers/goal_detail_controller.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<GoalDetailController> open() async {
    final c = Get.put(GoalDetailController(
      savings: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      goalId: 1,
      clock: () => DateTime(2026, 10, 4),
    ));
    await c.load();
    return c;
  }

  test('deposit and withdraw move money in and out of the goal', () async {
    final c = await open();
    expect(c.goal.value!.name, 'ادخار عام');
    expect(await c.deposit('100'), isTrue);
    expect(await c.withdraw('40'), isTrue);
    await settle();
    expect(c.saved.value, 60000);
    expect(c.movements.map((m) => m.amount), [-40000, 100000]);
    expect(c.movements.every((m) => m.source == SavingsSource.manual), isTrue);
    expect(c.movements.first.date, DateTime(2026, 10, 4));
  });

  test('withdrawing more than the goal holds is refused with a message', () async {
    final c = await open();
    await c.deposit('10');
    expect(await c.withdraw('25'), isFalse);
    expect(Get.find<MessageService>().lastMessage.value, contains('10.000'));
    expect((await Get.find<SavingsRepository>().balances())[1], 10000);
  });

  test('invalid amounts are refused', () async {
    final c = await open();
    expect(await c.deposit('0'), isFalse);
    expect(await c.withdraw('abc'), isFalse);
    expect(await Get.find<SavingsRepository>().getAllMovements(), isEmpty);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail** — Run: `flutter test test/modules/savings test/modules/goal_form test/modules/goal_detail` — Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/modules/savings/controllers/savings_controller.dart
import 'package:get/get.dart';

import '../../../core/logic/goal_projection.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class SavingsController extends GetxController {
  SavingsController({
    required this.savings,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SavingsRepository savings;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final goals = <GoalProgress>[].obs;
  final total = 0.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final balances = await savings.balances();
    final list = await savings.getGoals();
    goals.assignAll([
      for (final goal in list) GoalProgress(goal: goal, saved: balances[goal.id] ?? 0),
    ]);
    total.value = balances.values.fold(0, (a, b) => a + b);
  }

  int? monthlyNeeded(GoalProgress progress) => GoalProjection.monthlyNeeded(
      progress, settings.currentPeriod(_clock()));

  void openGoal(GoalProgress progress) =>
      Get.toNamed(Routes.goalDetail, arguments: progress.goal.id);

  void openAddGoal() => Get.toNamed(Routes.goalForm);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/savings/bindings/savings_binding.dart
import 'package:get/get.dart';

import '../controllers/savings_controller.dart';

class SavingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => SavingsController(
          savings: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/savings/widgets/goal_card.dart
import 'package:flutter/material.dart';

import '../../../core/logic/goal_projection.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../widgets/money_text.dart';

/// One savings pot: what it holds, its target and what to save each month.
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.progress,
    required this.currency,
    required this.monthlyNeeded,
    required this.onTap,
  });

  final GoalProgress progress;
  final Currency currency;
  final int? monthlyNeeded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final goal = progress.goal;
    final target = progress.target;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(goal.isGeneral ? Icons.savings_outlined : Icons.flag_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(goal.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  MoneyText(progress.saved,
                      currency: currency,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              if (target != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 8,
                    color: AppColors.primary,
                    backgroundColor: AppColors.divider,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress.isReached
                      ? 'وصلت للهدف'
                      : '${progress.percent}% من ${MoneyText.label(target, currency)}'
                          '${goal.targetDate == null ? '' : ' · قبل ${ArabicDates.dayMonth(goal.targetDate!)} ${goal.targetDate!.year}'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
              if (monthlyNeeded != null) ...[
                const SizedBox(height: 4),
                Text('وفّر ${MoneyText.label(monthlyNeeded!, currency)} بالشهر لتوصل',
                    style: const TextStyle(color: AppColors.primary, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/savings/views/savings_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/money_text.dart';
import '../controllers/savings_controller.dart';
import '../widgets/goal_card.dart';

class SavingsView extends GetView<SavingsController> {
  const SavingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المدخرات')),
      body: Obx(() {
        final goals = controller.goals.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('مجموع المدخرات',
                      style: TextStyle(color: AppColors.onPrimaryMuted, fontSize: 13)),
                  const SizedBox(height: 4),
                  MoneyText(controller.total.value,
                      currency: controller.currency,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final goal in goals) ...[
              GoalCard(
                progress: goal,
                currency: controller.currency,
                monthlyNeeded: controller.monthlyNeeded(goal),
                onTap: () => controller.openGoal(goal),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      }),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.openAddGoal,
        icon: const Icon(Icons.add),
        label: const Text('هدف جديد'),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/goal_form/controllers/goal_form_controller.dart
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/savings_goal.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Create a savings goal, or edit/remove the one with [editId].
class GoalFormController extends GetxController {
  GoalFormController({
    required this.savings,
    required this.settings,
    this.editId,
  });

  final SavingsRepository savings;
  final SettingsService settings;
  final int? editId;

  final nameController = TextEditingController();
  final targetController = TextEditingController();
  final _name = ''.obs;
  final _target = ''.obs;
  final targetDate = Rxn<DateTime>();
  final isEditing = false.obs;

  SavingsGoal? _editing;
  late final Future<void> ready;

  Currency get currency => settings.currency;

  int? get _targetAmount => Money.parse(_target.value, decimals: 3);

  bool get canSave =>
      _name.value.trim().isNotEmpty &&
      (_target.value.trim().isEmpty || _targetAmount != null);

  @override
  void onInit() {
    super.onInit();
    nameController.addListener(() => _name.value = nameController.text);
    targetController.addListener(() => _target.value = targetController.text);
    ready = _load();
  }

  Future<void> _load() async {
    if (editId == null) return;
    final goal = await savings.getGoal(editId!);
    if (goal == null) return;
    _editing = goal;
    isEditing.value = true;
    nameController.text = goal.name;
    targetController.text =
        goal.targetAmount == null ? '' : Money.toEditable(goal.targetAmount!);
    targetDate.value = goal.targetDate;
  }

  void setTargetDate(DateTime? value) =>
      targetDate.value = value == null ? null : DateKeys.dateOnly(value);

  Future<bool> save() async {
    if (!canSave) return false;
    final goal = SavingsGoal(
      id: _editing?.id,
      name: _name.value.trim(),
      targetAmount: _targetAmount,
      targetDate: targetDate.value,
      isGeneral: _editing?.isGeneral ?? false,
      createdAt: _editing?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch),
    );
    try {
      if (_editing == null) {
        await savings.addGoal(goal);
      } else {
        await savings.updateGoal(goal);
      }
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الهدف');
      return false;
    }
  }

  /// Removes the edited goal; refused (with a message) while it holds money.
  Future<bool> remove() async {
    final goal = _editing;
    if (goal == null || goal.isGeneral) return false;
    try {
      await savings.removeGoal(goal);
      return true;
    } on GoalNotEmptyException catch (e) {
      Get.find<MessageService>().showError(
          'اسحب المبلغ من الهدف أول (فيه ${Money.format(e.balance, decimals: currency.decimals)})');
      return false;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف الهدف');
      return false;
    }
  }

  @override
  void onClose() {
    nameController.dispose();
    targetController.dispose();
    super.onClose();
  }
}
```

Note: the target is parsed with 3 decimals so any typed amount is kept exactly; a 2-decimal currency only limits how it is shown.

```dart
// file: lib/app/modules/goal_form/bindings/goal_form_binding.dart
import 'package:get/get.dart';

import '../controllers/goal_form_controller.dart';

class GoalFormBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments;
    Get.lazyPut(() => GoalFormController(
          savings: Get.find(),
          settings: Get.find(),
          editId: args is int ? args : null,
        ));
  }
}
```

```dart
// file: lib/app/modules/goal_form/views/goal_form_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/date_utils.dart';
import '../controllers/goal_form_controller.dart';

class GoalFormView extends GetView<GoalFormController> {
  const GoalFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.isEditing.value ? 'تعديل الهدف' : 'هدف جديد')),
        actions: [
          Obx(() => controller.isEditing.value
              ? IconButton(
                  tooltip: 'حذف الهدف',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _remove,
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: controller.nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الهدف',
                hintText: 'مثلاً لابتوب أو سفرة',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller.targetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'المبلغ المطلوب (اختياري)',
                suffixText: controller.currency.symbol,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Obx(() {
              final date = controller.targetDate.value;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('بدّي أوصل قبل'),
                subtitle: Text(date == null
                    ? 'بدون تاريخ'
                    : '${ArabicDates.dayMonth(date)} ${date.year}'),
                trailing: date == null
                    ? null
                    : IconButton(
                        tooltip: 'شيل التاريخ',
                        icon: const Icon(Icons.close),
                        onPressed: () => controller.setTargetDate(null),
                      ),
                onTap: () => _pickDate(context),
              );
            }),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: Listenable.merge(
                  [controller.nameController, controller.targetController]),
              builder: (context, _) => FilledButton(
                onPressed: controller.canSave ? _save : null,
                child: const Text('حفظ'),
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

  Future<void> _remove() async {
    if (await controller.remove()) Get.back();
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: controller.targetDate.value ?? DateTime(now.year + 1, now.month, 1),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) controller.setTargetDate(picked);
  }
}
```

```dart
// file: lib/app/modules/goal_detail/controllers/goal_detail_controller.dart
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/savings_goal.dart';
import '../../../data/models/savings_movement.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class GoalDetailController extends GetxController {
  GoalDetailController({
    required this.savings,
    required this.settings,
    required this.database,
    required this.goalId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SavingsRepository savings;
  final SettingsService settings;
  final DatabaseService database;
  final int goalId;
  final DateTime Function() _clock;

  final goal = Rxn<SavingsGoal>();
  final saved = 0.obs;
  final movements = <SavingsMovement>[].obs;

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
    goal.value = await savings.getGoal(goalId);
    saved.value = (await savings.balances())[goalId] ?? 0;
    movements.assignAll(await savings.getMovements(goalId));
  }

  Future<bool> deposit(String text) => _move(text, 1);

  Future<bool> withdraw(String text) => _move(text, -1);

  Future<bool> _move(String text, int sign) async {
    final amount = Money.parse(text, decimals: 3);
    if (amount == null) return false;
    try {
      await savings.addMovement(SavingsMovement(
        goalId: goalId,
        amount: sign * amount,
        date: DateKeys.dateOnly(_clock()),
        source: SavingsSource.manual,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            DateTime.now().millisecondsSinceEpoch),
      ));
      return true;
    } on InsufficientSavingsException catch (e) {
      Get.find<MessageService>().showError(
          'بالهدف بس ${Money.format(e.available, decimals: currency.decimals)}');
      return false;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ الحركة');
      return false;
    }
  }

  void openEdit() => Get.toNamed(Routes.goalForm, arguments: goalId);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/goal_detail/bindings/goal_detail_binding.dart
import 'package:get/get.dart';

import '../controllers/goal_detail_controller.dart';

class GoalDetailBinding extends Bindings {
  @override
  void dependencies() {
    final goalId = Get.arguments as int;
    Get.lazyPut(() => GoalDetailController(
          savings: Get.find(),
          settings: Get.find(),
          database: Get.find(),
          goalId: goalId,
        ));
  }
}
```

```dart
// file: lib/app/modules/goal_detail/views/goal_detail_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/enums.dart';
import '../../../widgets/amount_dialog.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/money_text.dart';
import '../controllers/goal_detail_controller.dart';

class GoalDetailView extends GetView<GoalDetailController> {
  const GoalDetailView({super.key});

  static const _sourceLabels = {
    SavingsSource.manual: 'يدوي',
    SavingsSource.monthEnd: 'من آخر الشهر',
    SavingsSource.recurring: 'تلقائي',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.goal.value?.name ?? '')),
        actions: [
          Obx(() => controller.goal.value?.isGeneral ?? true
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'تعديل الهدف',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: controller.openEdit,
                )),
        ],
      ),
      body: Obx(() {
        final goal = controller.goal.value;
        if (goal == null) return const Center(child: CircularProgressIndicator());
        final movements = controller.movements.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Center(
              child: Column(
                children: [
                  const Text('بالهدف هلأ',
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  MoneyText(controller.saved.value,
                      currency: controller.currency,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700)),
                  if (goal.targetAmount != null)
                    Text('من ${MoneyText.label(goal.targetAmount!, controller.currency)}',
                        style: const TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _ask(context, 'إضافة للهدف', controller.deposit),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    onPressed: () => _ask(context, 'سحب من الهدف', controller.withdraw),
                    icon: const Icon(Icons.remove),
                    label: const Text('سحب'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('الحركات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (movements.isEmpty)
              const EmptyState(icon: Icons.history, message: 'ما في حركات لسا')
            else
              Card(
                child: Column(
                  children: [
                    for (final (index, m) in movements.indexed) ...[
                      if (index > 0) const Divider(indent: 16, endIndent: 16),
                      ListTile(
                        title: Text(_sourceLabels[m.source]!),
                        subtitle: Text(
                            ArabicDates.relativeDay(m.date, today: controller.today)),
                        trailing: MoneyText(m.amount,
                            currency: controller.currency,
                            showPlus: true,
                            showSymbol: false,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: m.amount > 0 ? AppColors.income : AppColors.expense,
                            )),
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

  Future<void> _ask(
    BuildContext context,
    String title,
    Future<bool> Function(String text) action,
  ) async {
    final result = await showDialog<AmountDialogResult>(
      context: context,
      builder: (_) => AmountDialog(title: title, currency: controller.currency),
    );
    if (result is SaveAmount) await action(result.text);
  }
}
```

Add to `app_pages.dart` (imports + pages):

```dart
    GetPage(name: Routes.savings, page: () => const SavingsView(), binding: SavingsBinding()),
    GetPage(name: Routes.goalForm, page: () => const GoalFormView(), binding: GoalFormBinding(), fullscreenDialog: true),
    GetPage(name: Routes.goalDetail, page: () => const GoalDetailView(), binding: GoalDetailBinding()),
```

- [ ] **Step 4: Run tests** — Run: `flutter analyze && flutter test test/modules` — Expected: no issues, PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add savings screens with goals, add/withdraw and projections"`

---

### Task 7: Month-end leftover prompt and Home totals

**Files:**
- Create: `lib/app/modules/home/widgets/month_end_banner.dart`, `lib/app/modules/month_end/{bindings/month_end_binding.dart, controllers/month_end_controller.dart, views/month_end_view.dart}`
- Modify: `lib/app/modules/home/controllers/home_controller.dart`, `lib/app/modules/home/views/home_view.dart`, `lib/app/modules/home/widgets/balance_card.dart`, `lib/app/routes/app_pages.dart`
- Test: `test/modules/month_end/month_end_test.dart`

**Interfaces:**
- Produces:
  - `HomeController.monthEndOffer` (`RxnInt`), `skipMonthEnd()`, `openMonthEnd()`, `openSavings()`
  - `BalanceCard({required BalanceSummary summary, required Currency currency, VoidCallback? onSavingsTap})` shows "مجموع المدخرات" and "الكلي معك"
  - `MonthEndController({required SavingsRepository savings, required TransactionRepository transactions, required SettingsService settings, DateTime Function()? clock})`: `ready`, `offered` (`RxInt`), `goals` (`RxList<SavingsGoal>`), `controllerFor(int goalId) → TextEditingController`, `allocated` (`RxInt`), `canSave`, `putAllInGeneral()`, `save() → Future<bool>`, `skip() → Future<void>`

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/month_end/month_end_test.dart
import 'package:calculator/app/data/models/enums.dart';
import 'package:calculator/app/data/models/savings_goal.dart';
import 'package:calculator/app/data/repositories/savings_repository.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/home/controllers/home_controller.dart';
import 'package:calculator/app/modules/month_end/controllers/month_end_controller.dart';
import 'package:calculator/app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  final today = DateTime(2026, 10, 4);

  setUp(() async {
    await setUpTestServices();
    final repo = Get.find<TransactionRepository>();
    await repo.add(income(1250000, DateTime(2026, 9, 1)));
    await repo.add(expense(750000, DateTime(2026, 9, 10)));
  });

  Future<HomeController> openHome() async {
    final c = Get.put(HomeController(
      transactions: Get.find(),
      categories: Get.find(),
      savings: Get.find(),
      templates: Get.find(),
      budgets: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => today,
    ));
    await c.load();
    return c;
  }

  Future<MonthEndController> openMonthEnd() async {
    final c = Get.put(MonthEndController(
      savings: Get.find(),
      transactions: Get.find(),
      settings: Get.find(),
      clock: () => today,
    ));
    await c.ready;
    return c;
  }

  test('Home offers last period\'s leftover, and Skip hides it for good', () async {
    final home = await openHome();
    expect(home.monthEndOffer.value, 500000);
    await home.skipMonthEnd();
    await settle();
    expect(home.monthEndOffer.value, isNull);
    expect(Get.find<SettingsService>().settings.value.lastMonthEndPromptPeriod, '2026-09');
  });

  test('Home shows total savings and the grand total', () async {
    await Get.find<SavingsRepository>().addMovement(saving(100000, DateTime(2026, 10, 2)));
    final home = await openHome();
    expect(home.summary.value!.totalSavings, 100000);
    expect(home.summary.value!.total, 500000);
  });

  test('splitting the leftover across goals saves it in one step', () async {
    final laptop = await Get.find<SavingsRepository>().addGoal(
        SavingsGoal(name: 'لابتوب', createdAt: DateTime(2026, 10, 1)));
    final c = await openMonthEnd();
    expect(c.offered.value, 500000);
    expect(c.goals.map((g) => g.name), ['ادخار عام', 'لابتوب']);

    c.controllerFor(laptop.id!).text = '100';
    c.controllerFor(1).text = '50';
    expect(c.allocated.value, 150000);
    expect(await c.save(), isTrue);

    final movements = await Get.find<SavingsRepository>().getAllMovements();
    expect(movements.map((m) => m.amount).toSet(), {100000, 50000});
    expect(movements.every((m) => m.source == SavingsSource.monthEnd && m.date == today), isTrue);
    expect(Get.find<SettingsService>().settings.value.lastMonthEndPromptPeriod, '2026-09');
  });

  test('more than the leftover cannot be saved', () async {
    final c = await openMonthEnd();
    c.controllerFor(1).text = '600';
    expect(c.canSave, isFalse);
    expect(await c.save(), isFalse);
    expect(await Get.find<SavingsRepository>().getAllMovements(), isEmpty);
  });

  test('"all to General Savings" fills in the whole leftover', () async {
    final c = await openMonthEnd();
    c.putAllInGeneral();
    expect(c.allocated.value, 500000);
    expect(c.canSave, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — Run: `flutter test test/modules/month_end` — Expected: FAIL.

- [ ] **Step 3: Implement**

`home_controller.dart`: import `../../../core/logic/month_end_check.dart`; add `final monthEndOffer = RxnInt();`; at the end of `load()`:

```dart
    monthEndOffer.value = MonthEndCheck.leftoverToOffer(
      current: current,
      lastPromptedKey: settings.settings.value.lastMonthEndPromptPeriod,
      transactions: all,
      movements: movements,
    );
```

and the methods:

```dart
  /// Answers "not now" for last period's leftover; it is not offered again.
  Future<void> skipMonthEnd() async {
    final previous = settings.currentPeriod(_clock()).previous;
    try {
      await settings.update(settings.settings.value
          .copyWith(lastMonthEndPromptPeriod: previous.key));
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ اختيارك');
    }
  }

  void openMonthEnd() => Get.toNamed(Routes.monthEnd);

  void openSavings() => Get.toNamed(Routes.savings);
```

`balance_card.dart` — full replacement (adds the savings row, keeps the rest):

```dart
// file: lib/app/modules/home/widgets/balance_card.dart
import 'package:flutter/material.dart';

import '../../../core/logic/balance_calculator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// "Remaining from salary" with this period's breakdown, total savings and
/// everything the user has (spec §6.3).
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.summary,
    required this.currency,
    this.onSavingsTap,
  });

  final BalanceSummary summary;
  final Currency currency;
  final VoidCallback? onSavingsTap;

  @override
  Widget build(BuildContext context) {
    String label(int amount) =>
        MoneyText.label(amount, currency, showSymbol: false);
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
              color: summary.remaining < 0 ? AppColors.negativeOnDark : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'دخل ${label(summary.income)} · مصاريف ${label(summary.expenses)}'
            '${summary.saved == 0 ? '' : ' · للادخار ${label(summary.saved)}'}'
            '${summary.carriedOver == 0 ? '' : ' · مرحّل ${label(summary.carriedOver)}'}',
            style: const TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'مجموع المدخرات',
                  amount: summary.totalSavings,
                  currency: currency,
                  onTap: onSavingsTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  label: 'الكلي معك',
                  amount: summary.total,
                  currency: currency,
                ),
              ),
            ],
          ),
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
    this.onTap,
  });

  final String label;
  final int amount;
  final Currency currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.onPrimaryMuted, fontSize: 12)),
                  ),
                  if (onTap != null)
                    const Icon(Icons.chevron_right,
                        color: AppColors.onPrimaryMuted, size: 18),
                ],
              ),
              const SizedBox(height: 2),
              MoneyText(amount,
                  currency: currency,
                  showSymbol: false,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
```

```dart
// file: lib/app/modules/home/widgets/month_end_banner.dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// "Last month ended with X left — move some to savings?"
class MonthEndBanner extends StatelessWidget {
  const MonthEndBanner({
    super.key,
    required this.amount,
    required this.currency,
    required this.onSplit,
    required this.onSkip,
  });

  final int amount;
  final Currency currency;
  final VoidCallback onSplit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'خلص الشهر الماضي وضل معك ${MoneyText.label(amount, currency)}. بدك تحوّل منهم للادخار؟',
            style: const TextStyle(color: AppColors.primaryDark, fontSize: 13),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onSkip, child: const Text('مش هلأ')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: onSplit,
                child: const Text('وزّع'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

`home_view.dart`: pass `onSavingsTap: controller.openSavings` to `BalanceCard`, and right after it:

```dart
              if (controller.monthEndOffer.value case final offer?) ...[
                const SizedBox(height: 12),
                MonthEndBanner(
                  amount: offer,
                  currency: controller.currency,
                  onSplit: controller.openMonthEnd,
                  onSkip: controller.skipMonthEnd,
                ),
              ],
```

```dart
// file: lib/app/modules/month_end/controllers/month_end_controller.dart
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/month_end_check.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/savings_goal.dart';
import '../../../data/models/savings_movement.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Split last period's leftover across savings goals (spec §6.4).
class MonthEndController extends GetxController {
  MonthEndController({
    required this.savings,
    required this.transactions,
    required this.settings,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SavingsRepository savings;
  final TransactionRepository transactions;
  final SettingsService settings;
  final DateTime Function() _clock;

  final offered = 0.obs;
  final goals = <SavingsGoal>[].obs;
  final allocated = 0.obs;
  final isSaving = false.obs;
  final _inputs = <int, TextEditingController>{};

  late final Future<void> ready;

  Currency get currency => settings.currency;

  bool get canSave =>
      !isSaving.value && allocated.value > 0 && allocated.value <= offered.value;

  @override
  void onInit() {
    super.onInit();
    ready = _load();
  }

  Future<void> _load() async {
    final current = settings.currentPeriod(_clock());
    offered.value = MonthEndCheck.leftoverToOffer(
          current: current,
          lastPromptedKey: settings.settings.value.lastMonthEndPromptPeriod,
          transactions: await transactions.getAll(),
          movements: await savings.getAllMovements(),
        ) ??
        0;
    goals.assignAll(await savings.getGoals());
  }

  TextEditingController controllerFor(int goalId) =>
      _inputs.putIfAbsent(goalId, () {
        final input = TextEditingController();
        input.addListener(_recount);
        return input;
      });

  void _recount() {
    var sum = 0;
    for (final input in _inputs.values) {
      sum += Money.parse(input.text, decimals: 3) ?? 0;
    }
    allocated.value = sum;
  }

  void putAllInGeneral() {
    for (final input in _inputs.values) {
      input.text = '';
    }
    final general = goals.firstWhere((g) => g.isGeneral);
    controllerFor(general.id!).text = Money.toEditable(offered.value);
  }

  /// Saves every amount in one transaction and closes the question for the
  /// period. Returns false when the split is not valid or saving fails.
  Future<bool> save() async {
    if (!canSave) return false;
    isSaving.value = true;
    final date = DateKeys.dateOnly(_clock());
    final now = DateTime.fromMillisecondsSinceEpoch(DateTime.now().millisecondsSinceEpoch);
    final movements = [
      for (final MapEntry(key: goalId, value: input) in _inputs.entries)
        if (Money.parse(input.text, decimals: 3) case final amount?)
          SavingsMovement(
            goalId: goalId,
            amount: amount,
            date: date,
            source: SavingsSource.monthEnd,
            createdAt: now,
          ),
    ];
    try {
      await savings.addMovements(movements);
      await _markAnswered();
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ التوزيع');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> skip() async {
    try {
      await _markAnswered();
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحفظ اختيارك');
    }
  }

  Future<void> _markAnswered() {
    final previous = settings.currentPeriod(_clock()).previous;
    return settings.update(settings.settings.value
        .copyWith(lastMonthEndPromptPeriod: previous.key));
  }

  @override
  void onClose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/month_end/bindings/month_end_binding.dart
import 'package:get/get.dart';

import '../controllers/month_end_controller.dart';

class MonthEndBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => MonthEndController(
          savings: Get.find(),
          transactions: Get.find(),
          settings: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/month_end/views/month_end_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/money_text.dart';
import '../controllers/month_end_controller.dart';

class MonthEndView extends GetView<MonthEndController> {
  const MonthEndView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('وزّع اللي ضل معك')),
      body: SafeArea(
        child: Obx(() {
          final goals = controller.goals.toList();
          final offered = controller.offered.value;
          final allocated = controller.allocated.value;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('ضل معك من الشهر الماضي ${MoneyText.label(offered, controller.currency)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'وزّعت ${MoneyText.label(allocated, controller.currency)} · باقي ${MoneyText.label(offered - allocated, controller.currency)}',
                style: TextStyle(
                    color: allocated > offered ? AppColors.danger : AppColors.muted,
                    fontSize: 13),
              ),
              const SizedBox(height: 16),
              for (final goal in goals) ...[
                TextField(
                  controller: controller.controllerFor(goal.id!),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: goal.name,
                    suffixText: controller.currency.symbol,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextButton(
                onPressed: controller.putAllInGeneral,
                child: const Text('حط الكل بالادخار العام'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: controller.canSave ? _save : null,
                child: const Text('حفظ'),
              ),
              TextButton(onPressed: _skip, child: const Text('مش هلأ — خليهم مرحّلين')),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _save() async {
    if (await controller.save()) Get.back();
  }

  Future<void> _skip() async {
    await controller.skip();
    Get.back();
  }
}
```

Add to `app_pages.dart`: `GetPage(name: Routes.monthEnd, page: () => const MonthEndView(), binding: MonthEndBinding(), fullscreenDialog: true)`.

- [ ] **Step 4: Run tests** — Run: `flutter analyze && flutter test` — Expected: no issues, PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add month-end leftover split and savings totals on Home"`

---

### Task 8: Recurring savings rules

**Files:**
- Modify: `lib/app/modules/recurring_form/controllers/recurring_form_controller.dart`, `lib/app/modules/recurring_form/views/recurring_form_view.dart`, `lib/app/modules/recurring_form/bindings/recurring_form_binding.dart`, `test/modules/recurring_form/recurring_form_controller_test.dart`
- Test: add cases to `test/modules/recurring_form/recurring_form_controller_test.dart`

**Interfaces:**
- Changes: `RecurringFormController` gains `required SavingsRepository savings`; `kind` becomes `Rx<RecurringKind>` and `setKind(RecurringKind)`; new `goals` (`RxList<SavingsGoal>`), `goalId` (`RxnInt`), `selectGoal(int)`. `canSave` needs a goal for saving rules and a category otherwise.

- [ ] **Step 1: Update the existing tests and write the failing ones** — in the test file: pass `savings: Get.find()` to every `RecurringFormController(`; replace `TransactionKind.expense` with `RecurringKind.expense` in the "defaults" test and `c.setKind(TransactionKind.income)` with `c.setKind(RecurringKind.income)`. Then add:

```dart
  test('a monthly saving goes to the chosen goal as a recurring movement', () async {
    final c = await open();
    c.setKind(RecurringKind.saving);
    expect(c.visibleCategories, isEmpty);
    expect(c.goals.first.name, 'ادخار عام');
    c.amountText.value = '50';
    expect(c.canSave, isFalse);
    c.selectGoal(1);
    expect(c.canSave, isTrue);
    expect(await c.save(), isTrue);

    final rule = (await Get.find<RecurringRepository>().getAll()).single;
    expect(rule.kind, RecurringKind.saving);
    expect(rule.goalId, 1);
    expect(rule.categoryId, isNull);
    expect(rule.label, 'ادخار عام');
    final movement = (await Get.find<SavingsRepository>().getAllMovements()).single;
    expect(movement.amount, 50000);
    expect(movement.source, SavingsSource.recurring);
  });
```

(add imports for `savings_repository.dart`.)

- [ ] **Step 2: Run tests to verify they fail** — Run: `flutter test test/modules/recurring_form` — Expected: FAIL (no `savings` parameter / `RecurringKind` kind).

- [ ] **Step 3: Implement** — in `recurring_form_controller.dart`:
  - add `required this.savings,` and `final SavingsRepository savings;` (import `savings_repository.dart` and `savings_goal.dart`)
  - `final kind = RecurringKind.expense.obs;`, `final goalId = RxnInt();`, `final goals = <SavingsGoal>[].obs;`
  - `canSave => !isSaving.value && amount != null && (kind.value == RecurringKind.saving ? goalId.value != null : categoryId.value != null);`
  - `visibleCategories`: `kind.value == RecurringKind.saving ? const [] : _allCategories.where((c) => c.kind.name == kind.value.name).toList()`
  - `_load()`: also `goals.assignAll(await savings.getGoals());`; for an edited rule `kind.value = rule.kind; goalId.value = rule.goalId;`
  - `setKind(RecurringKind value)` clears both `categoryId` and `goalId`; add `void selectGoal(int id) => goalId.value = id;`
  - `save()`: build with `categoryId: saving ? null : category`, `goalId: saving ? goalId.value : null`, label fallback `saving ? goals.firstWhere((g) => g.id == goalId.value).name : category name`, `kind: kind.value`. For an edit, `copyWith` gains `goalId` (add `int? goalId` to `RecurringRule.copyWith`).
  - guard at the top of `save()`: `if (!canSave || value == null) return false;` (category may be null for savings).

  In the view, replace the `KindToggle` with a three-way `SegmentedButton<RecurringKind>` (مصروف / دخل / ادخار), and show goal `ChoiceChip`s instead of the `CategoryGrid` when the kind is saving:

```dart
            Obx(() => SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<RecurringKind>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: RecurringKind.expense, label: Text('مصروف')),
                      ButtonSegment(value: RecurringKind.income, label: Text('دخل')),
                      ButtonSegment(value: RecurringKind.saving, label: Text('ادخار')),
                    ],
                    selected: {controller.kind.value},
                    onSelectionChanged: (s) => controller.setKind(s.first),
                  ),
                )),
```

```dart
            Obx(() => controller.kind.value == RecurringKind.saving
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final goal in controller.goals)
                        ChoiceChip(
                          label: Text(goal.name),
                          selected: controller.goalId.value == goal.id,
                          onSelected: (_) => controller.selectGoal(goal.id!),
                        ),
                    ],
                  )
                : CategoryGrid(
                    categories: controller.visibleCategories,
                    selectedId: controller.categoryId.value,
                    onSelected: controller.selectCategory,
                  )),
```

  with the label above it reading `controller.kind.value == RecurringKind.saving ? 'الهدف' : 'التصنيف'`. Binding: add `savings: Get.find(),`.

- [ ] **Step 4: Run tests** — Run: `flutter analyze && flutter test` — Expected: no issues, PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add recurring monthly savings to goals"`

---

### Task 9: Reports screen

**Files:**
- Create: `lib/app/modules/reports/{bindings/reports_binding.dart, controllers/reports_controller.dart, views/reports_view.dart, widgets/category_donut.dart, widgets/period_bars.dart}`
- Modify: `lib/app/routes/app_pages.dart`
- Test: `test/modules/reports/reports_controller_test.dart`

**Interfaces:**
- Produces: `ReportsController({required TransactionRepository transactions, required CategoryRepository categories, required SettingsService settings, required DatabaseService database, DateTime Function()? clock})`: `period`, `shares` (`RxList<CategoryShare>`), `totals` (`RxList<PeriodTotals>`), `change` (`RxnInt`), `totalSpent` (`RxInt`), `currency`, `load()`, `previousPeriod()`, `nextPeriod()`, `openSavings()`; `reportPeriods = 6`.

- [ ] **Step 1: Write the failing test**

```dart
// file: test/modules/reports/reports_controller_test.dart
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/reports/controllers/reports_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  Future<ReportsController> open() async {
    final c = Get.put(ReportsController(
      transactions: Get.find(),
      categories: Get.find(),
      settings: Get.find(),
      database: Get.find(),
      clock: () => DateTime(2026, 10, 15),
    ));
    await c.load();
    return c;
  }

  test('shares, six-period totals and the change from last period', () async {
    final repo = Get.find<TransactionRepository>();
    await repo.add(expense(100000, DateTime(2026, 9, 5)));
    await repo.add(expense(84000, DateTime(2026, 10, 2)));
    await repo.add(expense(28000, DateTime(2026, 10, 3), categoryId: 3));

    final c = await open();
    expect(c.shares.map((s) => s.category.name), ['أكل', 'فواتير']);
    expect(c.shares.map((s) => s.percent), [75, 25]);
    expect(c.totalSpent.value, 112000);
    expect(c.totals, hasLength(ReportsController.reportPeriods));
    expect(c.totals.last.expenses, 112000);
    expect(c.change.value, 12);
  });

  test('an empty period has no shares and no change', () async {
    final c = await open();
    expect(c.shares, isEmpty);
    expect(c.totalSpent.value, 0);
    expect(c.change.value, isNull);
  });

  test('moving to the previous period', () async {
    await Get.find<TransactionRepository>().add(expense(100000, DateTime(2026, 9, 5)));
    final c = await open();
    await c.previousPeriod();
    expect(c.period.value!.key, '2026-09');
    expect(c.totalSpent.value, 100000);
  });
}
```

- [ ] **Step 2: Run test to verify it fails** — Run: `flutter test test/modules/reports` — Expected: FAIL.

- [ ] **Step 3: Implement**

```dart
// file: lib/app/modules/reports/controllers/reports_controller.dart
import 'package:get/get.dart';

import '../../../core/logic/period.dart';
import '../../../core/logic/report_calculator.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class ReportsController extends GetxController {
  ReportsController({
    required this.transactions,
    required this.categories,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const reportPeriods = 6;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final period = Rxn<Period>();
  final shares = <CategoryShare>[].obs;
  final totals = <PeriodTotals>[].obs;
  final change = RxnInt();
  final totalSpent = 0.obs;

  bool _followsCurrent = true;
  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final current = _followsCurrent
        ? settings.currentPeriod(_clock())
        : period.value ?? settings.currentPeriod(_clock());
    final all = await transactions.getAll();
    final allCategories = await categories.getAll(includeArchived: true);

    final periodTotals = ReportCalculator.totals(
        last: current, count: reportPeriods, transactions: all);
    final now = periodTotals.last.expenses;
    final before = periodTotals[periodTotals.length - 2].expenses;

    period.value = current;
    shares.assignAll(ReportCalculator.byCategory(
      period: current,
      transactions: all,
      categoriesById: {for (final c in allCategories) c.id!: c},
    ));
    totals.assignAll(periodTotals);
    totalSpent.value = now;
    change.value = now == 0
        ? null
        : ReportCalculator.changePercent(previous: before, current: now);
  }

  Future<void> previousPeriod() => _show(period.value!.previous);

  Future<void> nextPeriod() => _show(period.value!.next);

  Future<void> _show(Period value) {
    period.value = value;
    _followsCurrent = value == settings.currentPeriod(_clock());
    return load();
  }

  void openSavings() => Get.toNamed(Routes.savings);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
```

```dart
// file: lib/app/modules/reports/bindings/reports_binding.dart
import 'package:get/get.dart';

import '../controllers/reports_controller.dart';

class ReportsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => ReportsController(
          transactions: Get.find(),
          categories: Get.find(),
          settings: Get.find(),
          database: Get.find(),
        ));
  }
}
```

```dart
// file: lib/app/modules/reports/widgets/category_donut.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/logic/report_calculator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currencies.dart';
import '../../../widgets/money_text.dart';

/// Spending by category as a donut, with a legend.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.shares,
    required this.total,
    required this.currency,
  });

  final List<CategoryShare> shares;
  final int total;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(PieChartData(
                centerSpaceRadius: 60,
                sectionsSpace: 2,
                startDegreeOffset: -90,
                sections: [
                  for (final share in shares)
                    PieChartSectionData(
                      value: share.amount.toDouble(),
                      color: Color(share.category.colorValue),
                      radius: 26,
                      showTitle: false,
                    ),
                ],
              )),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('المصاريف',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  MoneyText(total,
                      currency: currency,
                      showSymbol: false,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final share in shares)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(share.category.colorValue),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(share.category.name)),
                MoneyText(share.amount,
                    currency: currency,
                    showSymbol: false,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  child: Text('${share.percent}%',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

```dart
// file: lib/app/modules/reports/widgets/period_bars.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/logic/report_calculator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_utils.dart';

/// Expenses of the last periods as bars; the shown period is highlighted.
class PeriodBars extends StatelessWidget {
  const PeriodBars({super.key, required this.totals});

  final List<PeriodTotals> totals;

  @override
  Widget build(BuildContext context) {
    final maxValue = totals.fold(0, (m, t) => t.expenses > m ? t.expenses : m);
    return SizedBox(
      height: 160,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: BarChart(BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.15,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final period = totals[value.toInt()].period;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(ArabicDates.months[period.start.month - 1],
                        style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (final (index, total) in totals.indexed)
              BarChartGroupData(x: index, barRods: [
                BarChartRodData(
                  toY: total.expenses.toDouble(),
                  width: 22,
                  color: index == totals.length - 1
                      ? AppColors.primary
                      : const Color(0xFFC8D6D0),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ]),
          ],
        )),
      ),
    );
  }
}
```

Bars are drawn left-to-right (oldest → newest) like a timeline, as in the mockup.

```dart
// file: lib/app/modules/reports/views/reports_view.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/period_switcher.dart';
import '../controllers/reports_controller.dart';
import '../widgets/category_donut.dart';
import '../widgets/period_bars.dart';

class ReportsView extends GetView<ReportsController> {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final period = controller.period.value;
          return period == null
              ? const Text('التقارير')
              : PeriodSwitcher(
                  period: period,
                  onPrevious: controller.previousPeriod,
                  onNext: controller.nextPeriod,
                );
        }),
      ),
      body: Obx(() {
        final shares = controller.shares.toList();
        final totals = controller.totals.toList();
        final change = controller.change.value;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: shares.isEmpty
                    ? const EmptyState(
                        icon: Icons.pie_chart_outline,
                        message: 'ما في مصاريف بهالفترة',
                      )
                    : CategoryDonut(
                        shares: shares,
                        total: controller.totalSpent.value,
                        currency: controller.currency,
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('مقارنة آخر 6 شهور',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (change != null)
                          Text(
                            change >= 0
                                ? '↑ $change% عن الشهر الماضي'
                                : '↓ ${-change}% عن الشهر الماضي',
                            style: TextStyle(
                              fontSize: 12,
                              color: change > 0 ? AppColors.expense : AppColors.income,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (totals.isNotEmpty) PeriodBars(totals: totals),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: controller.openSavings,
              icon: const Icon(Icons.savings_outlined),
              label: const Text('المدخرات والأهداف'),
            ),
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.reports),
    );
  }
}
```

Add to `app_pages.dart`: `GetPage(name: Routes.reports, page: () => const ReportsView(), binding: ReportsBinding(), transition: Transition.noTransition)`.

- [ ] **Step 4: Run tests** — Run: `flutter analyze && flutter test` — Expected: no issues, PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add reports with spending by category and six-period comparison"`

---

### Task 10: Backup and restore in Settings

**Files:**
- Modify: `lib/app/modules/settings/controllers/settings_controller.dart`, `bindings/settings_binding.dart`, `views/settings_view.dart`; construction in `test/modules/settings/settings_controller_test.dart`, `test/modules/settings/reminder_settings_test.dart`, `test/modules/error_handling_test.dart`
- Test: `test/modules/settings/backup_settings_test.dart`

**Interfaces:**
- Changes: `SettingsController({required SettingsService settingsService, required NotificationService notifications, required BackupService backup, required FileExchangeProvider files, DateTime Function()? clock})`; new `lastBackupLabel` (String), `backupOverdue` (bool), `exportBackup()`, `pickBackup() → Future<BackupSummary?>`, `restore(BackupSummary) → Future<bool>`.

- [ ] **Step 1: Update construction and write the failing test** — every `SettingsController(` in tests gains `backup: Get.find(), files: Get.find()`.

```dart
// file: test/modules/settings/backup_settings_test.dart
import 'package:calculator/app/data/providers/file_exchange_provider.dart';
import 'package:calculator/app/data/repositories/transaction_repository.dart';
import 'package:calculator/app/modules/settings/controllers/settings_controller.dart';
import 'package:calculator/app/services/backup_service.dart';
import 'package:calculator/app/services/message_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../../helpers/fake_files.dart';
import '../../helpers/fixtures.dart';
import '../../helpers/test_services.dart';

void main() {
  setUp(setUpTestServices);

  final today = DateTime(2026, 10, 4, 9);

  SettingsController open() => Get.put(SettingsController(
        settingsService: Get.find(),
        notifications: Get.find(),
        backup: Get.find(),
        files: Get.find(),
        clock: () => today,
      ));

  FakeFileExchangeProvider files() =>
      Get.find<FileExchangeProvider>() as FakeFileExchangeProvider;

  test('never backed up: says so and flags it', () {
    final c = open();
    expect(c.lastBackupLabel, 'ما عملت نسخة احتياطية لسا');
    expect(c.backupOverdue, isTrue);
  });

  test('backing up shares a file and updates the label', () async {
    final c = open();
    await c.exportBackup();
    expect(files().shared, hasLength(1));
    expect(c.lastBackupLabel, 'آخر نسخة: اليوم');
    expect(c.backupOverdue, isFalse);
  });

  test('picking a file that is not a backup shows why', () async {
    files().textToPick = 'not json';
    expect(await open().pickBackup(), isNull);
    expect(Get.find<MessageService>().lastMessage.value, contains('مش نسخة'));
  });

  test('cancelling the picker does nothing', () async {
    files().textToPick = null;
    expect(await open().pickBackup(), isNull);
    expect(Get.find<MessageService>().lastMessage.value, isNull);
  });

  test('restoring a picked backup replaces the data', () async {
    final repo = Get.find<TransactionRepository>();
    await repo.add(expense(5000, DateTime(2026, 10, 1)));
    files().textToPick = await Get.find<BackupService>().exportJson(today);
    await repo.add(expense(7000, DateTime(2026, 10, 2)));

    final c = open();
    final summary = await c.pickBackup();
    expect(summary!.transactionCount, 1);
    expect(await c.restore(summary), isTrue);
    expect((await repo.getAll()).single.amount, 5000);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail** — Run: `flutter test test/modules/settings` — Expected: FAIL.

- [ ] **Step 3: Implement** — `settings_controller.dart` additions (constructor fields `backup`, `files`, `_clock = clock ?? DateTime.now`; imports for `backup_service.dart`, `file_exchange_provider.dart`, `date_utils.dart`):

```dart
  static const backupReminderDays = 30;

  String get lastBackupLabel {
    final last = settings.lastBackupAt;
    if (last == null) return 'ما عملت نسخة احتياطية لسا';
    final days = DateKeys.dateOnly(_clock()).difference(DateKeys.dateOnly(last)).inDays;
    if (days <= 0) return 'آخر نسخة: اليوم';
    if (days == 1) return 'آخر نسخة: مبارح';
    return 'آخر نسخة: قبل $days يوم';
  }

  bool get backupOverdue {
    final last = settings.lastBackupAt;
    return last == null ||
        _clock().difference(last).inDays > backupReminderDays;
  }

  Future<void> exportBackup() async {
    try {
      await backup.shareBackup(_clock());
    } catch (_) {
      Get.find<MessageService>().showError('ما قدرنا نعمل النسخة الاحتياطية');
    }
  }

  /// Lets the user pick a backup file. Null when cancelled or invalid (a
  /// message explains why).
  Future<BackupSummary?> pickBackup() async {
    final String? text;
    try {
      text = await files.pickJsonText();
    } catch (_) {
      Get.find<MessageService>().showError('ما قدرنا نفتح الملف');
      return null;
    }
    if (text == null) return null;
    try {
      return backup.parse(text);
    } on BackupFormatException catch (e) {
      Get.find<MessageService>().showError(e.message);
      return null;
    }
  }

  Future<bool> restore(BackupSummary summary) async {
    try {
      await backup.restore(summary);
      return true;
    } catch (_) {
      Get.find<MessageService>()
          .showError('ما قدرنا نسترجع النسخة. بياناتك الحالية ما تغيّرت');
      return false;
    }
  }
```

Binding: `SettingsController(settingsService: Get.find(), notifications: Get.find(), backup: Get.find(), files: Get.find())`.

View — after the "إدارة" card:

```dart
            const _SectionTitle('النسخ الاحتياطي'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('نسخة احتياطية الآن'),
                    subtitle: Text(
                      controller.lastBackupLabel,
                      style: TextStyle(
                          color: controller.backupOverdue ? AppColors.warning : AppColors.muted),
                    ),
                    onTap: controller.exportBackup,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('استرجاع من ملف'),
                    onTap: () => _restore(context),
                  ),
                ],
              ),
            ),
```

and:

```dart
  Future<void> _restore(BuildContext context) async {
    final summary = await controller.pickBackup();
    if (summary == null || !context.mounted) return;
    final when = summary.exportedAt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع النسخة؟'),
        content: Text(
          'رح تنمسح بياناتك الحالية وتنحط مكانها نسخة '
          '${when.day}/${when.month}/${when.year}: '
          '${summary.transactionCount} عملية و ${summary.goalCount} أهداف.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استرجاع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final restored = await controller.restore(summary);
    if (restored && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('انسترجعت النسخة')));
    }
  }
```

- [ ] **Step 4: Run tests** — Run: `flutter analyze && flutter test` — Expected: no issues, PASS
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: add backup and restore to settings"`

---

### Task 11: End-to-end checks, README, device check

**Files:**
- Modify: `test/app_test.dart`, `README.md`

- [ ] **Step 1: End-to-end tests** — append to `test/app_test.dart` (import `savings_repository.dart`):

```dart
  testWidgets('the reports tab shows spending by category', (tester) async {
    await boot(tester);
    await tester.runAsync(() => Get.find<TransactionRepository>().add(expense(5000, DateTime.now())));
    await tester.tap(find.text('التقارير'));
    await idle(tester);
    expect(find.text('أكل'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('Home opens savings from the savings total', (tester) async {
    await boot(tester);
    await tester.tap(find.text('مجموع المدخرات'));
    await idle(tester);
    expect(find.text('ادخار عام'), findsOneWidget);
    expect(find.text('هدف جديد'), findsOneWidget);
  });

  testWidgets('Home offers last month\'s leftover', (tester) async {
    await boot(tester);
    final now = DateTime.now();
    await tester.runAsync(() => Get.find<TransactionRepository>()
        .add(income(100000, DateTime(now.year, now.month - 1, 1))));
    await idle(tester);
    expect(find.textContaining('خلص الشهر الماضي'), findsOneWidget);
    await tester.tap(find.text('مش هلأ'));
    await idle(tester);
    expect(find.textContaining('خلص الشهر الماضي'), findsNothing);
  });
```

Run: `flutter test test/app_test.dart --timeout 60s` — Expected: PASS.

- [ ] **Step 2: README** — Features list: add reports, savings goals (manual, month-end split, monthly savings), Home totals, backup/restore; remove the "Planned" line.

- [ ] **Step 3: Verify** — Run: `flutter analyze && flutter test --timeout 60s && flutter build ios --simulator --debug` — Expected: clean, all pass, built. Then on the iPhone 17 Pro simulator: Reports tab renders, add a goal and deposit/withdraw, month-end banner appears with last-month data, Backup now opens the share sheet.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "test: end-to-end checks for reports, savings and month-end; update README"`
