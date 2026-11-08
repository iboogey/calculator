# Debts and Obligations + Standard Arabic UI — Design Spec

**Date:** 2026-11-08
**Status:** Approved (2026-11-08)
**Builds on:** `docs/superpowers/specs/2026-10-01-expense-tracker-design.md` (moves "Debts and loans" out of §5 "Out of scope")
**Mockup (approved by the user, 2026-11-08):** https://claude.ai/artifact/CZyPJji129JRMWFE5crwfn — six screens: Home card, الأشخاص tab, a person's page, عليّ tab, new obligation form, pay sheet.

---

## 1. Why

The user tracks money with family in another app (one running total per person, entries "Borrow" / "Payment"). To record money *they* owe (a bank instalment, university fees), they had to fake a person called "انا" — and in this app they would have had to misuse a savings goal. They want both in this app, without that workaround.

Two different jobs, so two different tools:

1. **الأشخاص (people):** a running account with each person, where money goes back and forth over time (علا took 50, paid back 50, took 980 …). One balance per person; green = they owe me, red = I owe them.
2. **عليّ (obligations):** a flat list of things I must pay — "رسوم الجامعة 600, due 15 كانون الأول". No person to create first; one quick form. Pay all or part; paid items fold away.

Separately, the user asked that **the whole app use Modern Standard Arabic (فصحى)** instead of Jordanian dialect.

## 2. Goals

- See on Home, with one button, what the balance would be if all debts were settled (I pay what I owe, people pay me back).

- Record lending/borrowing with a person in a few taps, and always see who owes whom and how much.
- Record "I owe X for Y" in one form, without creating a person.
- Pay an obligation fully or partly; by default the payment is also recorded as an expense so the monthly balance stays true.
- See totals at a glance on Home: "المستحق لي · المستحق عليّ", and a reminder when an obligation is due within 3 days or overdue.
- Every user-visible Arabic string in the app is فصحى.

## 3. Non-goals

- No push notifications for due dates (Home banner only).
- No interest, instalment schedules, or recurring obligations.
- No shared/synced debts with other people; still single-user, offline.
- No contacts import; names are typed.
- No change to Reports (debts are not a category).

## 4. Anti-goals (would be a failure even if it works)

- Having to create a person or place before recording a bill/obligation.
- Debt payments silently changing "المتبقي من الراتب" without the user seeing it (the "سجّله مصروفًا" choice is always visible on the pay sheet).
- A balance that can't be explained by the history shown on the same screen.
- Losing debt data on backup/restore, or old backups no longer restoring.
- Any dialect left in the UI after the فصحى pass.

## 5. Constraints

All constraints of the base spec hold: offline, money as `int` thousandths (`Money`), dates as `YYYY-MM-DD` strings, Arabic RTL UI, GetX Pattern (module = bindings/controllers/views/widgets), controllers report `DatabaseException` through `MessageService`, writes call `DatabaseService.notifyChanged()`, dialogs that own a `TextEditingController` keep it in their own `State`. Amount inputs use the phone keyboard with `AmountInputFormatter` (as the transaction form now does).

---

## 6. Behaviour

### 6.1 Entry point (Home)

- A **الديون** card on Home, directly under the balance card: icon, title "الديون", and "المستحق لي **X** · المستحق عليّ **Y**". Tapping it opens the Debts screen on the الأشخاص tab.
  - X = sum of positive person balances. Y = sum of negative person balances (as a positive number) + sum of unpaid obligation remainders.
  - With no debt data at all, the card still shows, with the line "سجّل ديونك والتزاماتك".
- A **due banner** under the card when the nearest unpaid obligation with a due date is due within 3 days (today counts) or overdue:
  - "يستحق {title} ({remaining}) اليوم" / "خلال N أيام" / "متأخر منذ N أيام". Tapping opens the Debts screen on the عليّ tab. Only the single most urgent obligation is shown.
- **"بعد تسوية الديون" (after settling debts) button** on the balance card, under the breakdown line. Pressing it switches the big number to a preview: **المتبقي بعد تسوية الديون = المتبقي من الراتب + المستحق لي − المستحق عليّ** (عليّ = people I owe + unpaid obligation remainders, the same totals as the Debts card). The label above the number changes to "المتبقي بعد تسوية الديون", the breakdown line becomes "المتبقي {remaining} + لي {X} − عليّ {Y}", and the button reads "إخفاء" (hide). Pressing again goes back. It is a view only: nothing is saved or recorded, and the choice is not remembered after leaving Home. The button is hidden when X and Y are both 0.
- The bottom navigation does not change (still 5 tabs).

