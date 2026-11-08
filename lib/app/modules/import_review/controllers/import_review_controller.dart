import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/logic/duplicate_check.dart';
import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/debt_entry.dart';
import '../../../data/models/debt_person.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pending_item.dart';
import '../../../data/models/transaction_category.dart';
import '../../../data/models/transaction_record.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/debt_repository.dart';
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
    required this.debts,
    this._openVoice = false,
  });

  /// The route argument that opens the voice sheet right away (Home's mic).
  static const voiceArgument = 'voice';

  final ImportRepository imports;
  final CategoryRepository categories;
  final RecurringRepository recurring;
  final TransactionRepository transactions;
  final SettingsService settings;
  final DatabaseService database;
  final DebtRepository debts;

  bool _openVoice;

  /// Newest first.
  final items = <PendingItem>[].obs;

  /// Every category, archived ones included, for showing names.
  final categoriesById = <int, TransactionCategory>{}.obs;

  /// "May already be recorded" label, by pending item id.
  final duplicateLabels = <int, String>{}.obs;

  /// Debt people, for the edit sheet's person picker.
  final people = <DebtPerson>[].obs;

  final isSaving = false.obs;

  late final Worker _reloadOnChange;

  Currency get currency => settings.currency;

  /// Active categories of [kind], for the edit sheet.
  List<TransactionCategory> categoriesFor(TransactionKind kind) => categoriesById
      .values
      .where((c) => c.kind == kind && !c.isArchived)
      .toList();

  /// What [item] may become: SMS items never become debts (spec §6.3).
  List<PendingKind> kindsFor(PendingItem item) =>
      item.source == PendingSource.voice
          ? PendingKind.values
          : const [PendingKind.expense, PendingKind.income];

  /// The person of a voice debt: their current name when known, otherwise
  /// the name as spoken.
  String? personLabel(PendingItem item) {
    final id = item.personId;
    if (id != null) {
      for (final p in people) {
        if (p.id == id) return p.name;
      }
    }
    return item.personName;
  }

  /// True once, when the screen was opened to start voice entry.
  bool takeVoiceRequest() {
    final open = _openVoice;
    _openVoice = false;
    return open;
  }

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
    final allPeople = await debts.getPeople();
    categoriesById.assignAll({for (final c in all) c.id!: c});
    duplicateLabels.assignAll(labels);
    people.assignAll(allPeople);
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

  static bool _isDebt(PendingKind kind) =>
      kind == PendingKind.debtGave || kind == PendingKind.debtTook;

  /// Approves [item] as suggested. Returns false when it cannot be approved
  /// directly or saving fails (a message is shown).
  Future<bool> approve(PendingItem item) {
    if (_isDebt(item.kind)) {
      if (!canApproveDirectly(item)) return Future.value(false);
      return _saveDebt(item, item.kind, item.amount, item.occurredAt,
          item.personId, item.personName, item.note);
    }
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
    if (_isDebt(kind)) {
      if (!kindsFor(item).contains(kind)) return Future.value(false);
      return _saveDebt(item, kind, amount, date, personId, personName, note);
    }
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

  /// Writes [item] as a debt entry: positive when I gave, negative when I
  /// took. The person is [personId] if they still exist, otherwise the one
  /// named [personName], created when new.
  Future<bool> _saveDebt(PendingItem item, PendingKind kind, int amount,
      DateTime date, int? personId, String? personName, String? note) async {
    if (isSaving.value) return false;
    isSaving.value = true;
    try {
      final person = await _resolvePerson(personId, personName);
      if (person == null) return false;
      await imports.approveAsDebt(
        item,
        DebtEntry(
          personId: person,
          amount: kind == PendingKind.debtGave ? amount : -amount,
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

  Future<int?> _resolvePerson(int? personId, String? personName) async {
    if (personId != null && await debts.getPerson(personId) != null) {
      return personId;
    }
    final name = personName?.trim() ?? '';
    if (name.isEmpty) return null;
    try {
      return (await debts.addPerson(name)).id;
    } on DuplicateNameException {
      final key = name.toLowerCase();
      for (final p in await debts.getPeople()) {
        if (p.name.trim().toLowerCase() == key) return p.id;
      }
      return null;
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
