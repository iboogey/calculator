import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/day_group.dart';
import '../../../core/logic/period.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../routes/app_routes.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
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

  /// True until the user moves to another period; then reloads keep showing
  /// the period they chose.
  bool _followsCurrent = true;
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
    final current = _followsCurrent
        ? settings.currentPeriod(_clock())
        : period.value ?? settings.currentPeriod(_clock());
    period.value = current;
    final items = await transactions.getBetween(current.start, current.end);
    final allCategories = await categories.getAll(includeArchived: true);
    categoriesById.assignAll({for (final c in allCategories) c.id!: c});
    _items = items;
    groups.assignAll(DayGroup.group(items));
  }

  Future<void> previousPeriod() => _showPeriod(period.value!.previous);

  Future<void> nextPeriod() => _showPeriod(period.value!.next);

  Future<void> _showPeriod(Period value) {
    period.value = value;
    _followsCurrent = value == settings.currentPeriod(_clock());
    return load();
  }

  /// Removes the row immediately (so a swipe-to-dismiss can finish), then
  /// deletes it from the database. On failure the row comes back.
  Future<void> delete(TransactionRecord record) async {
    final before = _items;
    _items = _items.where((t) => t.id != record.id).toList();
    groups.assignAll(DayGroup.group(_items));
    try {
      await transactions.delete(record.id!);
    } on DatabaseException {
      _items = before;
      groups.assignAll(DayGroup.group(_items));
      Get.find<MessageService>().showError('ما قدرنا نحذف العملية، جرّب مرة ثانية');
    }
  }

  Future<void> undoDelete(TransactionRecord record) async {
    try {
      await transactions.restore(record);
    } on DatabaseException {
      Get.find<MessageService>().showError('ما قدرنا نرجّع العملية');
    }
  }

  void openEdit(TransactionRecord record) =>
      Get.toNamed(Routes.transactionForm, arguments: record.id);

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
