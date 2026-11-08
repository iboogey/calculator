# Debts, Obligations and Standard Arabic — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Debts screen (الأشخاص: running balance per person; عليّ: obligations paid fully/partly, optionally recorded as an expense), a Home card with a due reminder and a "بعد تسوية الديون" preview, and rewrite every UI string in فصحى.

**Architecture:** Same GetX Pattern as phases 1–3. Schema version 2 adds four tables through the app's first `onUpgrade`. Pure math in `core/logic/debt_summary.dart`; one `DebtRepository` for all reads/writes (pay and delete-payment are single DB transactions that also touch `transactions`); modules `debts`, `debt_person`, `obligation_form`; Home and Transactions learn about debts through the repository.

**Tech Stack:** Flutter 3.44.8, `get`, `sqflite` (+ `sqflite_common_ffi` in tests). No new packages.

**Spec:** `docs/superpowers/specs/2026-11-08-debts-and-fusha-design.md` (read it — section numbers below refer to it). Mockup: https://claude.ai/artifact/CZyPJji129JRMWFE5crwfn

## Global Constraints

- Offline; money is `int` thousandths (`Money`); dates are `YYYY-MM-DD` text (`DateKeys`); Arabic RTL; GetX Pattern; controllers catch `DatabaseException` and call `MessageService.showError(...)`; every repository write calls `DatabaseService.notifyChanged()`.
- Dialogs/sheets that own a `TextEditingController` keep it in their own `State`.
- Amount inputs use `AmountField` / `AmountInputFormatter` (phone number keyboard) — never a custom keypad.
- Person entry sign: **positive = "أعطيتُ" (they owe me more), negative = "أخذتُ" (I owe them more)**.
- People entries never change "المتبقي من الراتب" / "الكلي معك". Obligation payments change them only through the optional expense transaction.
- An expense created by a payment is owned by it: in العمليات its amount and kind are read-only and it cannot be deleted (§9).
- Settle preview = `remaining + owedToMe − iOwe`, where `iOwe` = people I owe + unpaid obligation remainders. View only, never saved.
- Due reminder window: due within **3** days (today = 0) or overdue.
- Backup `schemaVersion` = **2**; restore accepts 1 and 2; a v1 file restores with empty debt tables.
- All new and existing UI copy is فصحى; no dialect markers (Task 13 list) anywhere in `lib/`.
- Branch: `feature/debts-fusha`. Run `flutter analyze` (no issues) and `flutter test` (all pass) before every commit.

## Review Focus

1. Paying twice quickly, or paying more than what is left → second/over payment refused, remaining never negative. *(Task 5 `pay refuses more than remaining`; Task 9 `a second pay while saving is ignored`)*
2. Deleting a payment whose expense the user already changed in العمليات (date/category) → payment and that expense both go, Home balance comes back. *(Task 5 `deletePayment removes its expense even after it was edited`)*
3. Upgrading a phone that already has phase-3 data → nothing lost, new tables present. *(Task 2 migration test)*
4. A person name with extra spaces or the same name again ("علا " vs "علا") → treated as duplicate. *(Task 4 `addPerson trims and refuses duplicates`)*
5. Obligation due today vs. yesterday vs. in 3 days at month/year boundaries → "اليوم" / "متأخر منذ يوم" / "خلال 3 أيام", computed on date-only values. *(Task 3 `daysUntil across a year boundary`)*

---

### Task 1: Debt models

**Files:**
- Create: `lib/app/data/models/debt_person.dart`, `debt_entry.dart`, `obligation.dart`, `obligation_payment.dart` (all in `lib/app/data/models/`)
- Test: `test/data/models/debt_models_test.dart`

**Interfaces:**
- Produces (immutable, `fromMap` / `toMap` / `==` / `hashCode` / `withId(int)`, same style as `SavingsMovement`; `fromMap` casts with `as`, so wrong types throw):
  - `DebtPerson({int? id, required String name, required DateTime createdAt})` — columns `id, name, created_at`; `copyWith({String? name})`.
  - `DebtEntry({int? id, required int personId, required int amount, required DateTime date, String? note, required DateTime createdAt})` — `person_id, amount, date, note, created_at`; `copyWith({int? amount, DateTime? date, String? note})`.
  - `Obligation({int? id, required String title, required int amount, DateTime? dueDate, String? note, required DateTime createdAt})` — `title, amount, due_date (nullable), note, created_at`; `copyWith({String? title, int? amount, DateTime? Function()? dueDate, String? Function()? note})` (function wrappers so null can be set).
  - `ObligationPayment({int? id, required int obligationId, required int amount, required DateTime date, int? transactionId, required DateTime createdAt})` — `obligation_id, amount, date, transaction_id, created_at`.

