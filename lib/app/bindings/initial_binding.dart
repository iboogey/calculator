import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../data/providers/file_exchange_provider.dart';
import '../data/providers/notification_provider.dart';
import '../data/providers/sms_inbox_provider.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/debt_repository.dart';
import '../data/repositories/import_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/savings_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/template_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/backup_service.dart';
import '../services/budget_alert_service.dart';
import '../services/database_service.dart';
import '../services/message_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/sms_import_service.dart';
import '../services/startup_service.dart';

/// Registers the app-wide services and repositories before the first screen.
/// Async because the database has to open first, so it runs from `main()`
/// instead of a synchronous `Bindings.dependencies()`.
abstract final class InitialBinding {
  static Future<void> initServices({
    DatabaseFactory? factory,
    String? path,
    NotificationProvider? notifications,
    FileExchangeProvider? files,
    SmsInboxProvider? smsInbox,
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
    Get.put(DebtRepository(database), permanent: true);
    final imports = Get.put(ImportRepository(database), permanent: true);
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
    final inbox = Get.put<SmsInboxProvider>(
        smsInbox ?? DeviceSmsInboxProvider(),
        permanent: true);
    final smsImport = Get.put(
      SmsImportService(
        inbox: inbox,
        imports: imports,
        categories: categories,
        settings: settings,
      ),
      permanent: true,
    );
    // Register any later import services (e.g. AI) above this line:
    // StartupService must be created last, because init() runs a first scan.
    await Get.putAsync(
        () => StartupService(
                recurring: recurring, database: database, smsImport: smsImport)
            .init(),
        permanent: true);
    final fileExchange = Get.put<FileExchangeProvider>(
        files ?? DeviceFileExchangeProvider(),
        permanent: true);
    Get.put(
      BackupService(database: database, settings: settings, files: fileExchange),
      permanent: true,
    );
  }
}
