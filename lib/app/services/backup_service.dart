import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../core/utils/date_utils.dart';
import '../data/providers/app_database.dart';
import '../data/providers/file_exchange_provider.dart';
import '../data/models/app_settings.dart';
import '../data/models/budget.dart';
import '../data/models/debt_entry.dart';
import '../data/models/debt_person.dart';
import '../data/models/obligation.dart';
import '../data/models/obligation_payment.dart';
import '../data/models/quick_template.dart';
import '../data/models/recurring_rule.dart';
import '../data/models/savings_goal.dart';
import '../data/models/savings_movement.dart';
import '../data/models/transaction_category.dart';
import '../data/models/transaction_record.dart';
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
    'learned_categories',
    'savings_goals',
    'recurring_rules',
    'transactions',
    'budgets',
    'savings_movements',
    'quick_templates',
    'budget_alerts_sent',
    'debt_people',
    'learned_people',
    'debt_entries',
    'obligations',
    'obligation_payments',
    'settings',
  ];

  /// Tables a version-1 backup does not have.
  static const _debtTables = {
    'debt_people',
    'debt_entries',
    'obligations',
    'obligation_payments',
  };

  /// Tables a version-2 backup does not have.
  static const _smartImportTables = {'learned_categories'};

  /// Tables a version-3 backup does not have.
  static const _learnedPeopleTables = {'learned_people'};

  static const _notABackup = 'هذا الملف ليس نسخة احتياطية من مصاريفي';

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

  /// Writes today's backup file and opens the share sheet. The time is
  /// recorded only when the file was actually shared; returns whether it was.
  Future<bool> shareBackup(DateTime now) async {
    final folder = await files.tempDirectory();
    final path =
        p.join(folder, 'masarifi-backup-${DateKeys.fromDate(now)}.json');
    await File(path).writeAsString(await exportJson(now));
    final shared =
        await files.shareFile(path, subject: 'نسخة احتياطية — مصاريفي');
    if (shared) {
      await settings.update(settings.settings.value.copyWith(lastBackupAt: now));
    }
    return shared;
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
          'النسخة من إصدار أحدث للتطبيق. حدّث التطبيق أولًا');
    }
    final rawTables = decoded['tables'];
    if (rawTables is! Map) throw const BackupFormatException(_notABackup);

    final parsed = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      var rows = rawTables[table];
      if (rows == null && version < 2 && _debtTables.contains(table)) {
        rows = const [];
      }
      if (rows == null && version < 3 && _smartImportTables.contains(table)) {
        rows = const [];
      }
      if (rows == null &&
          version < 4 &&
          _learnedPeopleTables.contains(table)) {
        rows = const [];
      }
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
    _checkTypes(parsed);
    _checkReferences(parsed);
    final exportedAt = decoded['exportedAt'];
    return BackupSummary(
      exportedAt: (exportedAt is String ? DateTime.tryParse(exportedAt) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      transactionCount: parsed['transactions']!.length,
      goalCount: parsed['savings_goals']!.length,
      tables: parsed,
    );
  }

  /// Reads every row the way the app will, so a file with a wrong value type
  /// is refused here instead of breaking the app after the restore.
  static void _checkTypes(Map<String, List<Map<String, Object?>>> tables) {
    final readers = <String, void Function(Map<String, Object?>)>{
      'categories': TransactionCategory.fromMap,
      'savings_goals': SavingsGoal.fromMap,
      'recurring_rules': RecurringRule.fromMap,
      'transactions': TransactionRecord.fromMap,
      'budgets': Budget.fromMap,
      'savings_movements': SavingsMovement.fromMap,
      'quick_templates': QuickTemplate.fromMap,
      'debt_people': DebtPerson.fromMap,
      'debt_entries': DebtEntry.fromMap,
      'obligations': Obligation.fromMap,
      'obligation_payments': ObligationPayment.fromMap,
      'settings': AppSettings.fromMap,
      'learned_categories': (row) {
        if (row['name_key'] is! String || row['category_id'] is! int) {
          throw const FormatException('learned_categories');
        }
      },
      'learned_people': (row) {
        if (row['name_key'] is! String || row['person_id'] is! int) {
          throw const FormatException('learned_people');
        }
      },
      'budget_alerts_sent': (row) {
        if (row['category_id'] is! int ||
            row['period_key'] is! String ||
            row['threshold'] is! int) {
          throw const FormatException('budget_alerts_sent');
        }
      },
    };
    try {
      for (final MapEntry(key: table, value: rows) in tables.entries) {
        rows.forEach(readers[table]!);
      }
    } catch (_) {
      throw const BackupFormatException(_notABackup);
    }
  }

  /// Refuses rows that point at a row the file does not contain.
  static void _checkReferences(Map<String, List<Map<String, Object?>>> tables) {
    Set<Object?> ids(String table) =>
        {for (final row in tables[table]!) row['id']};
    final people = ids('debt_people');
    final obligations = ids('obligations');
    final transactions = ids('transactions');
    final categories = ids('categories');
    final ok = tables['learned_categories']!
            .every((r) => categories.contains(r['category_id'])) &&
        tables['learned_people']!
            .every((r) => people.contains(r['person_id'])) &&
        tables['debt_entries']!
            .every((r) => people.contains(r['person_id'])) &&
        tables['obligation_payments']!.every((r) =>
            obligations.contains(r['obligation_id']) &&
            (r['transaction_id'] == null ||
                transactions.contains(r['transaction_id'])));
    if (!ok) throw const BackupFormatException(_notABackup);
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