### 6.2 Debts screen

App bar "الديون" with back. A two-segment toggle in the same style as the مصروف | دخل toggle: **الأشخاص | عليّ**. The selected tab is passed as a route argument (default الأشخاص).

#### 6.2.1 الأشخاص tab

- Two summary tiles: "المستحق لي" (green, sum of positive balances) and "المستحق عليّ" (red, sum of negative balances as positive).
- One row per person: letter avatar (first letter of the name), name, a sub-line ("مستحق لك" / "مستحق عليك" / "لا يوجد دين"), and the balance (green / red / grey "0").
- Order: non-zero balances first, by absolute balance descending; settled people last, by name.
- FAB "إضافة شخص" → a dialog with one name field. Names are trimmed; an empty name or a name already used (case-insensitive, trimmed) is refused with "هذا الاسم موجود مسبقًا".
- Empty state: "لا يوجد أشخاص بعد" with a hint to add one.

#### 6.2.2 A person's page

- App bar: the person's name; an edit action opens a sheet with **rename** (same uniqueness rule) and **delete person**. Delete asks for confirmation ("سيُحذف {name} وكل سجله") and removes the person and all their entries.
- Big card: "المستحق لك عند {name}" (balance > 0) / "المستحق عليك لـ{name}" (< 0) / "لا يوجد دين" (0), with the absolute amount.
- History, newest first (date DESC, id DESC): an up arrow + "أعطيتُ" for positive entries, a down arrow + "أخذتُ" for negative ones; date (`ArabicDates`), optional note, signed amount.
- Two bottom buttons: **أعطيتُ {name}** and **أخذتُ من {name}**. Each opens an entry sheet: amount (phone number keyboard), date (default today), note (optional), "حفظ".
  - "أعطيتُ" stores a positive amount (they owe me more, or I paid back what I owed).
  - "أخذتُ" stores a negative amount (I owe them more, or they paid me back).
  - A repayment is just the opposite button — there are no other entry types.
- Long-press on an entry → edit (same sheet, pre-filled, direction switchable) or delete (with Undo snackbar).

#### 6.2.3 عليّ tab

- One summary tile: "المبلغ المستحق عليّ" = sum of unpaid remainders, and "N التزامات · أقربها خلال N أيام" when one has a due date.
- One card per **unpaid** obligation (remaining > 0): title, a due line ("يستحق في {date} · خلال N أيام" in warning colour when ≤ 3 days or overdue; "بلا موعد محدد" when none), remaining amount, "سُدِّد X من Y" and a progress bar when partly paid.
- Order: by due date ascending (no due date last), then by creation.
- A collapsed section "تم سدادها (N)" listing fully paid obligations (greyed). Expand/collapse is in-memory only.
- FAB "التزام جديد" → the obligation form.
- Tap a card → the pay sheet. Long-press → edit / delete.
- Empty state: "لا توجد التزامات".

#### 6.2.4 Obligation form (new / edit)

Full-screen dialog, title "التزام جديد" / "تعديل الالتزام":
- Amount (big field, phone number keyboard, autofocus on new).
- "لمن أو ما هو؟" — free text, required, trimmed. Under it up to 5 quick-pick chips: the most recent distinct titles used before (none on first use).
- "تاريخ الاستحقاق (اختياري)" — date picker, clearable.
- "ملاحظة (اختياري)".
- "حفظ" enabled when amount and title are valid.
- On edit, the amount cannot go below what has already been paid (refused with a message showing the paid amount).
- Edit screen has a delete action. Deleting an obligation deletes its payments; any expenses those payments created stay in العمليات (they really were spent).

#### 6.2.5 Pay sheet

Bottom sheet, title "تسديد {title}", sub-line "المتبقي عليك {remaining} من {amount}":
- "المبلغ المدفوع" amount field, pre-filled with the full remaining amount; quick buttons "المبلغ كاملًا ({remaining})" and "جزء منه" (clears the field and focuses it).
- An amount above the remaining is refused (field shows an error, "تسديد" disabled).
- Checkbox **سجّله مصروفًا** — on by default — with the line "يُخصم من «المتبقي من الراتب» ضمن تصنيف {category} · تغيير". "تغيير" opens a picker of active expense categories. Default category: the one with `icon_key = 'bills'` (فواتير); if archived/missing, the first active expense category.
- Date, default today (tap to change).
- "تسديد" saves, in **one database transaction**: the payment row and, when the checkbox is on, an expense transaction (amount, category, date, note = obligation title) whose id is stored on the payment.
- When the payment completes the obligation, show a snackbar "تم سداد {title}".
- In the paid section, long-press a paid obligation → delete. Inside an obligation (long-press → "السجل"), payments can be deleted; deleting a payment also deletes the expense it created (same transaction), so the balance on Home goes back.

