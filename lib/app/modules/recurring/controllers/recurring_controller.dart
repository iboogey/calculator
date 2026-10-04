import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/recurring_generator.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/recurring_rule.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class RecurringController extends GetxController {
  RecurringController({
    required this.recurring,
    required this.categories,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final RecurringRepository recurring;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final rules = <RecurringRule>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  DateTime get today => _clock();

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final allCategories = await categories.getAll(includeArchived: true);
    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    rules.assignAll(await recurring.getAll());
  }

  Future<void> toggleActive(RecurringRule rule) async {
    try {
      await recurring.setActive(rule.id!, !rule.isActive);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نغيّر حالة القاعدة');
    }
  }

  DateTime nextDue(RecurringRule rule) =>
      RecurringGenerator.nextDueDate(rule, _clock());

  void openAdd() => Get.toNamed(Routes.recurringForm);

  void openEdit(RecurringRule rule) =>
      Get.toNamed(Routes.recurringForm, arguments: rule.id);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
