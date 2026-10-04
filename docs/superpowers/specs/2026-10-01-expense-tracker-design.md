# Personal Expense Tracker — Design Spec

**Date:** 2026-10-01
**Status:** Approved (2026-10-01)
**Project:** `calculator` (Flutter app, currently the default counter template)

---

## 1. Goal

A personal, single-user Flutter app to track monthly income and expenses, control spending with budgets, and save toward goals.

- **User:** one person (the owner). No family or shared accounts.
- **Purpose:** real daily use, and part of the "Flutter with AI" course. It will be published on GitHub, so the code must be clean and well organized.
- **Success means:**
  - Logging an expense takes under 5 seconds.
  - The user always knows (a) how much is left from the salary this period and (b) how much is saved in total.
  - The user still uses the app after the first two weeks.

## 2. Hard constraints

- **Local only.** No sign-in, no accounts, no server, no cloud, no analytics. All data lives on the device.
- **No internet.** The app works fully offline and makes no network calls. The internet permission is removed from the Android manifest in release builds.
- **Platforms:** Android and iOS (the project already has both).

## 3. Decisions made in the interview

| # | Decision | Source |
|---|---|---|
| D1 | All 6 core features are in scope: categories and breakdown, budgets and alerts, fast entry and daily reminder, recurring fixed costs, savings goals, and month-to-month comparison. | User |
| D2 | Build in 3 phases. The data model is designed up front for all phases. | Recommended, user agreed to continue |
| D3 | Savings work the **hybrid** way: manual transfers to goals, a month-end prompt to move leftover money, optional recurring monthly savings, and a **General Savings** pot for money with no specific goal. | User |
| D4 | Two headline numbers on the home screen: **Remaining from salary** and **Total savings**, plus **Total you have** = both together. | User |
| D5 | The UI follows the approved mockup: Home, Add Transaction, Budgets and Recurring, Reports and Goals. | User |
| D6 | **Backup and restore** (a local JSON file) is in scope, in Phase 3. | User |
| D7 | **GetX** for state management, dependency injection and routing, following the **GetX Pattern** folder structure. Controllers, services, screens (views) and widgets each live in their own folders. | User |
| D8 | Pub.dev packages are allowed if they work fully offline. "Nothing external" means no external *services*. | User (implied by choosing GetX) |

## 4. Confirmed details

| # | Assumption | Why |
|---|---|---|
| A1 | **Currency is the Jordanian Dinar (JOD, 3 decimals)**, with the currency configurable in Settings. | User confirmed |
| A2 | **The UI is in Arabic (RTL).** Code, comments and the README are in English, for GitHub. | User confirmed |
| A3 | **The financial month starts on day 1 by default.** The user can change the start day (1–28), for example to salary day, in Settings. | User confirmed |
| A4 | **Quick favorites** ("Coffee · 1.500", saved with one tap) are included. | Shown in the mockup, not objected to |

## 5. Out of scope (for now)

These came from the extras list, and the user has not chosen them yet. Each can be added later without changing the core design.

- CSV export for spreadsheets (the JSON backup in D6 covers safety)
- App lock (PIN or biometrics)
- Multiple wallets or accounts (cash, bank, e-wallet)
- Debts and loans
- Search and filters (beyond the basic list)
- Receipt photos
- Home-screen widget
- English UI and dark mode

---

## 6. Core concepts and the money math

### 6.1 Money representation
All amounts are stored as **integers in thousandths of the currency unit** (for JOD, 1 dinar = 1000 fils). The scale is always 1000, even for a 2-decimal currency, so switching currency in Settings never changes what stored amounts mean. There are **no floating-point numbers** anywhere in storage or calculations. Formatting to "1,250.000 د.أ" happens only in the UI.

### 6.2 Financial period
- A **period** runs from `startDay` of one month to `startDay − 1` of the next month. Example: start day 25 means 25 Sep to 24 Oct.
- `startDay` is limited to 1–28, so every month has that day.
- A period is identified by a key such as `2026-09`, the month in which it starts.

### 6.3 The three numbers (decision D4)
Every movement of money falls into exactly one of these kinds:

| Kind | Effect on Remaining | Effect on Savings | Counted as spending in reports? |
|---|---|---|---|
| Income | + | — | no (shown as income) |
| Expense | − | — | **yes** |
| Saving deposit (to a goal or General Savings) | − | + | no |
| Saving withdrawal | + | − | no |

- **Remaining from salary** = all-time income − all-time expenses − all-time net savings.
  - Leftover money that is not moved to savings **carries over automatically** into the next period. Nothing is lost, and there is no stored "carryover" field that could go out of sync.
  - The home card breaks this period down as: carried over + income − expenses − saved this period.
- **Total savings** = the sum of all saving movements, across every goal and General Savings.
- **Total you have** = Remaining + Total savings.

Example (from the interview): salary 1,250, spent 600, moved 150 to goals. Remaining = 500. If savings before were 760, Total savings = 910 and Total = 1,410.

### 6.4 Savings — hybrid flow (decision D3)
1. **Manual:** on any goal, tap Add or Withdraw and enter an amount. Withdrawing more than the goal holds is blocked.
2. **Month-end prompt:** the first time the app opens after a period ends, if the closed period left a **positive** remaining, a sheet asks: "You have X left. Move some to savings?" The user can split the amount across goals and General Savings, or skip. The prompt is shown once per period.
3. **Recurring savings:** a recurring rule can be of type *saving*, for example 50 JOD to Laptop every salary day. It uses the same engine as recurring expenses (6.5).
4. **General Savings:** a built-in pot with no target that cannot be deleted.
5. **Goal projection:** if a goal has a target amount and a target date, the app shows "Save X / month to reach it", calculated as (target − saved) ÷ the number of remaining periods, rounded up.

### 6.5 Recurring rules
- A rule has: a type (income, expense or saving), an amount, a category or goal, a day of the month, a start date, and an active flag.
- **There is no background process.** When the app opens, the generator creates every occurrence that is due but missing, from the rule's last generated date up to today. This catch-up also covers weeks when the app was not opened.
- **Idempotent:** each generated entry stores `(ruleId, dueDate)` with a unique constraint, so running the generator twice never creates duplicates.
- Generated entries are normal transactions with an "Auto" badge. The user can edit or delete a single occurrence without affecting the rule.

### 6.6 Budgets
- Each budget is a monthly limit per expense category, and it applies to every period.
- Status = amount spent in the category this period ÷ the limit:
  - under 80%: normal
  - 80–99%: **warning** (orange)
  - 100% or more: **over budget** (dark red-brown)
- Alerts appear in-app as a banner on Home. A local notification fires the moment a newly saved expense crosses 80% or 100%, once per threshold per category per period.

### 6.7 Daily reminder
A local notification at a user-chosen time (default 21:00): "سجّلت مصاريف اليوم؟" It can be turned off in Settings. It is scheduled on the device and needs no internet.

### 6.8 Backup and restore (decision D6)
- **Export:** Settings → "Backup now" writes one JSON file, `masarifi-backup-YYYY-MM-DD.json`, that contains every table plus `schemaVersion`, `appVersion` and `exportedAt`. The OS share sheet then opens so the user chooses where to keep it (Files, Drive, email, and so on). The app itself uploads nothing.
- **Restore:** Settings → "Restore" opens a file picker. The app then:
  1. parses the file and checks `schemaVersion`. A file from a *newer* app version is rejected with a clear message.
  2. shows a summary ("124 transactions, 3 goals, from 2026-09-30") and asks for confirmation, because a restore **replaces all current data**.
  3. replaces everything inside **one database transaction**. If anything fails, the current data stays untouched.
- **Reminder:** if the last backup is more than 30 days old, Settings shows a gentle "Last backup: 34 days ago" hint. There is no automatic background backup.

---

## 7. Data model (SQLite)