### 6.3 Money math

- Person balance = Σ entries.amount (signed). > 0 they owe me; < 0 I owe them.
- Obligation remaining = amount − Σ payments.amount; paid when remaining == 0. Remaining is never negative (enforced on pay and on edit).
- **People entries do not change "المتبقي من الراتب" or "الكلي معك"** (user, 2026-11-08). The user sees their effect on demand through the "بعد تسوية الديون" preview on Home (§6.1).
- Obligation payments change the balance only through the expense transaction they optionally create — no new term in `BalanceCalculator`.

### 6.4 Backup and restore

- `BackupService.tables` gains the four new tables (parents before children: `debt_people`, `debt_entries`, `obligations`, `obligation_payments` after `transactions`, since payments reference transactions).
- Export writes `schemaVersion: 2`.
- Restore accepts `schemaVersion` 1 and 2. A version-1 file has no debt tables; they restore as empty (restore still replaces everything, as today). Version > 2 is refused as "newer".
- `_checkTypes` validates the new rows via the new models' `fromMap`.
- `payment.transaction_id` pointing at a transaction missing from the file is refused as not-a-backup (foreign key would fail anyway; the message must be the normal one, not a crash).

### 6.5 Standard Arabic (فصحى) pass

- Every user-visible Arabic string under `lib/` (≈194: labels, hints, buttons, snackbars, dialogs, error messages, notification titles/bodies, empty states, backup messages) is rewritten in clear, short فصحى. Category seed names stay (they are already standard: أكل may become طعام — see §10).
- Meaning and tone stay the same; no new information is added.
- Examples: "ما قدرنا نحفظ العملية، جرّب مرة ثانية" → "تعذّر حفظ العملية، حاول مرة أخرى"; "احفظها كمفضّلة (زر بضغطة وحدة بالرئيسية)" → "احفظها في المفضّلة (زر بنقرة واحدة في الرئيسية)"; "الكلي معك" → "إجمالي ما لديك"; "لسا ما سجلت" → "لم تسجّل … بعد"; "انضافت: X" → "أُضيفت: X"; "تراجع" stays; "الملف مش نسخة احتياطية من مصاريفي" → "هذا الملف ليس نسخة احتياطية من مصاريفي"; "حدّث التطبيق أول" → "حدّث التطبيق أولًا".
- Dialect markers that must not remain anywhere in `lib/`: ما قدرنا، جرّب، مش، لسا، وحدة (as "one"), شو، لمين، هيك، بدك، انضاف، هسا، كمان، اشي/شي (as "thing"), منيح، عشان، زي.
- Tests that find widgets by text are updated to the new strings.
- Existing user data is not migrated (category names a user already has stay as stored).

---

## 7. Data model (schema version 2)

```sql
CREATE TABLE debt_people (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE debt_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  person_id INTEGER NOT NULL REFERENCES debt_people(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount <> 0),   -- + I gave, − I took
  date TEXT NOT NULL,
  note TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_debt_entries_person ON debt_entries(person_id);
CREATE TABLE obligations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0),
  due_date TEXT,
  note TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE obligation_payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  obligation_id INTEGER NOT NULL REFERENCES obligations(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  date TEXT NOT NULL,
  transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_obligation_payments_obligation ON obligation_payments(obligation_id);
```

