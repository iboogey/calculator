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