| Table | Key fields |
|---|---|
| `categories` | id, name, iconKey, colorValue, kind (income/expense), sortOrder, isArchived |
| `transactions` | id, kind (income/expense), amountMinor, categoryId, date (local date), note?, recurringRuleId?, recurringDueDate?, createdAt — unique(recurringRuleId, recurringDueDate) |
| `budgets` | id, categoryId (unique), limitMinor |
| `recurring_rules` | id, kind (income/expense/saving), amountMinor, categoryId?, goalId?, dayOfMonth, startDate, lastGeneratedDate?, isActive, label |
| `savings_goals` | id, name, targetMinor?, targetDate?, isGeneral, isArchived, createdAt |
| `savings_movements` | id, goalId, amountMinor (+ for a deposit, − for a withdrawal), date, source (manual/monthEnd/recurring), recurringRuleId?, recurringDueDate?, note? — unique(recurringRuleId, recurringDueDate) |
| `quick_templates` | id, label, kind, amountMinor, categoryId, sortOrder |
| `budget_alerts_sent` | categoryId, periodKey, threshold (80/100) — primary key on all three, so each alert fires only once |
| `settings` (single row) | periodStartDay, currencyCode, currencyDecimals, reminderEnabled, reminderTime, lastMonthEndPromptPeriod?, lastBackupAt? |

- **Seed data on first launch:**
  - Expense categories: Food, Transport, Bills, Housing, Shopping, Entertainment, Health, Other.
  - Income categories: Salary, Other.
  - The General Savings pot.
- **Deleting** a category or goal that is in use **archives** it instead, so history is never broken.
- Every saving and recurring table exists **from Phase 1**, even before its UI does, so later phases need no risky migrations.

---

## 8. Architecture

### 8.1 Tech choices
| Concern | Choice | Reason |
|---|---|---|
| State, DI, routing | **get** (GetX) | User's choice (D7). Simple reactive state (`.obs` / `Obx`), bindings for dependency injection, named routes |
| Database | **sqflite** (SQLite, raw SQL) + **sqflite_common_ffi** (dev only, for in-memory DB in tests) | User's choice. Models map to rows with `toMap` / `fromMap`; schema versions via `onCreate` / `onUpgrade` |
| Notifications | **flutter_local_notifications** + **timezone** | Fully local scheduling |
| Charts | **fl_chart** | Pure Dart, offline |
| Formatting | **intl** | Number and date formatting, Arabic locale |
| Backup files | **path_provider**, **share_plus** (export), **file_picker** (restore) | Local file I/O plus the OS share sheet. The app itself never uploads anything |

### 8.2 The GetX Pattern

This follows the **GetX Pattern** "modules" structure (the one `get_cli` generates with `get create page:<name>`), with each kind of file in its own folder as requested.

**The layers, and what each one may do:**

| Layer | Folder | Responsibility | May depend on |
|---|---|---|---|
| **View (screen)** | `modules/<m>/views/` | A `GetView<XController>`. Only layout: reads `controller.x` inside `Obx`, calls controller methods on taps. **No logic, no arithmetic, no DB.** | its controller, widgets |
| **Widget** | `modules/<m>/widgets/` (screen-specific) and `app/widgets/` (shared) | Small, reusable UI parts that receive data through constructor parameters. Stateless where possible. | nothing except theme |
| **Controller** | `modules/<m>/controllers/` | A `GetxController`. Holds the screen state as `.obs` fields, handles user actions, calls repositories and services, and uses `core/logic` for calculations. | repositories, services, core |
| **Binding** | `modules/<m>/bindings/` | `Bindings.dependencies()` that `Get.lazyPut`s the module's controller. Wires the module when its route opens. | controllers |
| **Service** | `app/services/` | A `GetxService`: a long-lived app-wide singleton (database, notifications, settings, backup, startup). Registered once in `InitialBinding`. | repositories, core |
| **Repository** | `app/data/repositories/` | The only place that reads or writes data. Exposes `Future`s of models and bumps `DatabaseService.revision` after every write. | providers, models |
| **Provider** | `app/data/providers/` | The raw data source: the sqflite database, table SQL, seed and migrations. | — |
| **Model** | `app/data/models/` | Plain immutable data classes (Transaction, Category, Goal…) and enums. | — |
| **Core logic** | `app/core/logic/` | **Pure Dart** money math (balance, budget status, recurring generator, goal projection, period). No Flutter, no GetX, no DB, so it is fully unit-tested. | models |

