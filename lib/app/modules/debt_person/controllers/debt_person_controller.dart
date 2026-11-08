import 'package:get/get.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/currencies.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/debt_entry.dart';
import '../../../data/models/debt_person.dart';
import '../../../data/repositories/debt_repository.dart';
import '../../../services/database_service.dart';
import '../../../services/message_service.dart';
import '../../../services/settings_service.dart';

/// What the entry sheet returns; [amount] is already signed
/// (positive = I gave, negative = I took).
class EntryDraft {
  const EntryDraft({required this.amount, required this.date, this.note});

  final int amount;
  final DateTime date;
  final String? note;
}

class DebtPersonController extends GetxController {
  DebtPersonController({
    required this.debts,
    required this.settings,
    required this.database,
    required this.personId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DebtRepository debts;
  final SettingsService settings;
  final DatabaseService database;
  final int personId;
  final DateTime Function() _clock;

  final person = Rxn<DebtPerson>();
  final balance = 0.obs;
  final entries = <DebtEntry>[].obs;

  bool _isSaving = false;
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
    person.value = await debts.getPerson(personId);
    balance.value = (await debts.personBalances())[personId] ?? 0;
    entries.assignAll(await debts.getEntries(personId));
  }

  Future<bool> addEntry(EntryDraft d) async {
    if (_isSaving) return false;
    _isSaving = true;
    try {
      await debts.addEntry(DebtEntry(
        personId: personId,
        amount: d.amount,
        date: DateKeys.dateOnly(d.date),
        note: d.note,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            DateTime.now().millisecondsSinceEpoch),
      ));
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ السجل، حاول مرة أخرى');
      return false;
    } finally {
      _isSaving = false;
    }
  }

  Future<bool> updateEntry(DebtEntry old, EntryDraft d) async {
    if (_isSaving) return false;
    _isSaving = true;
    try {
      await debts.updateEntry(DebtEntry(
        id: old.id,
        personId: old.personId,
        amount: d.amount,
        date: DateKeys.dateOnly(d.date),
        note: d.note,
        createdAt: old.createdAt,
      ));
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ السجل، حاول مرة أخرى');
      return false;
    } finally {
      _isSaving = false;
    }
  }

  /// Returns the deleted entry so the caller can offer Undo, or null.
  Future<DebtEntry?> deleteEntry(DebtEntry e) async {
    try {
      await debts.deleteEntry(e.id!);
      return e;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حذف السجل، حاول مرة أخرى');
      return null;
    }
  }

  Future<void> undoDelete(DebtEntry e) async {
    try {
      await debts.restoreEntry(e);
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حفظ السجل، حاول مرة أخرى');
    }
  }

  /// Returns null on success, otherwise the message to show.
  Future<String?> rename(String name) async {
    if (_isSaving) return null;
    _isSaving = true;
    try {
      await debts.renamePerson(personId, name);
      return null;
    } on ArgumentError {
      return 'اكتب الاسم';
    } on DuplicateNameException {
      return 'هذا الاسم موجود مسبقًا';
    } on DatabaseException {
      return 'تعذّر حفظ الاسم، حاول مرة أخرى';
    } finally {
      _isSaving = false;
    }
  }

  Future<bool> deletePerson() async {
    try {
      await debts.deletePerson(personId);
      return true;
    } on DatabaseException {
      Get.find<MessageService>().showError('تعذّر حذف الشخص، حاول مرة أخرى');
      return false;
    }
  }

  @override
  void onClose() {
    _reloadOnChange.dispose();
    super.onClose();
  }
}