- [ ] **Step 1: Write failing tests** — for each model: `toMap` then `fromMap` round-trips to an equal object (include null `note`, null `dueDate`, null `transactionId`); `fromMap` with `'amount': '5'` throws a `TypeError`; `Obligation.copyWith(dueDate: () => null)` clears the date.
- [ ] **Step 2:** `flutter test test/data/models/debt_models_test.dart` → FAIL (files missing).
- [ ] **Step 3:** Implement the four models.
- [ ] **Step 4:** Same command → PASS.
- [ ] **Step 5:** Commit `feat: add debt and obligation models`.

---

### Task 2: Schema version 2 and the first migration

**Files:**
- Modify: `lib/app/data/providers/app_database.dart`
- Test: `test/data/providers/app_database_migration_test.dart`

**Interfaces:**
- Produces: `AppDatabase.version == 2`; `@visibleForTesting static const List<String> schemaV1` (today's `_schema`) and `schemaV2` (the §7 statements: 4 tables + 2 indexes, verbatim); `onCreate` runs `schemaV1 + schemaV2` then seeds; `onUpgrade(db, oldVersion, newVersion)` runs `schemaV2` when `oldVersion < 2`.
- Seed change: the first expense category name becomes `'طعام'` (was `'أكل'`, `icon_key 'food'` unchanged) — new installs only.

- [ ] **Step 1: Write failing tests**
  - `fresh database has the debt tables` — open via `openTestDatabase()`; `sqlite_master` lists `debt_people, debt_entries, obligations, obligation_payments`.
  - `upgrading a version-1 database keeps its data and adds the debt tables` — with `databaseFactoryFfi` and a temp file path (`Directory.systemTemp.createTempSync()`): open with `version: 1`, `onCreate` running `AppDatabase.schemaV1` + inserting one category and one transaction; close; reopen with `AppDatabase.open(factory: databaseFactoryFfi, path: samePath)`; expect the transaction row still there and the 4 tables present; `PRAGMA user_version` = 2.
  - `deleting a person cascades to their entries` and `deleting a transaction clears payment.transaction_id` (foreign keys are on).
- [ ] **Step 2:** `flutter test test/data/providers/app_database_migration_test.dart` → FAIL.
- [ ] **Step 3:** Implement. Update `test/helpers/fixtures.dart` doc comment (1 = طعام) and any test that finds the text `'أكل'` from the seed (e.g. `test/app_test.dart`) to `'طعام'`.
- [ ] **Step 4:** `flutter test` → all PASS.
- [ ] **Step 5:** Commit `feat: schema v2 with debt tables and first migration`.

---

### Task 3: Debt math and due labels

**Files:**
- Create: `lib/app/core/logic/debt_summary.dart`
- Modify: `lib/app/core/utils/date_utils.dart` (add `ArabicDates.dueLabel`)
- Test: `test/core/logic/debt_summary_test.dart`, `test/core/utils/date_utils_test.dart` (add cases; create if absent)

**Interfaces:**
- Consumes: Task 1 models.
- Produces:
  - `class PersonBalance { final DebtPerson person; final int balance; }`
  - `class ObligationStatus { final Obligation obligation; final int paid; int get remaining => obligation.amount - paid; bool get isPaid => remaining <= 0; }`
  - `class DueInfo { final ObligationStatus status; final int daysLeft; }` (negative = overdue)
  - `class DebtTotals { final int owedToMe; final int iOwe; bool get isEmpty; }`
  - `abstract final class DebtSummary`:
    - `static List<PersonBalance> people(List<DebtPerson> people, Map<int, int> balances)` — non-zero first by `|balance|` desc, then settled by name.
    - `static List<ObligationStatus> obligations(List<Obligation> list, Map<int, int> paid)` — unpaid first (due date asc, no date last, then `createdAt` asc), then paid (`createdAt` desc).
    - `static DebtTotals totals(List<PersonBalance> people, List<ObligationStatus> obligations)` — owedToMe = Σ positive balances; iOwe = Σ |negative balances| + Σ unpaid remaining.
    - `static int daysUntil(DateTime due, DateTime today)` — date-only difference in calendar days (use `DateTime.utc(y,m,d)` for both to avoid DST).
    - `static DueInfo? mostUrgent(List<ObligationStatus> list, DateTime today, {int withinDays = 3})` — smallest `daysLeft` among unpaid with a due date, only if `daysLeft <= withinDays`.
    - `static int settledRemaining(int remaining, DebtTotals totals)` → `remaining + owedToMe - iOwe`.
  - `ArabicDates.dueLabel(int daysLeft)`: `0 → 'اليوم'`, `1 → 'خلال يوم'`, `2 → 'خلال يومين'`, `3..10 → 'خلال N أيام'`, `≥11 → 'خلال N يومًا'`; negative mirrors with `'متأخر منذ يوم' / 'متأخر منذ يومين' / 'متأخر منذ N أيام' / 'متأخر منذ N يومًا'`.

- [ ] **Step 1: Write failing tests** — `people orders owed first by size, settled last by name`; `obligations puts unpaid by due date with undated last, paid after`; `totals adds people I owe and unpaid remainders` (balances {+980, −40, 0}, obligations 600 paid 300 + 157.2 unpaid + 50 paid fully → owedToMe 980000, iOwe 40000+300000+157200); `remaining never counts a fully paid obligation`; `mostUrgent picks overdue over due-in-2 and ignores due-in-4`; `mostUrgent is null without due dates`; `daysUntil across a year boundary` (due 2027-01-01, today 2026-12-31 → 1; today 2027-01-02 → −1); `settledRemaining = 412500 + 1477000 − 539950 = 1349550`; dueLabel for 0, 1, 2, 3, 11, −1, −2, −5, −12.
- [ ] **Step 2:** run both test files → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: debt totals, ordering and due labels`.

---

### Task 4: DebtRepository — people

**Files:**
- Create: `lib/app/data/repositories/debt_repository.dart`
- Modify: `lib/app/bindings/initial_binding.dart` (register `DebtRepository(database)` permanently, next to `SavingsRepository`)
- Test: `test/data/repositories/debt_repository_people_test.dart`

**Interfaces:**
- Produces in `debt_repository.dart`:
  - `class DuplicateNameException implements Exception { const DuplicateNameException(); }`
  - `class DebtRepository { DebtRepository(DatabaseService database); ... }` with:
    - `Future<List<DebtPerson>> getPeople()` (by name), `Future<DebtPerson?> getPerson(int id)`
    - `Future<DebtPerson> addPerson(String name)` — trims; throws `ArgumentError` when empty, `DuplicateNameException` when another person has the same trimmed name (compare `trim(name)` in SQL).
    - `Future<void> renamePerson(int id, String name)` — same rules, excluding itself.
    - `Future<void> deletePerson(int id)` (cascade removes entries)
    - `Future<Map<int, int>> personBalances()` — `SUM(amount) GROUP BY person_id`.
    - `Future<List<DebtEntry>> getEntries(int personId)` — `date DESC, id DESC`.
    - `Future<DebtEntry> addEntry(DebtEntry entry)`, `Future<void> updateEntry(DebtEntry entry)`, `Future<void> deleteEntry(int id)`, `Future<void> restoreEntry(DebtEntry entry)` (insert with its id, for Undo).

- [ ] **Step 1: Write failing tests** (use `setUpTestServices()` and `Get.find<DebtRepository>()`): `addPerson trims and refuses duplicates` ("علا " then "علا" → `DuplicateNameException`; "" → `ArgumentError`); `renamePerson to its own name is allowed, to another's is refused`; `balances sum signed entries per person`; `entries come newest first`; `deletePerson removes their entries`; `restoreEntry brings back the same id`; `every write bumps database.revision`.
- [ ] **Step 2:** `flutter test test/data/repositories/debt_repository_people_test.dart` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: debt repository for people and entries`.

---

### Task 5: DebtRepository — obligations and payments

**Files:**
- Modify: `lib/app/data/repositories/debt_repository.dart`
- Test: `test/data/repositories/debt_repository_obligations_test.dart`

**Interfaces:**
- Produces:
  - `class OverpaymentException implements Exception { const OverpaymentException(this.remaining); final int remaining; }`
  - `class AmountBelowPaidException implements Exception { const AmountBelowPaidException(this.paid); final int paid; }`
  - `Future<List<Obligation>> getObligations()`, `Future<Obligation?> getObligation(int id)`
  - `Future<Obligation> addObligation(Obligation o)` (title trimmed, `ArgumentError` if empty)
  - `Future<void> updateObligation(Obligation o)` — in one transaction; throws `AmountBelowPaidException(paid)` when `o.amount < paid`.
  - `Future<void> deleteObligation(int id)` — payments cascade; their expense transactions stay.
  - `Future<Map<int, int>> paidTotals()`, `Future<List<ObligationPayment>> getPayments(int obligationId)` (`date DESC, id DESC`)
  - `Future<List<String>> recentTitles({int limit = 5})` — distinct titles, most recently created first.
  - `Future<ObligationPayment> pay({required int obligationId, required int amount, required DateTime date, int? expenseCategoryId})` — one transaction: read remaining; `amount <= 0` → `ArgumentError`; `amount > remaining` → `OverpaymentException(remaining)`; when `expenseCategoryId != null` insert an expense into `transactions` (amount, category, date, `note` = obligation title, `created_at` now) and store its id as `transaction_id`; insert the payment.
  - `Future<void> deletePayment(ObligationPayment p)` — one transaction: delete the payment and, when `p.transactionId != null`, that transaction.
  - `Future<Map<int, String>> linkedExpenses()` — `transaction_id → obligation title` for every payment with an expense.

- [ ] **Step 1: Write failing tests** — `pay with expense creates a linked expense in the same category and date`; `pay without expense leaves transactions untouched`; `pay refuses more than remaining` (600, pay 400, pay 300 → `OverpaymentException(200000)`, only one payment stored); `pay that fails half-way saves nothing` (pass a non-existent category id → FK error → no payment, no transaction); `deletePayment removes its expense even after it was edited` (pay with expense, change the transaction's date/category via `TransactionRepository.update`, delete payment → transaction gone); `updateObligation below paid is refused`; `deleteObligation keeps the expenses its payments created`; `recentTitles is distinct and newest first`; `linkedExpenses maps transaction ids to titles`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: obligations, atomic payments and linked expenses`.

---

### Task 6: Backup schema 2

**Files:**
- Modify: `lib/app/services/backup_service.dart`
- Test: `test/services/backup_service_test.dart` (add cases)

**Interfaces:**
- `BackupService.tables` becomes: `categories, savings_goals, recurring_rules, transactions, budgets, savings_movements, quick_templates, budget_alerts_sent, debt_people, debt_entries, obligations, obligation_payments, settings`.
- Export writes `schemaVersion: AppDatabase.version` (2). `parse`: version 1 → debt tables default to `[]` when absent; version 2 → all tables required; `_checkTypes` gains the four `fromMap` readers; reference check: every `debt_entries.person_id` is a `debt_people.id`, every `obligation_payments.obligation_id` is an `obligations.id`, every non-null `transaction_id` is a `transactions.id` — otherwise `BackupFormatException(_notABackup)`.

- [ ] **Step 1: Write failing tests** — `export then restore keeps people, entries, obligations and payments`; `a version-1 backup restores with no debts` (export, drop the 4 keys, set `schemaVersion: 1`, restore → debt tables empty, transactions intact); `a payment pointing at a missing transaction is rejected cleanly` (expect `BackupFormatException`, current data untouched); update the existing "newer version" test to use `AppDatabase.version + 1`.
- [ ] **Step 2:** `flutter test test/services/backup_service_test.dart` → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** → PASS.
- [ ] **Step 5:** Commit `feat: back up and restore debts (backup schema 2)`.

---

### Task 7: Debts screen — tabs and people list

**Files:**
- Move: `lib/app/modules/transaction_form/widgets/amount_field.dart` → `lib/app/widgets/amount_field.dart` (update imports; move `test/modules/transaction_form/amount_field_test.dart` → `test/widgets/amount_field_test.dart`)
- Modify: `lib/app/routes/app_routes.dart`, `lib/app/routes/app_pages.dart`
- Create: `lib/app/modules/debts/bindings/debts_binding.dart`, `controllers/debts_controller.dart`, `views/debts_view.dart`, `widgets/people_tab.dart`, `widgets/add_person_dialog.dart`
- Test: `test/modules/debts/debts_controller_test.dart`

**Interfaces:**
- Routes: `Routes.debts = '/debts'`, `Routes.debtPerson = '/debt-person'`, `Routes.obligationForm = '/obligation-form'` (the last two pages are registered in Tasks 8 and 9).
- `enum DebtsTab { people, obligations }` (in `debts_controller.dart`); `Routes.debts` argument is a `DebtsTab` (default `people`).
- `DebtsController({required DebtRepository debts, required CategoryRepository categories, required SettingsService settings, required DatabaseService database, DebtsTab initialTab = DebtsTab.people, DateTime Function()? clock})`:
  - `tab` (`Rx<DebtsTab>`), `people` (`RxList<PersonBalance>`), `unpaid` / `paid` (`RxList<ObligationStatus>`), `totals` (`Rx<DebtTotals>`), `showPaid` (`RxBool`), `currency`, `today`.
  - `Future<void> load()` (reloads on `database.revision` like `SavingsController`).
  - `Future<String?> addPerson(String name)` → `null` on success, else the message `'هذا الاسم موجود مسبقًا'` / `'اكتب الاسم'`.
  - `void openPerson(PersonBalance p)` → `Get.toNamed(Routes.debtPerson, arguments: p.person.id)`.
- View: app bar "الديون"; `SegmentedButton<DebtsTab>` with `'الأشخاص'` / `'عليّ'` (same look as `KindToggle`); People tab per §6.2.1 and the mockup (two tiles "المستحق لي"/"المستحق عليّ", rows with letter avatar, sub-line "مستحق لك"/"مستحق عليك"/"لا يوجد دين", coloured amount via `MoneyText`); FAB label `'إضافة شخص'` on the people tab; empty state `'لا يوجد أشخاص بعد'` with the hint `'أضف شخصًا لتسجيل ما بينكما من ديون'`. Obligations tab shows a placeholder until Task 9. `AddPersonDialog` is a `StatefulWidget` owning its controller, returns the typed name; the view calls `addPerson` and shows the returned message inline.

- [ ] **Step 1: Write failing tests** — `loads people ordered with totals`; `addPerson returns the duplicate message and saves nothing`; `opens on the tab passed in`; `reloads after a repository write`.
- [ ] **Step 2:** `flutter test test/modules/debts/debts_controller_test.dart` → FAIL.
- [ ] **Step 3:** Implement; register `GetPage(name: Routes.debts, ...)`.
- [ ] **Step 4:** `flutter test` → PASS; `flutter analyze` clean.
- [ ] **Step 5:** Commit `feat: debts screen with people tab`.

---

### Task 8: A person's page

**Files:**
- Create: `lib/app/modules/debt_person/bindings/debt_person_binding.dart`, `controllers/debt_person_controller.dart`, `views/debt_person_view.dart`, `widgets/entry_sheet.dart`, `widgets/person_actions_sheet.dart`
- Modify: `lib/app/routes/app_pages.dart`
- Test: `test/modules/debt_person/debt_person_controller_test.dart`, `test/modules/debt_person/entry_sheet_test.dart`

**Interfaces:**
- `class EntryDraft { final int amount; final DateTime date; final String? note; }` — `amount` already signed.
- `EntrySheet({required bool gave, required String personName, required DateTime today, DebtEntry? editing})` — `StatefulWidget`; amount via `AmountField` (autofocus), a direction `SegmentedButton` (`'أعطيتُ'` / `'أخذتُ'`) shown only when editing, date (default today, picker), note; "حفظ" pops an `EntryDraft`.
- `DebtPersonController({required DebtRepository debts, required SettingsService settings, required DatabaseService database, required int personId, DateTime Function()? clock})`:
  - `person` (`Rxn<DebtPerson>`), `balance` (`RxInt`), `entries` (`RxList<DebtEntry>`).
  - `Future<bool> addEntry(EntryDraft d)`, `Future<bool> updateEntry(DebtEntry old, EntryDraft d)`, `Future<DebtEntry?> deleteEntry(DebtEntry e)` (returns it for Undo), `Future<void> undoDelete(DebtEntry e)`.
  - `Future<String?> rename(String name)` (same messages as Task 7), `Future<bool> deletePerson()`.
- View per §6.2.2: card text `'المستحق لك عند {name}'` / `'المستحق عليك لـ{name}'` / `'لا يوجد دين'`; rows `'أعطيتُ'` (up arrow, green) / `'أخذتُ'` (down arrow, red) with `ArabicDates.dayMonth` and note; bottom buttons `'أعطيتُ {name}'` and `'أخذتُ من {name}'`; long-press row → sheet with "تعديل" / "حذف"; delete shows a snackbar `'حُذف السجل'` with action `'تراجع'`; app-bar edit → `PersonActionsSheet` (rename field, "حذف الشخص" → confirm dialog `'سيُحذف {name} وكل سجله'` plus, when the balance is not 0, a second line with the card text and amount (e.g. `'المستحق لك عند علا 980.000'`), then `Get.back()` to the list).

- [ ] **Step 1: Write failing tests** — controller: `a gave entry adds a positive amount and raises the balance`; `a took entry adds a negative amount`; `editing can flip the direction`; `delete then undo restores the entry`; `rename to an existing name returns the message`; `deletePerson removes everything`. Widget: `EntrySheet returns a negative amount for took` (pump the sheet, enter `'2.5'`, tap حفظ → draft amount `-2500`).
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Implement; register `GetPage(name: Routes.debtPerson, ...)` (binding reads `Get.arguments as int`).
- [ ] **Step 4:** `flutter test` → PASS.
- [ ] **Step 5:** Commit `feat: person page with entries`.

---

### Task 9: Obligations tab, obligation form, pay sheet

**Files:**
- Create: `lib/app/modules/debts/widgets/obligations_tab.dart`, `widgets/pay_sheet.dart`, `widgets/payments_sheet.dart`
- Create: `lib/app/modules/obligation_form/bindings/obligation_form_binding.dart`, `controllers/obligation_form_controller.dart`, `views/obligation_form_view.dart`
- Modify: `lib/app/modules/debts/controllers/debts_controller.dart`, `views/debts_view.dart`, `lib/app/routes/app_pages.dart`
- Test: `test/modules/debts/debts_obligations_test.dart`, `test/modules/debts/pay_sheet_test.dart`, `test/modules/obligation_form/obligation_form_controller_test.dart`

**Interfaces:**
- `class PayDraft { final int amount; final DateTime date; final int? expenseCategoryId; }`
- `PaySheet({required ObligationStatus status, required List<TransactionCategory> expenseCategories, required int? defaultCategoryId, required DateTime today, required Currency currency})` — `StatefulWidget`; field pre-filled with `Money.toEditable(remaining)`; buttons `'المبلغ كاملًا ({remaining})'` and `'جزء منه'`; error text `'أكبر من المتبقي'` and disabled "تسديد" when amount > remaining; checkbox `'سجّله مصروفًا'` (default on) with `'يُخصم من «المتبقي من الراتب» ضمن تصنيف {name} · تغيير'`; pops a `PayDraft`.
- `DebtsController` gains: `expenseCategories` (active expense categories), `int? get defaultExpenseCategoryId` (category with `iconKey == 'bills'`, else first active expense), `isSaving` (`RxBool`), `Future<bool> pay(ObligationStatus s, PayDraft d)` (ignored while saving; on `OverpaymentException` → message `'المبلغ أكبر من المتبقي ({remaining})'`; when it completes the obligation, `lastNotice.value = 'تم سداد {title}'` for the view's snackbar), `Future<void> deleteObligation(ObligationStatus s)`, `Future<List<ObligationPayment>> paymentsOf(ObligationStatus s)`, `Future<void> deletePayment(ObligationPayment p)`, `void openNewObligation()`, `void openEditObligation(ObligationStatus s)`, `DueInfo dueOf(ObligationStatus s)` (only for dated ones).
- `ObligationFormController({required DebtRepository debts, required SettingsService settings, int? editId, DateTime Function()? clock})`: `amountController` (+ `amountText`), `titleController`, `noteController`, `dueDate` (`Rxn<DateTime>`), `recentTitles`, `isEditing`, `inputDecimals`, `bool get canSave`, `Future<bool> save()` (on `AmountBelowPaidException` → `'لا يمكن أن يقل المبلغ عن المدفوع ({paid})'`), `Future<bool> delete()`.
- Obligations tab per §6.2.3 / mockup: tile `'المبلغ المستحق عليّ'` + `'{n} التزامات · أقربها {dueLabel}'`; cards with title, due line `'يستحق في {dayMonth} · {dueLabel}'` (warning colour when `daysLeft <= 3`) or `'بلا موعد محدد'`, remaining, `'سُدِّد {paid} من {amount}'` + `LinearProgressIndicator` when partly paid; collapsible `'تم سدادها ({n})'`; empty `'لا توجد التزامات'`; FAB `'التزام جديد'`; tap → `PaySheet`; long-press → "تعديل" / "السجل" (`PaymentsSheet`: payments with date, amount, `'مسجّل مصروفًا'` tag, delete button) / "حذف".
- Form per §6.2.4: titles `'التزام جديد'` / `'تعديل الالتزام'`; labels `'لمن أو ما هو؟'`, `'تاريخ الاستحقاق (اختياري)'` (clear button), `'ملاحظة (اختياري)'`; `ActionChip`s from `recentTitles`.

- [ ] **Step 1: Write failing tests** — controller: `splits unpaid and paid in order`; `pay with the default category records a bills expense`; `a second pay while saving is ignored`; `paying the rest sets the paid notice`; `overpay shows the remaining in the message`; `default category falls back when bills is archived`. Pay sheet widget: `prefills the remaining and disables pay above it`; `unticking the expense returns a null category`. Form: `save creates an obligation with trimmed title and optional due date`; `cannot save without a title`; `editing below paid shows the paid amount`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Implement; register `GetPage(name: Routes.obligationForm, ..., fullscreenDialog: true)`.
- [ ] **Step 4:** `flutter test` → PASS.
- [ ] **Step 5:** Commit `feat: obligations tab, form and partial payments`.

---

### Task 10: Linked expenses are owned by their payment

**Files:**
- Modify: `lib/app/modules/transactions/controllers/transactions_controller.dart`, `views/transactions_view.dart`, `bindings/transactions_binding.dart`
- Modify: `lib/app/modules/transaction_form/controllers/transaction_form_controller.dart`, `views/transaction_form_view.dart`, `bindings/transaction_form_binding.dart`
- Test: `test/modules/transactions/transactions_controller_test.dart`, `test/modules/transaction_form/transaction_form_controller_test.dart` (add cases)

**Interfaces:**
- Both controllers gain `required DebtRepository debts`.
- `TransactionsController`: `linked` (`RxMap<int, String>` from `debts.linkedExpenses()`, loaded in `load()`); `bool canDelete(TransactionRecord t)`; view's `Dismissible.confirmDismiss` returns `false` for linked rows and calls `MessageService.showError('هذه العملية مرتبطة بتسديد «{title}»، احذفها من الديون')`.
- `TransactionFormController`: `linkedTitle` (`RxnString`); when set, the view makes the amount field read-only, hides the kind toggle and delete action, and shows `'مرتبطة بتسديد «{title}» — عدّلها من الديون'`; `save()` keeps the stored amount and kind for linked records; `delete()` returns false for them.

- [ ] **Step 1: Write failing tests** — `a payment's expense cannot be deleted from the list`; `editing a payment's expense keeps its amount and kind but saves the new category`; unlinked behaviour unchanged.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `flutter test` → PASS.
- [ ] **Step 5:** Commit `feat: lock expenses created by debt payments`.

---

### Task 11: Home — debts card, due banner, settle preview

**Files:**
- Create: `lib/app/modules/home/widgets/debts_card.dart`, `widgets/due_obligation_banner.dart`
- Modify: `lib/app/modules/home/controllers/home_controller.dart`, `views/home_view.dart`, `widgets/balance_card.dart`, `bindings/home_binding.dart`
- Test: `test/modules/home/home_controller_test.dart` (add cases), `test/modules/home/balance_card_test.dart`

**Interfaces:**
- `HomeController` gains `required DebtRepository debts`; `debtTotals` (`Rx<DebtTotals>`), `dueObligation` (`Rxn<DueInfo>`), `showSettled` (`RxBool`, false on every open), `void toggleSettled()`, `void openDebts([DebtsTab tab = DebtsTab.people])`.
- `BalanceCard` gains `DebtTotals? debts`, `bool showSettled`, `VoidCallback? onToggleSettled`. When `showSettled`: label `'المتبقي بعد تسوية الديون'`, big number `DebtSummary.settledRemaining(summary.remaining, debts)`, line `'المتبقي {remaining} + لي {owedToMe} − عليّ {iOwe}'`, button `'إخفاء'`; otherwise button `'بعد تسوية الديون'`. Button hidden when `debts == null || debts.isEmpty`.
- `DebtsCard({required DebtTotals totals, required Currency currency, required VoidCallback onTap})` — `'الديون'` + `'المستحق لي {x} · المستحق عليّ {y}'`, or `'سجّل ديونك والتزاماتك'` when empty.
- `DueObligationBanner({required DueInfo due, required Currency currency, required VoidCallback onTap})` — `'يستحق {title} ({remaining}) {dueLabel}'`; for overdue `'{title} ({remaining}) {dueLabel}'` (dueLabel already says "متأخر منذ …"). Tap → `openDebts(DebtsTab.obligations)`.
- Order on Home: balance card → debts card → due banner → month-end banner → budget banner → favorites → recent.

- [ ] **Step 1: Write failing tests** — controller: `debt totals include people and unpaid obligations`; `due banner picks the most urgent within 3 days`; `toggleSettled flips and starts off`. Widget (`BalanceCard`): `settle button switches number to remaining + owed − owe` (412.500 / 1,477 / 539.950 → `1,349.550`); `no settle button without debts`.
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `flutter test` → PASS.
- [ ] **Step 5:** Commit `feat: debts card, due reminder and settle preview on Home`.

---

### Task 12: End-to-end check and README

**Files:**
- Modify: `test/app_test.dart`, `README.md`

- [ ] **Step 1: Write the failing widget test** `owing the university: add, pay part as expense, Home updates` — boot; tap the Home debts card; tap `'عليّ'`; tap `'التزام جديد'`; enter amount `600`, title `'رسوم الجامعة'`; save; tap the card; tap `'جزء منه'`, enter `300`; tap `'تسديد'`; back to Home → `find.textContaining('-300.000')` in recent transactions and the debts card shows `300.000` owed. A second test: `lending to a person never changes the Home balance` (add person علا, `'أعطيتُ علا'` 50 → Home "المتبقي من الراتب" unchanged; settle button shows `+ لي 50.000`).
- [ ] **Step 2:** `flutter test test/app_test.dart` → PASS (fix any wiring gaps found).
- [ ] **Step 3:** README: add Debts to the feature list (two tabs, partial payments recorded as expenses, settle preview, backup schema 2).
- [ ] **Step 4:** `flutter analyze` clean, `flutter test` all PASS.
- [ ] **Step 5:** Commit `test: end-to-end debts flow; README`.

---

### Task 13: Standard Arabic (فصحى) across the app

**Files:**
- Modify: every file under `lib/` with user-visible Arabic (≈194 strings: views, widgets, controllers' messages, `MessageService` title `'صار خطأ'` → `'حدث خطأ'`, `NotificationService` texts, `BackupService` messages, `ArabicDates` stays), and the tests that look strings up.
- Create: `test/fusha_copy_test.dart`

**Interfaces:** none (copy only).

Rules (§6.5): same meaning and length, short فصحى; keep established words (مصروف، دخل، ميزانية، مدخرات، تراجع، حفظ). Use these exact replacements where they occur:
- `ما قدرنا نحفظ العملية، جرّب مرة ثانية` → `تعذّر حفظ العملية، حاول مرة أخرى` (same pattern for نحذف/نرجّع/نحفظ اختيارك → `تعذّر حذف…` / `تعذّرت استعادة…` / `تعذّر حفظ اختيارك`)
- `احفظها كمفضّلة (زر بضغطة وحدة بالرئيسية)` → `احفظها في المفضّلة (زر بنقرة واحدة في الرئيسية)`; `مفضّلة — بضغطة وحدة` → `المفضّلة — بنقرة واحدة`
- `الكلي معك` → `إجمالي ما لديك`; `انضافت: X` → `أُضيفت: X`
- `الملف مش نسخة احتياطية من مصاريفي` → `هذا الملف ليس نسخة احتياطية من مصاريفي`; `…حدّث التطبيق أول` → `…حدّث التطبيق أولًا`
- `لسا ما سجلت …` → `لم تسجّل … بعد`

- [ ] **Step 1: Write the failing test** `test/fusha_copy_test.dart` — reads every `.dart` file under `lib/`, extracts single-quoted string literals, and fails listing file:line for any literal containing a marker as a whole word (boundary = start/end or a non-Arabic-letter char; use `RegExp('(^|[^\\u0621-\\u064A])($markers)(?=\$|[^\\u0621-\\u064A])')`). Markers: `ما قدرنا, جرّب, جرب, مش, لسا, لسه, شو, لمين, هيك, بدك, بدي, انضاف, انضافت, هسا, هلأ, كمان, منيح, عشان, زي, اشي, شي, صار, نرجّع, وحدة`.
- [ ] **Step 2:** `flutter test test/fusha_copy_test.dart` → FAIL listing the current dialect strings.
- [ ] **Step 3:** Rewrite the strings; update widget/controller tests that match old text (`grep -rn` the old strings under `test/`).
- [ ] **Step 4:** `flutter test` → all PASS (including the scan); `flutter analyze` clean.
- [ ] **Step 5:** Commit `feat: standard Arabic (فصحى) throughout the app`.