- `AppDatabase.version` becomes 2. `onCreate` creates everything; a new `onUpgrade` runs the statements above when `oldVersion < 2`. Existing data is untouched. (This is the app's first migration; the schema list is split into v1 statements and v2 statements so both paths share them.)
- Uniqueness of person names is enforced in the repository (case-insensitive, trimmed), not by a constraint, so restore of odd data does not fail.

## 8. Architecture

New pieces, following the existing patterns (`SavingsRepository`, `savings` / `goal_detail` / `goal_form` modules):

- **Models** (`lib/app/data/models/`): `DebtPerson`, `DebtEntry`, `Obligation`, `ObligationPayment` — immutable, `fromMap` / `toMap` / `==`, like `SavingsMovement`.
- **Pure logic** (`lib/app/core/logic/debt_summary.dart`): person balances, people ordering, obligation remaining/paid, totals (المستحق لي / عليّ), and the most urgent due obligation for a given "today" (days until due, overdue). Fully unit-tested, no database.
- **Repository** (`lib/app/data/repositories/debt_repository.dart`), one class for both parts:
  - people: `getPeople`, `addPerson` (throws `DuplicateNameException`), `renamePerson`, `deletePerson`, `getEntries(personId)`, `addEntry`, `updateEntry`, `deleteEntry`, `balances()`.
  - obligations: `getObligations`, `addObligation`, `updateObligation` (throws `AmountBelowPaidException(paid)`), `deleteObligation`, `getPayments(obligationId)`, `paidTotals()`, `recentTitles(limit)`.
  - `pay(obligationId, amount, date, {expense: (categoryId)?})` — one transaction; throws `OverpaymentException(remaining)`; inserts the expense transaction first and stores its id.
  - `deletePayment(payment)` — one transaction; also deletes the linked transaction.
  - Every write calls `notifyChanged()`; registered permanently in `InitialBinding`.
- **Modules** (`lib/app/modules/`):
  - `debts` — the tabbed screen (people list + obligations list), add-person dialog, pay sheet.
  - `debt_person` — a person's page, entry sheet, rename/delete sheet.
  - `obligation_form` — new/edit obligation (full-screen dialog).
- **Routes:** `Routes.debts` (argument: initial tab), `Routes.debtPerson` (argument: person id), `Routes.obligationForm` (argument: obligation id or null).
- **Home:** `HomeController` loads debt totals and the most urgent obligation through `DebtRepository` + `DebtSummary`; new widgets `DebtsCard` and `DueObligationBanner`.
- **Transactions module:** the transaction form and list ask `DebtRepository.isPaymentExpense(transactionId)` (or a set of linked ids) to lock amount/kind and block delete for linked expenses (§9).
- **Shared widget:** the big amount field (`AmountField` + `AmountInputFormatter`) moves from `modules/transaction_form/widgets/` to `lib/app/widgets/` so the obligation form, pay sheet and entry sheet reuse it.

## 9. Error handling and edge cases

- Database failures → `MessageService.showError` with a فصحى message; nothing half-saved (pay and delete-payment are single transactions).
- Overpay / amount below paid / duplicate name → refused with a specific message, nothing saved.
- Two quick taps on "تسديد" → second is ignored while saving (same `isSaving` guard as the transaction form).
- Deleting a person with a non-zero balance → allowed after the confirmation that names the balance.
- **An expense created by a payment belongs to that payment** *(builder's call)*. In العمليات its amount and kind are read-only and it cannot be deleted or swiped away; the form shows "مرتبطة بتسديد «{title}» — عدّلها من الديون". Date, category and note stay editable. It changes or disappears only through the payment (delete payment → its expense goes too). So a payment and its expense never disagree, and the transaction-list Undo never meets a linked row. (`ON DELETE SET NULL` stays as a safety net for restore of odd data.)
- Category picked for the expense later archived → the payment's expense is unaffected; the pay sheet's default falls back as in §6.2.5.
- Due-date arithmetic uses date-only values (`DateKeys.dateOnly`), so "today" never shows as "خلال 0 أيام" — it shows "اليوم".

## 10. Left to the builder

- **Branching** *(builder's call)*: the phone-keyboard amount field change is committed first on `feature/phase-3-insight`; this work goes on a new branch `feature/debts-fusha` cut from it.

- Exact فصحى wording of each string, within §6.5's rules and examples. Category seed "أكل" → "طعام" only for new installs (seed), existing rows untouched.
- Icons (Material) for the Home card, arrows, obligation cards.
- Layout details within the mockup's look; widget split inside each module.
- Snackbar Undo for entry delete follows the existing transaction-list pattern.

## 11. Open questions for the user

- ~~Q1~~ Answered 2026-11-08: people entries stay out of the balance; instead Home gets the "بعد تسوية الديون" preview button (§6.1).

## 12. Testing

TDD as in the base spec:
- `DebtSummary` unit tests: balances, ordering, totals, remaining, due-soon/overdue/today, no due dates.
- Repository tests on the in-memory database: duplicate names, cascade deletes, overpay refused, pay with/without expense (transaction row + link), delete payment removes its expense, edit below paid refused, migration v1 → v2 keeps old data and adds tables.
- Backup tests: v2 round-trip includes debts; v1 file restores with empty debts; dangling `transaction_id` refused cleanly.
- Controller tests for debts, person page, obligation form, pay sheet; Home card totals, due banner, and the settle-preview number (remaining + لي − عليّ, toggling, hidden when no debts).
- An end-to-end widget test: Home card → عليّ → new obligation → pay part with expense → Home balance and card update.
- A test that scans `lib/` for the dialect markers in §6.5 and fails if any remain.
