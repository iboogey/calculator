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

Money is stored as integers in thousandths (1 JOD = 1000 fils), never as `double`.

## Running

```bash
flutter pub get
flutter run
flutter test
```
