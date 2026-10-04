import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/providers/notification_provider.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/savings_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/template_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/budget_alert_service.dart';
import '../services/database_service.dart';
import '../services/message_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/startup_service.dart';

/// Registers the app-wide services and repositories before the first screen.
/// Async because the database has to open first, so it runs from `main()`
/// instead of a synchronous `Bindings.dependencies()`.
abstract final class InitialBinding {
  static Future<void> initServices({
    DatabaseFactory? factory,
    String? path,
    NotificationProvider? notifications,
  }) async {
    final database = await Get.putAsync(
        () => DatabaseService(factory: factory, path: path).init(),
        permanent: true);
    final settingsRepository =
        Get.put(SettingsRepository(database), permanent: true);
    final categories = Get.put(CategoryRepository(database), permanent: true);
    final transactions =
        Get.put(TransactionRepository(database), permanent: true);
    Get.put(SavingsRepository(database), permanent: true);
    final budgets = Get.put(BudgetRepository(database), permanent: true);
    final recurring = Get.put(RecurringRepository(database), permanent: true);
    Get.put(TemplateRepository(database), permanent: true);

    final settings = await Get.putAsync(
        () => SettingsService(settingsRepository, database).init(),
        permanent: true);
    Get.put(MessageService(), permanent: true);
    final notificationService = await Get.putAsync(
        () => NotificationService(
                notifications ?? LocalNotificationProvider(), settings)
            .init(),
        permanent: true);
    Get.put(
      BudgetAlertService(
        database: database,
        budgets: budgets,
        transactions: transactions,
        categories: categories,
        settings: settings,
        notifications: notificationService,
      ),
      permanent: true,
    );
    await Get.putAsync(
        () => StartupService(recurring: recurring, database: database).init(),
        permanent: true);
  }
}
