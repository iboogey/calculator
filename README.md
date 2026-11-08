# مصاريفي — Personal Expense Tracker

A personal Flutter app for tracking monthly income and expenses.
Arabic (RTL) interface, no accounts: all data stays on the device in SQLite.
The app works offline; AI features only go online after you add your own key.

## Features
- Add, edit and delete income and expenses with a fast keypad and category grid
- Home: "Remaining from salary" for the current financial month (with carry-over), total savings,
  everything you have, a budget warning, the month-end savings question and one-tap favorites
- Transactions grouped by day, swipe to delete with Undo, browse previous months
- Reports: spending by category (donut) and the last 6 months compared
- Budgets per category with progress bars and alerts at 80 % and 100 %
- Savings: General Savings plus goals with targets, add/withdraw, "save X a month to reach it",
  a month-end split of what is left, and fixed monthly savings
- Fixed monthly income, expenses and savings (rent, salary, …) added automatically
- Debts: two tabs (People: money lent or borrowed with a running balance; Owed by me: obligations such as
  tuition, with a due date), partial payments that can be recorded as expenses (locked in Transactions),
  a due reminder on Home and a "after settling debts" preview of what is left (view only)
- Daily reminder notification (default 21:00), all scheduled on the device
- Backup to a JSON file (shared wherever you choose, schema version 2 including debts) and restore from it (v1 files still work)
- Smart import: bank SMS on the phone are read into a review list (approve or dismiss each one); Android only. Note: the `READ_SMS` permission blocks a future Play Store release
- AI (optional): pick Gemini, Claude or OpenAI in Settings and add your own API key (kept in the device's secure storage, never in the database or backups); it suggests categories for unknown shops. Only the shop name and city are sent. Test the connection from Settings
- Settings: month start day, currency, reminder, fixed costs, favorites, backup

See [the design spec](docs/superpowers/specs/2026-10-01-expense-tracker-design.md).

## Architecture — GetX Pattern

```
lib/app/
  modules/<feature>/
    bindings/     dependency injection for the screen (Get.lazyPut)
    controllers/  GetxController: screen state (.obs) and actions
    views/        GetView: layout only, rebuilt by Obx
    widgets/      widgets used only by this screen
  services/       GetxService singletons: database, settings, notifications,
                  budget alerts, startup (recurring catch-up on start/resume),
                  backup, messages
  data/
    models/       plain data classes with toMap / fromMap
    providers/    data sources: sqflite database (schema, seed, migrations),
                  local notifications and file sharing/picking
                  (behind interfaces, faked in tests)
    repositories/ the only code that reads or writes data
  core/
    logic/        pure Dart rules (periods, balance, budgets, recurring dates,
                  goal projection, reports, month-end) — fully unit-tested
    utils/        money parsing/formatting, dates, currencies
    theme/        colors, theme, category icons
  widgets/        widgets shared by several screens
  routes/         named routes and GetPages
```

Data flows one way: **View → Controller → Repository → sqflite**.
After every write, `DatabaseService.revision` increases; controllers listen with
`ever(...)` and reload, so every open screen stays up to date.

Money is stored as integers in thousandths (1 JOD = 1000 fils), never as `double`.

## Running

```bash
flutter pub get
flutter run
flutter test
```