**Data flows one way:** View → Controller → Repository → Provider (sqflite).

**How screens refresh (sqflite has no streams):** `DatabaseService` holds `final revision = 0.obs`. Every repository write runs `revision.value++` after it commits. Each controller loads its data in `onInit()` and registers `ever(db.revision, (_) => load())`, so any change anywhere (a new expense, a recurring entry, a restore) refreshes every open screen. Controller `.obs` fields → `Obx` rebuilds the View.

### 8.3 Folder structure
```
lib/
  main.dart                          # init services, runApp(App())
  app/
    app_widget.dart                  # GetMaterialApp: Arabic RTL locale, theme, initialRoute, getPages, initialBinding
    bindings/
      initial_binding.dart           # Get.put all GetxServices + repositories (permanent)
    routes/
      app_routes.dart                # abstract class Routes { static const HOME = '/home'; ... }
      app_pages.dart                 # List<GetPage>: route → view + binding
    core/
      theme/
        app_colors.dart              # colors from the mockup
        app_theme.dart               # ThemeData, IBM Plex Sans Arabic
      utils/
        money.dart                   # Money (int minor units) + parse/format
        date_utils.dart
      logic/                         # PURE Dart — unit-tested
        period.dart                  # period from startDay (6.2)
        balance_calculator.dart      # Remaining / Savings / Total (6.3)
        budget_status.dart           # thresholds (6.6)
        recurring_generator.dart     # catch-up of due occurrences (6.5)
        goal_projection.dart         # "save X / month" (6.4)
    data/
      models/                        # transaction.dart, category.dart, budget.dart, recurring_rule.dart,
                                     # savings_goal.dart, savings_movement.dart, quick_template.dart, app_settings.dart, enums.dart
      providers/
        app_database.dart            # sqflite open, CREATE TABLE SQL, seed, onUpgrade migrations
      repositories/                  # transaction_, category_, budget_, recurring_, savings_, template_, settings_repository.dart
    services/
      database_service.dart          # owns the AppDatabase instance
      settings_service.dart          # current AppSettings as .obs, used app-wide
      notification_service.dart      # daily reminder + budget alerts
      recurring_service.dart         # runs the generator, writes results
      backup_service.dart            # export / restore JSON (6.8)
      startup_service.dart           # launch sequence (8.4)
    widgets/                         # shared: money_text.dart, category_icon.dart, amount_keypad.dart,
                                     # progress_bar.dart, empty_state.dart, app_bottom_nav.dart
    modules/
      home/
        bindings/home_binding.dart
        controllers/home_controller.dart
        views/home_view.dart
        widgets/                     # balance_card.dart, budget_alert_banner.dart, quick_templates_row.dart, recent_transactions.dart
      transaction_form/              # add / edit transaction (same layout: bindings, controllers, views, widgets)
      transactions/                  # full list
      budgets/
      recurring/
      reports/
      savings/
      month_end/                     # month-end allocation sheet
      settings/                      # includes backup / restore actions
      categories/                    # manage categories
      templates/                     # manage favorites
test/
  core/logic/  core/utils/  data/repositories/  modules/   # mirrors lib/app
```

**Rules that keep it clean:**
1. One class per file, and the file is named after the class (`home_controller.dart` → `HomeController`).
2. A view never touches a repository or service directly. It always goes through its controller.
3. A controller never builds widgets and never imports `material.dart` for layout. The only exceptions are `Get.snackbar`, `Get.dialog` and `Get.toNamed`.
4. Money math only lives in `core/logic/`. Controllers call it; they do not re-implement it.
5. Navigation uses named routes only (`Get.toNamed(Routes.TRANSACTION_FORM, arguments: id)`).

### 8.4 Startup flow (`StartupService`)
1. Open the database and seed it on first run.
2. Run the recurring generator for every active rule.
3. If the previous period closed and was not prompted yet: queue the month-end savings sheet.
4. Make sure the daily reminder is scheduled to match Settings.
5. Show Home.

---

## 9. Screens

