import 'package:get/get.dart';

import '../../../core/logic/day_group.dart';
import '../../../core/logic/period.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/settings_service.dart';

class TransactionsController extends GetxController {
  TransactionsController({
    required this.transactions,
    required this.categories,
    required this.settings,
    required this.database,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TransactionRepository transactions;
  final CategoryRepository categories;
  final SettingsService settings;
  final DatabaseService database;
  final DateTime Function() _clock;

  final period = Rxn<Period>();
  final groups = <DayGroup>[].obs;
  final categoriesById = <int, TransactionCategory>{}.obs;

  List<TransactionRecord> _items = const [];
  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  DateTime get today => _clock();

  @override
  void onInit() {
    super.onInit();
    period.value = settings.currentPeriod(_clock());
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final current = period.value ??= settings.currentPeriod(_clock());
    final items = await transactions.getBetween(current.start, current.end);
    final allCategories = await categories.getAll(includeArchived: true);
    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    _items = items;
    groups.assignAll(DayGroup.group(items));
  }

  Future<void> previousPeriod() {
    period.value = period.value!.previous;
    return load();
  }

  Future<void> nextPeriod() {
    period.value = period.value!.next;
    return load();
  }

  /// Removes the row immediately (so a swipe-to-dismiss can finish), then
  /// deletes it from the database.
  Future<void> delete(TransactionRecord record) {
    _items = _items.where((t) => t.id != record.id).toList();
    groups.assignAll(DayGroup.group(_items));
    return transactions.delete(record.id!);
  }

  Future<void> undoDelete(TransactionRecord record) =>
      transactions.restore(record);

  void openEdit(TransactionRecord record) =>
      Get.toNamed(Routes.transactionForm, arguments: record.id);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
