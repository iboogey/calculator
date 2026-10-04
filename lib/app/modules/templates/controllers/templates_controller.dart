import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../data/models/quick_template.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

class TemplatesController extends GetxController {
  TemplatesController({
    required this.templates,
    required this.categories,
    required this.settings,
    required this.database,
  });

  final TemplateRepository templates;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;

  final items = <QuickTemplate>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final allCategories = await categories.getAll(includeArchived: true);
    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    items.assignAll(await templates.getAll());
  }

  Future<void> delete(QuickTemplate template) async {
    try {
      await templates.delete(template.id!);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نحذف المفضّلة');
    }
  }

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
