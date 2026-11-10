import 'package:get/get.dart';

import '../core/logic/bank_sms_parser.dart';
import '../data/models/enums.dart';
import '../data/models/pending_item.dart';
import '../data/providers/sms_inbox_provider.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/import_repository.dart';
import 'settings_service.dart';

/// Suggests a category for a parsed card purchase (the AI hook).
typedef CategorySuggester = Future<int?> Function(ParsedBankSms sms);

/// Reads new bank SMS from the inbox and stores them as pending items for the
/// user to review. The message text itself is never stored.
class SmsImportService extends GetxService {
  SmsImportService({
    required this.inbox,
    required this.imports,
    required this.categories,
    required this.settings,
    this.suggester,
  });

  final SmsInboxProvider inbox;
  final ImportRepository imports;
  final CategoryRepository categories;
  final SettingsService settings;
  CategorySuggester? suggester;

  Future<int>? _running;

  /// Scans messages newer than the scan point and returns how many pending
  /// items were added. A call made while a scan runs waits for it and
  /// returns 0.
  Future<int> scan(DateTime now) {
    final running = _running;
    if (running != null) return running.then((_) => 0);
    final scan = _scan(now);
    _running = scan;
    return scan.whenComplete(() => _running = null);
  }

  /// A failing suggester (timeout, no network) means "no suggestion".
  Future<int?> _suggest(CategorySuggester suggest, ParsedBankSms sms) async {
    try {
      return await suggest(sms);
    } catch (_) {
      return null;
    }
  }

  Future<int> _scan(DateTime now) async {
    if (!settings.settings.value.smsImportEnabled ||
        !inbox.isSupported ||
        !await inbox.hasPermission()) {
      return 0;
    }
    final after =
        await imports.scanPoint() ?? settings.currentPeriod(now).start;
    final messages = await inbox.readInbox(after: after);
    if (messages.isEmpty) return 0;

    final all = await categories.getAll(includeArchived: false);
    int? byIcon(String key) {
      for (final c in all) {
        if (c.iconKey == key) return c.id;
      }
      return null;
    }

    final incomeOther = byIcon('income_other');
    final other = byIcon('other');
    final learned = <(String, TransactionKind), int?>{};
    final suggested = <String, int?>{};
    final items = <PendingItem>[];
    var newest = after;

    for (final message in messages) {
      // A message dated after [now] waits for a later scan, which reads on
      // from at most [now]: the scan point never moves past [now], so a
      // future-dated message cannot make later ones be skipped.
      if (message.date.isAfter(now)) continue;
      if (message.date.isAfter(newest)) newest = message.date;
      final sms = BankSmsParser.parse(message.body);
      if (sms == null) continue;
      final income = sms.type == BankSmsType.cliqReceived;
      final kind = income ? TransactionKind.income : TransactionKind.expense;
      final key = learnedKey(sms.type, sms.name);
      var categoryId = learned.containsKey((key, kind))
          ? learned[(key, kind)]
          : learned[(key, kind)] = await imports.learnedCategory(key, kind);
      if (categoryId == null) {
        switch (sms.type) {
          case BankSmsType.cliqReceived:
            categoryId = incomeOther;
          case BankSmsType.bankFee:
            categoryId = other;
          case BankSmsType.cardPurchase:
            final suggest = suggester;
            if (suggest != null) {
              categoryId = suggested.containsKey(key)
                  ? suggested[key]
                  : suggested[key] = await _suggest(suggest, sms);
            }
          case BankSmsType.cliqSent:
            break;
        }
      }
      items.add(
        PendingItem(
          source: PendingSource.sms,
          kind: income ? PendingKind.income : PendingKind.expense,
          amount: sms.amount,
          occurredAt: message.date,
          smsType: sms.type,
          name: sms.name,
          city: sms.city,
          suggestedCategoryId: categoryId,
          note: sms.name,
          createdAt: now,
        ),
      );
    }

    await imports.addPendingAndAdvance(items, newest);
    return items.length;
  }
}
