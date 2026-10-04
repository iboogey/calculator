# مصاريفي — Personal Expense Tracker

A personal, fully offline Flutter app for tracking monthly income and expenses.
Arabic (RTL) interface, no accounts, no internet: all data stays on the device in SQLite.

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
                  budget alerts, startup (recurring catch-up on start/resume), messages
  data/
    models/       plain data classes with toMap / fromMap
    providers/    data sources: sqflite database (schema, seed, migrations)
                  and local notifications (behind an interface, faked in tests)
    repositories/ the only code that reads or writes data
  core/
    logic/        pure Dart rules (periods, balance, budgets, recurring dates) — fully unit-tested
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
