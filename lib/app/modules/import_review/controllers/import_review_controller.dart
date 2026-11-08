import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/duplicate_check.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pending_item.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/import_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../data/repositories/transaction_repository.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// Lists imported items so the user can approve, edit or dismiss each one.
class ImportReviewController extends GetxController {
  ImportReviewController({
    required this.imports,
    required this.categories,
    required this.recurring,
    required this.transactions,
    required this.settings,
    required this.database,
  });

  final ImportRepository imports;
  final CategoryRepository categories;
  final RecurringRepository recurring;
  final TransactionRepository transactions;
  final SettingsService settings;
  final DatabaseService database;

  /// Newest first.
  final items = <PendingItem>[].obs;

  /// Every category, archived ones included, for showing names.
  final categoriesById = <int, TransactionCategory>{}.obs;

  /// "May already be recorded" label, by pending item id.
  final duplicateLabels = <int, String>{}.obs;

  final isSaving = false.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  /// Active categories of [kind], for the edit sheet.
  List<TransactionCategory> categoriesFor(TransactionKind kind) => categoriesById
      .values
      .where((c) => c.kind == kind && !c.isArchived)
      .toList();

  @override
  void onInit() {
    super.onInit();
    _reloadOnChange = ever(database.revision, (_) => load());
    load();
  }

  Future<void> load() async {
    final pending = await imports.getPending();
    final all = await categories.getAll(includeArchived: true);
    final labels = await _duplicateLabels(pending);
    categoriesById.assignAll({for (final c in all) c.id!: c});
    duplicateLabels.assignAll(labels);
    items.assignAll(pending);
  }

  Future<Map<int, String>> _duplicateLabels(List<PendingItem> pending) async {
    final candidates = [
      for (final item in pending)
        if (item.id != null && _transactionKind(item.kind) != null) item,
    ];
    if (candidates.isEmpty) return {};
    final days = [
      for (final item in candidates) DateKeys.dateOnly(item.occurredAt),
    ]..sort();
    final start = days.first.subtract(const Duration(days: 1));
    final end = DateTime(days.last.year, days.last.month, days.last.day + 2);
    final existing = await transactions.getBetween(start, end);
    final rules = await recurring.getAll();
    final labels = <int, String>{};
    for (final item in candidates) {
      final label = DuplicateCheck.find(
        kind: _transactionKind(item.kind)!,
        amount: item.amount,
        date: item.occurredAt,
        rules: rules,
        transactions: existing,
      );
      if (label != null) labels[item.id!] = label;
    }
    return labels;
  }

  static TransactionKind? _transactionKind(PendingKind kind) => switch (kind) {
        PendingKind.income => TransactionKind.income,
        PendingKind.expense => TransactionKind.expense,
        _ => null,
      };

  /// Whether [item] can be approved with one tap.
  bool canApproveDirectly(PendingItem item) => switch (item.kind) {
        PendingKind.income ||
        PendingKind.expense =>
          item.suggestedCategoryId != null,
        PendingKind.debtGave || PendingKind.debtTook =>
          item.personId != null || item.personName != null,
      };

  /// Approves [item] as suggested. Returns false when it cannot be approved
  /// directly or saving fails (a message is shown).
  Future<bool> approve(PendingItem item) {
    final kind = _transactionKind(item.kind);
    final category = item.suggestedCategoryId;
    if (kind == null || category == null) return Future.value(false);
    return _saveTransaction(item, kind, item.amount, item.occurredAt, category,
        item.note);
  }

  /// Approves [item] with the values the user chose in the edit sheet.
  Future<bool> approveEdited(
    PendingItem item, {
    required PendingKind kind,
    required int amount,
    required DateTime date,
    int? categoryId,
    int? personId,
    String? personName,
    String? note,
  }) {
    final transactionKind = _transactionKind(kind);
    if (transactionKind == null || categoryId == null) {
      return Future.value(false);
    }
    return _saveTransaction(item, transactionKind, amount, date, categoryId,
        note);
  }

  Future<bool> _saveTransaction(PendingItem item, TransactionKind kind,
      int amount, DateTime date, int categoryId, String? note) async {
    if (isSaving.value) return false;
    isSaving.value = true;
    try {
      await imports.approveAsTransaction(
        item,
        TransactionRecord(
          kind: kind,
          amount: amount,
          categoryId: categoryId,
          date: DateKeys.dateOnly(date),
          note: note,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              DateTime.now().millisecondsSinceEpoch),
        ),
      );
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ العملية، حاول مرة أخرى');
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Removes [item]. Returns it for Undo, or null when that failed.
  Future<PendingItem?> dismiss(PendingItem item) async {
    final id = item.id;
    if (id == null) return null;
    try {
      await imports.dismiss(id);
      return item;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر التجاهل، حاول مرة أخرى');
      return null;
    }
  }

  Future<void> undoDismiss(PendingItem item) async {
    try {
      await imports.restore(item);
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر التراجع، حاول مرة أخرى');
    }
  }

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
