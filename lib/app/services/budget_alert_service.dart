import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../core/logic/budget_status.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/transaction_repository.dart';
import 'database_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';

/// Sends a notification the first time a category reaches 80 % or 100 % of
/// its budget in a period.
class BudgetAlertService extends GetxService {
  BudgetAlertService({
    required this.database,
    required this.budgets,
    required this.transactions,
    required this.categories,
    required this.settings,
    required this.notifications,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DatabaseService database;
  final BudgetRepository budgets;
  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final NotificationService notifications;
  final DateTime Function() _clock;

  late final Worker _checkOnChange;

  @override
  void onInit() {
    super.onInit();
    _checkOnChange = ever(database.revision, (_) => check());
  }

  Future<void> check() async {
    try {
      final period = settings.currentPeriod(_clock());
      final allCategories = await categories.getAll(includeArchived: true);
      final statuses = BudgetCalculator.calculate(
        period: period,
        budgets: await budgets.getAll(),
        categoriesById: {for (final c in allCategories) c.id!: c},
        transactions: await transactions.getBetween(period.start, period.end),
      );
      for (final status in statuses) {
        var newest = 0;
        for (final threshold in status.reachedThresholds) {
          if (await budgets.markAlertSent(status.category.id!, period.key, threshold)) {
            newest = threshold;
          }
        }
        // Only the highest new threshold, so one expense never sends two.
        if (newest > 0) await notifications.showBudgetAlert(status, newest);
      }
    } on DatabaseException {
      // The database is closing or busy; the next change checks again.
    }
  }

  @override
  void onClose() {
    _checkOnChange.dispose();
    super.onClose();
  }
}
