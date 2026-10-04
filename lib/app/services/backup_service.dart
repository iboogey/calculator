import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../core/utils/date_utils.dart';
import '../data/providers/app_database.dart';
import '../data/providers/file_exchange_provider.dart';
import '../data/models/app_settings.dart';
import '../data/models/budget.dart';
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
    _checkTypes(parsed);
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
      'settings': AppSettings.fromMap,
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