| Screen | Contents | Phase |
|---|---|---|
| **Home** | period dates; Remaining (large), with the income / expenses / saved breakdown; Total savings; Total you have; budget warning banner; quick favorites; last 5 transactions; + button | 1 (savings numbers become visible in 3) |
| **Add / Edit transaction** | Expense/Income toggle, number pad, category grid, optional note, date (defaults to today), Save | 1 |
| **Transactions list** | grouped by day, swipe to delete with Undo, tap to edit, filter by period | 1 |
| **Settings** | period start day, currency, reminder on/off and time, manage categories, manage favorites, Backup now / Restore with last-backup date | 1–3 |
| **Budgets** | per-category progress bars, set or edit limits | 2 |
| **Recurring** | list of rules with next due date, add/edit/pause | 2 |
| **Reports** | donut chart by category for a period, bar chart for the last 6 periods, % change vs. last period, period switcher | 3 |
| **Savings** | General Savings + goals (progress, projection), add/withdraw, movement history | 3 |
| **Month-end sheet** | leftover amount, split across goals, Skip | 3 |

Bottom navigation: Home · Reports · Budget · Settings. Savings is reached from Home and Reports.

---

## 10. Phases and deliverables

Each phase ends with a working app that can be used daily, and a GitHub-ready commit history.

**Phase 1 — Foundation (MVP)**
- Project setup: packages, lints, GetX Pattern folders, `GetMaterialApp`, routes, `InitialBinding`, theme, RTL Arabic, Android internet permission removed
- `Money`, `Period`, and the full sqflite schema with seed data
- Add / edit / delete transactions; transactions list
- Home with Remaining for the period (carryover included)
- Settings: period start day and currency

**Phase 2 — Control**
- Budgets with in-app warnings and threshold notifications
- Recurring rules (income and expense) with the catch-up generator
- Daily reminder notification
- Quick favorites

**Phase 3 — Insight and goals**
- Reports: donut chart and multi-period comparison
- Savings: General Savings, goals, add/withdraw, projection
- Recurring savings rules
- Month-end prompt
- Home shows Total savings and Total you have
- Backup (export JSON via the share sheet) and Restore (file picker, confirm, atomic replace)

---

## 11. Error handling and edge cases

- **Amount input:** must be greater than 0; a maximum of 9 digits before the decimal point; decimals limited to what the currency allows. Save is disabled until the amount is valid.
- **Remaining can go negative** (overspending). It is shown in red-brown with a minus sign and never hidden or clamped.
- **Withdrawing more than a goal holds** is blocked, with a message.
- **Editing old transactions** updates past periods automatically, because everything is computed and not stored.
- **Changing the period start day** only changes how periods are grouped. No data changes.
- **Database errors** show a snackbar and the action is not half-applied: multi-row writes such as the month-end split run inside one database transaction.
- **Notification permission denied:** the app still works. Settings shows that reminders are off and how to enable them.
- **Dates** are stored as local calendar dates (no time zone shifts). `createdAt` is a timestamp used only for ordering.

---

## 12. Testing strategy (TDD)

- **Unit tests (most important):** `money`, `period` (start days 1, 25 and 28; year boundaries), `balance_calculator` (the interview example must give 500 / 910 / 1,410), `budget_status` thresholds, `recurring_generator` (catch-up across several missed months, no duplicates on a rerun, paused rules), `goal_projection`.
- **Repository tests:** against an in-memory sqflite database (`sqflite_common_ffi`, `inMemoryDatabasePath`): seeding, archive-instead-of-delete, unique constraints, the month-end split as one atomic write, and a backup round trip (export → restore gives identical data; a newer `schemaVersion` is rejected; a corrupt file leaves the data untouched).
- **Controller tests:** each `GetxController` is tested with fake repositories injected through `Get.put` (`Get.testMode = true`, `Get.reset()` between tests). For example, `HomeController` exposes the right Remaining, Savings and Total values for given repository data.
- **Widget tests:** the add-transaction flow (enter an amount, pick a category, save, Home updates), and the budget warning banner appearing.
- Every phase ends with `flutter analyze` clean and all tests passing.

---
