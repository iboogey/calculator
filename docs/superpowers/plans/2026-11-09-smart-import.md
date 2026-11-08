# Smart Import (Bank SMS + Voice) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the user's bank SMS into pending expenses/income they approve one by one, with optional AI category suggestions and voice entry (which may also create debts).

**Architecture:** A pure-Dart parser turns SMS bodies into `ParsedBankSms`. `SmsImportService` (run from `StartupService`) reads new SMS since a device-only scan point, builds `PendingItem`s with a category suggestion (learned memory → AI → default) and stores them in `pending_items`. A new `import_review` module lists them; approving writes a normal transaction (or, for voice, a debt entry) and deletes the pending row in one DB transaction. AI providers sit behind one `AiClient` interface; keys live in `flutter_secure_storage`.

**Tech Stack:** Flutter 3.44 / Dart 3.12, GetX, sqflite (DB v2 → v3), `permission_handler` (READ_SMS), a Kotlin `MethodChannel` for the SMS inbox, `flutter_secure_storage`, `http` (+ `package:http/testing.dart` in tests), `speech_to_text`.

**Spec:** `docs/superpowers/specs/2026-11-08-smart-import-design.md`

## Global Constraints

- Money is `int` thousandths; parse with `Money.parse(text, decimals: 3)`, never `double`.
- Dates in the DB are `YYYY-MM-DD` (`DateKeys`); SMS times are stored as epoch millis in `occurred_at`.
- All user-visible text is فصحى Arabic, RTL. Copy fixed by the spec is quoted verbatim in the tasks.
- GetX Pattern: module = bindings/controllers/views/widgets; repositories are the only DB access; every write calls `DatabaseService.notifyChanged()`; controllers report `DatabaseException` through `MessageService.showError`.
- Platform code (SMS, permissions, secure storage, speech, HTTP) is behind an interface and faked in tests.
- **Public repo:** no real SMS, names, account numbers or keys anywhere in `test/` or `lib/`. Use only the fabricated fixtures in `test/helpers/sms_fixtures.dart` (Task 1).
- **Never stored:** SMS body, account number, balance. `pending_items` rows are deleted on approve and on dismiss. `pending_items` and the scan point are never in the backup and are untouched by restore.
- **Never sent to AI:** SMS text, account numbers, balances, CliQ names. Category suggestion sends merchant + city + category names only.
- SMS items only ever become expense or income; only voice items may become debt entries.
- No "approve all" anywhere.
- Run the whole suite with `flutter test` and `flutter analyze` before every commit; both must be clean.

## Review Focus

1. **Two equal card payments in the same minute** (e.g. two 1.000 JD coffees) must produce two pending items, not one: the scan point is "strictly after the newest SMS date read", so both are read in the same scan. → test in Task 6.
2. **App resumed while a scan is still running** (start + resume fire together) must not import the same SMS twice. → test in Task 6.
3. **Bank padding variations** (single space vs runs of spaces between merchant/city/country, trailing spaces, Arabic-Indic digits in amounts) must parse identically or be ignored, never mis-split into a wrong merchant/amount. → tests in Task 1.
4. **A v2 backup restored on the v3 app** (no `learned_categories`, settings row without the new columns) must restore and keep SMS import settings at defaults; the device's scan point and pending items stay as they were. → test in Task 3.
5. **AI returns a category not in the list, wrong JSON, or times out** during a scan: the item is still created with no category and the scan finishes. → test in Task 12.

---

## Phase 1 — SMS import without AI

### Task 1: Bank SMS parser

**Files:**
- Create: `lib/app/core/logic/bank_sms_parser.dart`
- Create: `test/helpers/sms_fixtures.dart`
- Test: `test/core/logic/bank_sms_parser_test.dart`

**Interfaces:**
- Produces:
  - `enum BankSmsType { cardPurchase, cliqSent, cliqReceived, bankFee }`
  - `class ParsedBankSms { final BankSmsType type; final int amount; final String name; final String? city; }` with `==`/`hashCode`. `name` = merchant (card), counterparty (CliQ) or reason (fee); `city` only for card purchases.
  - `abstract final class BankSmsParser { static ParsedBankSms? parse(String body); }`
  - `String learnedKey(BankSmsType type, String name)` (top-level, same file): prefix `shop:` (cardPurchase), `cliq:` (cliqSent/cliqReceived), `fee:` (bankFee) + name trimmed, inner whitespace collapsed to one space, upper-cased.

- [ ] **Step 1: Write the fixtures file** `test/helpers/sms_fixtures.dart` with these exact fabricated constants (copied from spec §6.2):

```dart
const smsCard = 'تفويض حركة على حسابكم 1234567 - 001 بقيمة 3.5 دينار اردني من SAMPLE SUPER MARKET      AMMAN       JOR الرصيد المتوفر 120.250 دينار اردني';
const smsCliqSent = 'حوالة كليك صادرة بمبلغ 25.0 دينار اردني من حسابكم 1234567 - 001 الى SAMI KHALED HADDAD الرصيد المتوفر 95.250 دينار اردني';
const smsCliqReceived = 'حوالة كليك واردة بمبلغ 10.0 دينار اردني لحسابكم 1234567 - 001 من RANA OMAR SALEH الرصيد المتوفر 105.250 دينار اردني';
const smsFee = 'قيد مبلغ 0.5 دينار اردني على حسابكم 7654321 - 002 وذلك عمولة خدمات مصرفية الية';
const smsAnnouncement = 'متعاملنا الكريم، قد تتأثر بعض خدماتنا البنكية ليلة الجمعة من الساعة 02:00 – 06:00 صباحاً.';
const smsCardTruncated = 'تفويض حركة على حسابكم 1234567 - 001 بقيمة 7.1 دينار اردني من SAMPLE ELECTRICITY R   AMMAN       JOR الرصيد المتوفر 579.094 دينار اردني';
const smsCardNarrowGap = 'تفويض حركة على حسابكم 1234567 - 001 بقيمة 34.41 دينار اردني من SAMPLE FISH REST 2  AQABA         JOR الرصيد المتوفر 586.194 دينار اردني';
```

- [ ] **Step 2: Write the failing tests**

```dart
test('card purchase', () => expect(BankSmsParser.parse(smsCard),
    const ParsedBankSms(type: BankSmsType.cardPurchase, amount: 3500, name: 'SAMPLE SUPER MARKET', city: 'AMMAN')));
test('CliQ sent', () => expect(BankSmsParser.parse(smsCliqSent),
    const ParsedBankSms(type: BankSmsType.cliqSent, amount: 25000, name: 'SAMI KHALED HADDAD')));
test('CliQ received', () => expect(BankSmsParser.parse(smsCliqReceived),
    const ParsedBankSms(type: BankSmsType.cliqReceived, amount: 10000, name: 'RANA OMAR SALEH')));
test('bank fee', () => expect(BankSmsParser.parse(smsFee),
    const ParsedBankSms(type: BankSmsType.bankFee, amount: 500, name: 'عمولة خدمات مصرفية الية')));
test('announcement is ignored', () => expect(BankSmsParser.parse(smsAnnouncement), isNull));
test('truncated merchant kept as-is', () => expect(BankSmsParser.parse(smsCardTruncated)!.name, 'SAMPLE ELECTRICITY R'));
test('two-space gap still splits merchant and city', () {
  final p = BankSmsParser.parse(smsCardNarrowGap)!;
  expect((p.name, p.city, p.amount), ('SAMPLE FISH REST 2', 'AQABA', 34410));
});
test('three-decimal amount', () => expect(BankSmsParser.parse(smsCard.replaceFirst('3.5', '176.464'))!.amount, 176464));
test('Arabic-Indic digits in amount', () => expect(BankSmsParser.parse(smsCard.replaceFirst('3.5', '٣٫٥'))!.amount, 3500));
test('trailing/extra spaces tolerated', () => expect(BankSmsParser.parse('  $smsCliqSent  ')!.amount, 25000));
test('unparseable amount → null', () => expect(BankSmsParser.parse(smsCard.replaceFirst('3.5', '3.5.1')), isNull));
test('card merchant with single spaces only (no city split) → null', () => expect(
    BankSmsParser.parse('تفويض حركة على حسابكم 1 - 001 بقيمة 1.0 دينار اردني من SHOP AMMAN JOR الرصيد المتوفر 1.0 دينار اردني'), isNull));
test('OTP-like text → null', () => expect(BankSmsParser.parse('رمز التحقق 123456'), isNull));
test('learnedKey normalizes', () {
  expect(learnedKey(BankSmsType.cardPurchase, ' route   65 '), 'shop:ROUTE 65');
  expect(learnedKey(BankSmsType.cliqReceived, 'Sami  Haddad'), 'cliq:SAMI HADDAD');
  expect(learnedKey(BankSmsType.bankFee, 'عمولة'), 'fee:عمولة');
});
```

- [ ] **Step 3: Run** `flutter test test/core/logic/bank_sms_parser_test.dart` — Expected: FAIL (file/class missing).
- [ ] **Step 4: Implement** `BankSmsParser.parse`: trim; one `RegExp` per template anchored `^…$` with `\s+` between fixed words; account `[\d\s-]+`; amount `[\d٠-٩.,٫]+` passed to `Money.parse(_, decimals: 3)` (null → return null). Card template captures the text between `من ` and ` الرصيد المتوفر` and splits it with `RegExp(r'\s{2,}')` into exactly 3 parts `[merchant, city, country]` (country `^[A-Z]{3}$`); any other shape → null.
- [ ] **Step 5: Run** the test file — Expected: all PASS.
- [ ] **Step 6: Commit** `git add lib/app/core/logic/bank_sms_parser.dart test/helpers/sms_fixtures.dart test/core/logic/bank_sms_parser_test.dart && git commit -m "feat: bank SMS parser for the four templates"`

### Task 2: Duplicate check

**Files:**
- Create: `lib/app/core/logic/duplicate_check.dart`
- Test: `test/core/logic/duplicate_check_test.dart`

**Interfaces:**
- Consumes: `RecurringRule`, `TransactionRecord`, `TransactionKind`, `RecurringKind`.
- Produces: `abstract final class DuplicateCheck { static String? find({required TransactionKind kind, required int amount, required DateTime date, required List<RecurringRule> rules, required List<TransactionRecord> transactions}); }` — returns the label to show after "قد يكون مسجّلًا مسبقًا: ", or null.

- [ ] **Step 1: Write the failing tests** (rule = active expense rule, label 'قسط السيارة', amount 180000, dayOfMonth 5, startDate 2026-01-01):

```dart
test('rule due within ±3 days matches', () =>
    expect(DuplicateCheck.find(kind: expense, amount: 180000, date: DateTime(2026, 11, 7), rules: [rule], transactions: []), 'قسط السيارة'));
test('rule due 4 days away does not match', () =>
    expect(DuplicateCheck.find(kind: expense, amount: 180000, date: DateTime(2026, 11, 9), rules: [rule], transactions: []), isNull));
test('month boundary: due 1 Dec, SMS 29 Nov matches', ...dayOfMonth 1 → 'قسط السيارة');
test('inactive rule, saving rule, other amount, other kind, start after date → null', ...);
test('transaction same amount and kind within ±1 day matches with its note, or category-less fallback "عملية مسجّلة"', () {
  expect(DuplicateCheck.find(kind: expense, amount: 5240, date: DateTime(2026, 11, 2), rules: [],
      transactions: [expense(5240, DateTime(2026, 11, 1), note: 'فاتورة الهاتف')]), 'فاتورة الهاتف');
  expect(DuplicateCheck.find(kind: expense, amount: 5240, date: DateTime(2026, 11, 2), rules: [],
      transactions: [expense(5240, DateTime(2026, 11, 1))]), 'عملية مسجّلة');
});
test('transaction 2 days away → null', ...);
test('rule match wins over transaction match', ...);
```

- [ ] **Step 2: Run** `flutter test test/core/logic/duplicate_check_test.dart` — Expected: FAIL.
- [ ] **Step 3: Implement.** Rule candidates: `DateTime(y, m + k, rule.dayOfMonth)` for k ∈ {-1, 0, 1} around `date`, ignoring candidates before `rule.startDate`; compare whole-day differences (`DateKeys.dateOnly`). `RecurringKind.income/expense` maps to `TransactionKind` by name; `saving` never matches.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: duplicate check against recurring rules and transactions"` (add both files).

### Task 3: Database v3, models, backup v3

**Files:**
- Modify: `lib/app/data/providers/app_database.dart` (version 3, `schemaV3`, `_onCreate`, `_onUpgrade`)
- Create: `lib/app/data/models/pending_item.dart`
- Modify: `lib/app/data/models/app_settings.dart`
- Modify: `lib/app/services/backup_service.dart`
- Test: `test/data/providers/app_database_migration_test.dart`, `test/data/models/pending_item_test.dart`, `test/services/backup_service_test.dart`, `test/data/models/models_test.dart`

**Interfaces:**
- Produces:
  - `schemaV3` (exact):
    ```sql
    CREATE TABLE pending_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL CHECK (source IN ('sms', 'voice')),
      kind TEXT NOT NULL CHECK (kind IN ('income', 'expense', 'debtGave', 'debtTook')),
      amount INTEGER NOT NULL CHECK (amount > 0),
      occurred_at INTEGER NOT NULL,
      sms_type TEXT,
      name TEXT,
      city TEXT,
      suggested_category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
      person_id INTEGER REFERENCES debt_people(id) ON DELETE SET NULL,
      person_name TEXT,
      note TEXT,
      created_at INTEGER NOT NULL
    )
    CREATE TABLE learned_categories (
      name_key TEXT PRIMARY KEY,
      category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE
    )
    CREATE TABLE device_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      last_sms_scan_at INTEGER
    )
    ALTER TABLE settings ADD COLUMN sms_import_enabled INTEGER NOT NULL DEFAULT 0
    ALTER TABLE settings ADD COLUMN ai_provider TEXT NOT NULL DEFAULT 'none'
    ALTER TABLE settings ADD COLUMN ai_model TEXT
    ALTER TABLE settings ADD COLUMN voice_language TEXT NOT NULL DEFAULT 'ar-JO'
    ```
    plus `INSERT INTO device_state (id) VALUES (1)` in both create and upgrade.
  - `enum PendingKind { income, expense, debtGave, debtTook }`, `enum PendingSource { sms, voice }`
  - `class PendingItem { int? id; PendingSource source; PendingKind kind; int amount; DateTime occurredAt; BankSmsType? smsType; String? name; String? city; int? suggestedCategoryId; int? personId; String? personName; String? note; DateTime createdAt; }` with `fromMap`, `toMap`, `withId`, `copyWith`, `==`, and `String? get learnKey` → `learnedKey(smsType!, name!)` when both set, else null.
  - `enum AiProviderKind { none, gemini, claude, openai }` (in `app_settings.dart`)
  - `AppSettings` gains `smsImportEnabled` (bool, default false), `aiProvider` (`AiProviderKind`, default none), `aiModel` (`String?`), `voiceLanguage` (String, default `'ar-JO'`); `fromMap` falls back to these defaults when a column is missing (v2 backups); `copyWith` gets `clearAiModel` bool for setting `aiModel` back to null.
  - `BackupService.tables` gains `'learned_categories'` directly after `'categories'`; `_checkTypes` validates it (`name_key` String, `category_id` int); `_checkReferences` checks `category_id` exists in the file's categories; version < 3 files get `learned_categories: []`. `pending_items` and `device_state` are **not** in `tables`.

- [ ] **Step 1: Write the failing tests**
  - migration test: `AppDatabase.version == 3`; fresh DB has `pending_items`, `learned_categories`, `device_state` with one row (`last_sms_scan_at` null); upgrading a v2 DB (built from `schemaV1 + schemaV2` with one transaction and one settings row) keeps the transaction and the settings row reads `smsImportEnabled == false`, `aiProvider == AiProviderKind.none`, `voiceLanguage == 'ar-JO'`. Update the existing `expect(AppDatabase.version, 2)` to 3.
  - `pending_item_test`: `toMap`/`fromMap` round-trip for an SMS card item and a voice debt item; `learnKey` is `'shop:SAMPLE SUPER MARKET'` for the card item and null for voice.
  - `models_test`: `AppSettings.fromMap` on a map **without** the four new keys gives the defaults; round-trip with all set.
  - `backup_service_test`:
    - export → parse → restore round-trips a `learned_categories` row;
    - export JSON has no `pending_items` / `device_state` keys;
    - restore leaves an existing `pending_items` row and `device_state.last_sms_scan_at` unchanged;
    - a schemaVersion-2 file (no `learned_categories`, settings without new columns) restores and settings read defaults;
    - a `learned_categories` row pointing at a missing category → `BackupFormatException`.
- [ ] **Step 2: Run** `flutter test test/data test/services/backup_service_test.dart` — Expected: new tests FAIL.
- [ ] **Step 3: Implement** schema, migration (`if (oldVersion < 3)` runs `schemaV3`), models, `AppSettings` fields, backup changes. Note: restore deletes `categories`, which sets `pending_items.suggested_category_id` to NULL — acceptable (spec §6.11 falls back to none).
- [ ] **Step 4: Run** `flutter test` — Expected: whole suite PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: database v3 for smart import; backup v3"` (all touched files).

### Task 4: SMS inbox provider (Android) and fake

**Files:**
- Create: `lib/app/data/providers/sms_inbox_provider.dart`
- Create: `android/app/src/main/kotlin/<package path>/SmsInboxChannel.kt` and register it in `MainActivity.kt` (find the package path from the existing `MainActivity.kt`)
- Modify: `android/app/src/main/AndroidManifest.xml` (add `<uses-permission android:name="android.permission.READ_SMS"/>`)
- Modify: `pubspec.yaml` (add `permission_handler`, latest stable)
- Create: `test/helpers/fake_sms_inbox.dart`

**Interfaces:**
- Produces:
  - `class SmsMessage { final DateTime date; final String body; }`
  - `abstract class SmsInboxProvider { bool get isSupported; Future<bool> hasPermission(); Future<bool> requestPermission(); Future<List<SmsMessage>> readInbox({required DateTime after}); }` — `readInbox` returns messages with `date` strictly after `after`, oldest first.
  - `class DeviceSmsInboxProvider implements SmsInboxProvider` — `isSupported` = `GetPlatform.isAndroid`; permission via `Permission.sms`; inbox via `MethodChannel('masarifi/sms')` method `readInbox` with `{'after': millis}` returning `List<Map>` of `{'date': int, 'body': String}`. Kotlin side queries `content://sms/inbox` with `date > ?` ordered `date ASC`, returning only `date` and `body` columns.
  - `class FakeSmsInboxProvider implements SmsInboxProvider { bool supported = true; bool granted = true; final messages = <SmsMessage>[]; int readCount = 0; }` — `readInbox` filters `messages` by `after`, increments `readCount`.

- [ ] **Step 1: Implement** the interface, device implementation, Kotlin channel, manifest permission, fake. (No unit test for platform code; the fake is exercised from Task 6.)
- [ ] **Step 2: Verify build** `flutter build apk --debug` — Expected: builds.
- [ ] **Step 3: Run** `flutter analyze && flutter test` — Expected: clean / PASS.
- [ ] **Step 4: Commit** `git commit -m "feat: Android SMS inbox provider behind an interface"`.

### Task 5: Import repository

**Files:**
- Create: `lib/app/data/repositories/import_repository.dart`
- Modify: `lib/app/bindings/initial_binding.dart` (register `ImportRepository`)
- Test: `test/data/repositories/import_repository_test.dart`

**Interfaces:**
- Consumes: `PendingItem`, `TransactionRecord`, `DebtEntry`, `DatabaseService`.
- Produces `class ImportRepository(DatabaseService)`:
  - `Future<DateTime?> scanPoint()` / `Future<void> setScanPoint(DateTime at)` (reads/writes `device_state`; `setScanPoint` never moves backwards)
  - `Future<void> addPending(List<PendingItem> items)` (one transaction; notifies only when non-empty)
  - `Future<List<PendingItem>> getPending()` (newest `occurred_at` first, then id DESC)
  - `Future<int> pendingCount()`
  - `Future<void> dismiss(int id)` / `Future<void> restore(PendingItem item)` (re-insert with its id; for Undo)
  - `Future<void> update(PendingItem item)`
  - `Future<int?> learnedCategory(String key)` (ignores rows whose category is archived)
  - `Future<TransactionRecord> approveAsTransaction(PendingItem item, TransactionRecord record)` — one DB transaction: insert record, delete pending row, and if `item.learnKey != null` upsert `learned_categories(key, record.categoryId)`; notifies once.
  - `Future<DebtEntry> approveAsDebt(PendingItem item, DebtEntry entry)` — insert entry, delete pending row; no learning.

- [ ] **Step 1: Write the failing tests** (on `openTestDatabase()`):
  - scan point null at first, set → read back; setting an earlier time keeps the later one;
  - add 2 → `getPending` newest first, `pendingCount == 2`;
  - `approveAsTransaction` inserts the transaction, removes the pending row, and `learnedCategory('shop:SAMPLE SUPER MARKET') == categoryId`;
  - approving the same key again with another category overwrites (last choice wins);
  - voice item (`learnKey == null`) approval learns nothing;
  - `approveAsDebt` inserts a `debt_entries` row and removes the pending row;
  - dismiss removes the row; restore puts it back with the same id;
  - archived category → `learnedCategory` returns null;
  - after `approveAsTransaction` the `pending_items` table contains no row for that item, and no table contains the SMS body (assert `sqlite_master` has no table other than the known list).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the repository; register it in `InitialBinding` as `Get.put(ImportRepository(database), permanent: true)`.
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: import repository for pending items and learned categories"`.

### Task 6: SMS import service and startup hook

**Files:**
- Create: `lib/app/services/sms_import_service.dart`
- Modify: `lib/app/services/startup_service.dart`, `lib/app/bindings/initial_binding.dart` (new optional `SmsInboxProvider? smsInbox` param; register provider + service before `StartupService`), `test/helpers/test_services.dart` (pass a `FakeSmsInboxProvider`; tests get it with `Get.find<SmsInboxProvider>() as FakeSmsInboxProvider`, so `setUpTestServices`'s return type is unchanged — use the same pattern for every later fake)
- Test: `test/services/sms_import_service_test.dart`, `test/services/startup_service_test.dart`

**Interfaces:**
- Consumes: `BankSmsParser`, `ImportRepository`, `CategoryRepository`, `SettingsService`, `SmsInboxProvider`, `DatabaseService`.
- Produces:
  - `typedef CategorySuggester = Future<int?> Function(ParsedBankSms sms);` — the AI hook. Phase 1 passes none.
  - `class SmsImportService extends GetxService { SmsImportService({required SmsInboxProvider inbox, required ImportRepository imports, required CategoryRepository categories, required SettingsService settings, CategorySuggester? suggester}); Future<int> scan(DateTime now); }` — returns the number of items added. `suggester` is a mutable field so Phase 2 can set it.
  - `StartupService` gains a required `SmsImportService smsImport` and calls `await smsImport.scan(_clock())` inside `refresh()` before `notifyChanged()`, swallowing any exception.

- [ ] **Step 1: Write the failing tests** (`setUpTestServices`, fake inbox, settings `smsImportEnabled: true`, period start day 1, now = 2026-11-09 10:00):
  - disabled setting or `granted == false` or `supported == false` → `scan` returns 0 and `readCount == 0`;
  - first scan reads from period start: an SMS dated 2026-10-31 is ignored, one dated 2026-11-02 is added;
  - each fixture becomes the right pending item: card → `expense`, no category; CliQ sent → `expense`; CliQ received → `income` with category `دخل آخر` (seed icon `income_other`); fee → `expense` with category `أخرى` (icon `other`); announcement → nothing;
  - learned category wins: after learning `shop:SAMPLE SUPER MARKET → 5`, a new card SMS gets `suggestedCategoryId == 5`; same for a `cliq:` key and a `fee:` key (beating the `أخرى` default);
  - scan point becomes the newest SMS date read (including non-matching messages); a second scan with no new SMS adds 0;
  - **two identical card SMS with the same body and dates one second apart** in one scan → 2 items;
  - **concurrent `scan` calls** (`await Future.wait([s.scan(now), s.scan(now)])`) → items added once (total 1 for one SMS);
  - a `suggester` that is set is called only for `cardPurchase` items with no learned category, at most once per distinct `learnedKey` per scan; it is never called for CliQ or fee items;
  - pending items never store the body: `PendingItem.toMap()` keys are exactly the `pending_items` columns (no `body`, `account`, `balance`).
  - startup test: `StartupService.refresh()` triggers a scan (fake inbox `readCount` increments) and still notifies when the scan throws.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.** Guard concurrency with a `Future<int>? _running` (a second call awaits the first and returns 0). Start point = `scanPoint ?? settings.currentPeriod(now).start`. Default categories found by `iconKey` (`'income_other'`, `'other'`) from `CategoryRepository.getAll(includeArchived: false)`; missing → null. Note for each item = `sms.name` (spec §6.6 "note defaults to the shop or person name").
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: scan bank SMS into pending items on start and resume"`.

### Task 7: Review screen and Home banner

**Files:**
- Create: `lib/app/modules/import_review/{bindings/import_review_binding.dart, controllers/import_review_controller.dart, views/import_review_view.dart, widgets/pending_card.dart, widgets/pending_edit_sheet.dart}`
- Create: `lib/app/modules/home/widgets/import_banner.dart`
- Modify: `lib/app/routes/app_routes.dart` (`importReview = '/import-review'`), `lib/app/routes/app_pages.dart`, `lib/app/modules/home/controllers/home_controller.dart` (+ binding: inject `ImportRepository`), `lib/app/modules/home/views/home_view.dart`
- Test: `test/modules/import_review/import_review_controller_test.dart`, `test/modules/import_review/pending_card_test.dart`, `test/modules/home/home_controller_test.dart`

**Interfaces:**
- Consumes: `ImportRepository`, `CategoryRepository`, `RecurringRepository.getAll`, `TransactionRepository.getBetween`, `DuplicateCheck.find`, `SettingsService`, `DatabaseService`; shared widgets `KindToggle`, `CategoryGrid`, `AmountField`.
- Produces:
  - `ImportReviewController`: `items` (`RxList<PendingItem>`), `categoriesById`, `duplicateLabels` (`RxMap<int, String>` by item id), `Future<void> load()`, `bool canApproveDirectly(PendingItem)` (true when kind is income/expense and `suggestedCategoryId` is set, or kind is a debt kind with `personId` or `personName` set), `Future<bool> approve(PendingItem)`, `Future<bool> approveEdited(PendingItem item, {required PendingKind kind, required int amount, required DateTime date, int? categoryId, int? personId, String? personName, String? note})`, `Future<PendingItem?> dismiss(PendingItem)` (returns the item for Undo), `Future<void> undoDismiss(PendingItem)`. Reloads on `database.revision`.
  - `HomeController.pendingCount` (`RxInt`), loaded in `load()`; `openImportReview()` → `Get.toNamed(Routes.importReview)`.
  - Approving an income/expense item builds `TransactionRecord(kind, amount, categoryId, date: DateKeys.dateOnly(occurredAt), note: item.note)`.
  - Edit sheet for SMS items offers only مصروف | دخل (switching kind clears the category); debt mode is added in Task 15.

- [ ] **Step 1: Write the failing tests**
  - controller: load lists items newest first; `approve` on an item with a category writes one transaction (amount, kind, date, note) and the item leaves the list; `approve` on an item without a category returns false and writes nothing; `approveEdited` writes the edited values and learns the category; `dismiss` removes the item and `undoDismiss` brings it back; a card item matching an active recurring rule (same amount, due 2 days away) has `duplicateLabels[item.id] == rule.label`; a `DatabaseException` during approve shows `'تعذّر حفظ العملية، حاول مرة أخرى'` through `MessageService`.
  - widget `pending_card_test`: card shows the formatted amount, the name, the city, the category chip name (or `'بلا تصنيف'`), the warning line `'قد يكون مسجّلًا مسبقًا: قسط السيارة'`, and buttons `'اعتماد'`, `'تعديل'`, `'تجاهل'`; there is no `'اعتماد الكل'` text anywhere in the view.
  - home: `pendingCount` reflects pending rows and updates after `notifyChanged()`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** controller, view (app bar `'مراجعة الحركات'`, empty state `'لا توجد حركات جديدة'`, dismiss → SnackBar with `'تراجع'`), card, edit sheet (kind toggle, amount, category grid, date, note, save button `'حفظ واعتماد'`), Home banner text `'لديك {N} حركات جديدة للمراجعة'` (use `ArabicCount` for the noun if it reads better; N > 0 only), placed directly under `DebtsCard` before the due-obligation banner.
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: review screen for imported transactions and Home banner"`.

### Task 8: Settings switch for SMS import, README

**Files:**
- Modify: `lib/app/modules/settings/controllers/settings_controller.dart` (+ binding), `lib/app/modules/settings/views/settings_view.dart`, `README.md`
- Test: `test/modules/settings/smart_import_settings_test.dart`

**Interfaces:**
- Consumes: `SmsInboxProvider`, `SmsImportService.scan`.
- Produces: `SettingsController.smsSupported` (bool), `Future<void> setSmsImport(bool enabled)` — enabling requests permission; denied → setting stays false and `MessageService` shows `'لا يمكن قراءة رسائل البنك دون إذن الرسائل'`; granted → saves true and runs `scan(now)`. `bool get smsImportOn` = setting && permission (checked on load and on resume via `hasPermission`).

- [ ] **Step 1: Write the failing tests:** enabling with permission granted saves `smsImportEnabled == true` and calls scan (fake `readCount == 1`); denied keeps it false and shows the message; disabling saves false; `smsSupported == false` hides the tile (widget test: no `'استيراد رسائل البنك'` text).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.** New Settings card titled `'الاستيراد الذكي'` with `SwitchListTile` `'استيراد رسائل البنك'`, subtitle `'تُقرأ الرسائل على الهاتف فقط ولا تُحفظ'`. README: add the feature to the list, note that SMS import is Android-only and that `READ_SMS` blocks a future Play Store release.
- [ ] **Step 4: Run** `flutter analyze && flutter test` — Expected: clean / PASS.
- [ ] **Step 5: Manual check on the phone:** `flutter run` on the Android device, enable the switch, grant permission, confirm real bank SMS from this month appear for review, approve one, dismiss one, close/reopen the app: neither comes back.
- [ ] **Step 6: Commit** `git commit -m "feat: bank SMS import setting; README"`.

---

## Phase 2 — AI providers

### Task 9: Secret store

**Files:**
- Create: `lib/app/data/providers/secret_store.dart`
- Create: `test/helpers/fake_secret_store.dart`
- Modify: `pubspec.yaml` (`flutter_secure_storage`, latest stable), `lib/app/bindings/initial_binding.dart` (optional `SecretStore? secrets` param), `test/helpers/test_services.dart`

**Interfaces:**
- Produces: `abstract class SecretStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`, `class DeviceSecretStore` (FlutterSecureStorage, Android encrypted shared preferences), `String apiKeyName(AiProviderKind p) => 'ai_key_${p.name}'`, `class FakeSecretStore` (in-memory map).

- [ ] **Step 1: Implement** the three classes and register `SecretStore` in `InitialBinding`.
- [ ] **Step 2: Run** `flutter analyze && flutter test` — Expected: clean / PASS.
- [ ] **Step 3: Commit** `git commit -m "feat: secure key storage behind an interface"`.

### Task 10: Prompts and response parsing

**Files:**
- Create: `lib/app/core/logic/ai_prompts.dart`
- Test: `test/core/logic/ai_prompts_test.dart`

**Interfaces:**
- Produces:
  - `class VoiceResult { final PendingKind kind; final int amount; final String? category; final String? person; final String? note; final DateTime? date; }`
  - `abstract final class AiPrompts { static String category({required String merchant, String? city, required List<String> categories}); static String voice({required String text, required List<String> categories, required List<String> people, required DateTime today, required String currencyCode}); }`
  - `abstract final class AiResponses { static String? category(String raw, List<String> allowed); static VoiceResult? voice(String raw); }`

- [ ] **Step 1: Write the failing tests**
  - `AiPrompts.category(merchant: 'ROUTE 65', city: 'AMMAN', categories: [...])` contains `ROUTE 65`, `AMMAN`, every category name, and asks for JSON `{"category": ...}`;
  - `AiPrompts.voice(...)` contains the text, every category, every person, `2026-11-09`, `JOD`, the kinds `expense|income|debt_gave|debt_took`;
  - `AiResponses.category('{"category":"طعام"}', allowed) == 'طعام'`; a name not in `allowed` → null; JSON wrapped in ```json fences → parsed; garbage → null; `{"category":null}` → null;
  - `AiResponses.voice('{"kind":"expense","amount":"5.250","category":"طعام","person":null,"note":"سوبرماركت","date":null}')` → kind expense, amount 5250; `"debt_gave"` → `PendingKind.debtGave`; amount `"٥"` → 5000; missing/zero amount → null; unknown kind → null; bad date → `date == null`.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.** Prompts are Arabic-aware but written in English instructions, demanding only JSON. Response parsing strips code fences, `jsonDecode`s, and parses amount through `Money.parse(_, decimals: 3)`.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: AI prompts and strict response parsing"`.

### Task 11: AI clients (Gemini, Claude, OpenAI)

**Files:**
- Create: `lib/app/data/providers/ai_client.dart` (interface + factory), `lib/app/data/providers/ai/gemini_client.dart`, `.../claude_client.dart`, `.../openai_client.dart`
- Modify: `pubspec.yaml` (`http`, latest stable)
- Test: `test/data/providers/ai_clients_test.dart`

**Interfaces:**
- Produces:
  - `abstract class AiClient { Future<String> complete(String prompt, {required Duration timeout}); }` — returns the model's text; throws `AiException(String message)` on HTTP error, timeout or unexpected shape.
  - `AiClient createAiClient(AiProviderKind kind, {required String apiKey, String? model, http.Client? httpClient})` (throws on `none`).
  - Default model per provider: a `static const defaultModel` in each client. **Before writing it, look up the current fast/cheap model ID on each provider's official docs** (Claude: use the `claude-api` skill; Gemini: ai.google.dev; OpenAI: platform.openai.com) and note the source in a comment.
  - Request shapes: Gemini `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent` with header `x-goog-api-key`; Claude `POST https://api.anthropic.com/v1/messages` with `x-api-key` and `anthropic-version: 2023-06-01`; OpenAI `POST https://api.openai.com/v1/chat/completions` with `Authorization: Bearer`. Verify these against the same docs.

- [ ] **Step 1: Write the failing tests** using `MockClient`: for each provider, assert URL, auth header, the model (default and override), that the body contains the prompt, and that the reply text is extracted from that provider's response JSON; HTTP 401 → `AiException`; a request that never answers within `timeout` → `AiException`; a 200 with an unexpected body → `AiException`; the API key never appears in the URL query string.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** the three clients and the factory.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: Gemini, Claude and OpenAI clients behind one interface"`.

### Task 12: AI service and category suggestions during scan

**Files:**
- Create: `lib/app/services/ai_service.dart`
- Modify: `lib/app/bindings/initial_binding.dart` (optional `AiClient Function(AiProviderKind, String key, String? model)? aiClientFactory` param for tests; wire `SmsImportService.suggester`)
- Test: `test/services/ai_service_test.dart`

**Interfaces:**
- Consumes: `SettingsService`, `SecretStore`, `CategoryRepository`, `createAiClient`, `AiPrompts`, `AiResponses`.
- Produces `class AiService extends GetxService`:
  - `Future<bool> get isConfigured` (provider ≠ none and a key is stored)
  - `Future<int?> suggestCategory(ParsedBankSms sms)` — only for `cardPurchase`; sends `AiPrompts.category(merchant: sms.name, city: sms.city, categories: expense category names)`; 15 s timeout; maps the name back to an id; **returns null on any exception**.
  - `Future<VoiceResult> parseVoice(String text)` — 20 s timeout; throws `AiException` with a فصحى message on failure (used in Task 15).
  - `Future<void> testConnection()` — a tiny prompt; throws `AiException` on failure.
  - On init, sets `Get.find<SmsImportService>().suggester = suggestCategory`.

- [ ] **Step 1: Write the failing tests** with a fake `AiClient` that records prompts:
  - not configured → `suggestCategory` returns null without calling the client;
  - configured, reply `{"category":"طعام"}` → returns the طعام id;
  - reply naming an unknown category, garbage, or a thrown `AiException` → null, and `SmsImportService.scan` still adds the item with no category (end-to-end with the fake inbox);
  - the recorded prompt contains the merchant and city and **does not contain** the account `1234567`, the balance `120.250`, or the word `الرصيد`;
  - a CliQ item never triggers a client call.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: AI category suggestions for unknown shops"`.

### Task 13: AI settings section, internet permission, docs

**Files:**
- Modify: settings controller/view/binding, `android/app/src/main/AndroidManifest.xml` (add `<uses-permission android:name="android.permission.INTERNET"/>`), `README.md`, `docs/superpowers/specs/2026-10-01-expense-tracker-design.md` (§2: one line "Relaxed by the smart-import spec: AI calls only, only with a user key.")
- Test: `test/modules/settings/smart_import_settings_test.dart`

**Interfaces:**
- Produces on `SettingsController`: `Future<void> setAiProvider(AiProviderKind)`, `Future<void> saveApiKey(String key)` (trimmed; empty → ignored), `Future<void> deleteApiKey()`, `RxBool hasApiKey`, `Future<void> setAiModel(String text)` (empty → `clearAiModel`), `Future<bool> testAiConnection()` (shows `'تم الاتصال بنجاح'` or the error through `MessageService`).

- [ ] **Step 1: Write the failing tests:** choosing Gemini saves `aiProvider == gemini` in settings; `saveApiKey('  abc ')` writes `'abc'` under `ai_key_gemini` in `FakeSecretStore` and **nothing** in SQLite (assert the exported backup JSON does not contain `abc`); `deleteApiKey` removes it; keys are per provider (switching to Claude shows `hasApiKey == false`); empty model text stores null; test connection success/failure messages.
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** UI under `'الاستيراد الذكي'`: dropdown `'مزوّد الذكاء الاصطناعي'` (`'بدون'`, Gemini, Claude, OpenAI); masked `'مفتاح API'` field with show/hide and `'حذف المفتاح'`; `'النموذج'` text field (hint: the provider's default); `'اختبار الاتصال'` button. Key/model/test widgets hidden when provider is بدون. Manifest, README ("works offline; AI features go online only when you add a key"), base-spec note.
- [ ] **Step 4: Run** `flutter analyze && flutter test` — Expected: clean / PASS.
- [ ] **Step 5: Manual check:** enter a real Gemini key on the phone, tap اختبار الاتصال, then confirm an unknown shop's SMS arrives with a suggested category.
- [ ] **Step 6: Commit** `git commit -m "feat: AI provider settings with secure key; internet permission"`.

---

## Phase 3 — Voice entry

### Task 14: Speech provider

**Files:**
- Create: `lib/app/data/providers/speech_provider.dart`, `test/helpers/fake_speech.dart`
- Modify: `pubspec.yaml` (`speech_to_text`, latest stable), `AndroidManifest.xml` (`RECORD_AUDIO` permission and the `RecognitionService` `<queries>` intent that `speech_to_text` documents), `initial_binding.dart` (optional `SpeechProvider? speech`), `test_services.dart`

**Interfaces:**
- Produces: `abstract class SpeechProvider { Future<bool> init(); Future<void> start({required String localeId, required void Function(String text, bool isFinal) onResult}); Future<void> stop(); }`, `DeviceSpeechProvider` (speech_to_text; `listenFor: 30s`), `FakeSpeechProvider` (`available`, `emit(String text, {bool isFinal})`).

- [ ] **Step 1: Implement**, register.
- [ ] **Step 2: Run** `flutter analyze && flutter test && flutter build apk --debug` — Expected: clean / PASS / builds.
- [ ] **Step 3: Commit** `git commit -m "feat: speech-to-text provider behind an interface"`.

### Task 15: Voice entry flow and debt items

**Files:**
- Create: `lib/app/modules/import_review/controllers/voice_controller.dart`, `lib/app/modules/import_review/widgets/voice_sheet.dart`
- Modify: `import_review_controller.dart`, `pending_card.dart`, `pending_edit_sheet.dart`, `import_review_view.dart`, `import_review_binding.dart`, `home_view.dart` / `import_banner.dart` (mic button), `settings_controller.dart` (persist `voiceLanguage`)
- Test: `test/modules/import_review/voice_controller_test.dart`, `test/modules/import_review/import_review_controller_test.dart`

**Interfaces:**
- Consumes: `SpeechProvider`, `AiService.parseVoice`, `AiService.isConfigured`, `ImportRepository.addPending/approveAsDebt`, `DebtRepository.getPeople/addPerson`, `CategoryRepository`.
- Produces:
  - `enum VoiceState { idle, listening, editing, sending }`; `VoiceController`: `state`, `text` (`RxString`), `language` (`'ar-JO'` | `'en-US'`, from settings), `Future<void> setLanguage(String)`, `Future<void> startListening()`, `Future<void> stopListening()`, `Future<PendingItem?> send()` — calls `parseVoice(text)`, maps it (category name → id among current categories of the right kind; person name → existing `DebtPerson` id by case-insensitive trimmed match, else `personName`), stores it via `addPending` with `source: voice`, `occurredAt: date ?? now`, and returns it; the view then opens that item's edit sheet immediately (spec §6.7 step 4). On `AiException` shows its message and returns null.
  - `ImportReviewController.approve` for `debtGave`/`debtTook`: resolves the person (`personId`, or `DebtRepository.addPerson(personName)`, reusing an existing person on `DuplicateNameException`), then `approveAsDebt` with `DebtEntry(amount: +amount for debtGave, -amount for debtTook, date, note)`.
  - Edit sheet for voice items offers مصروف | دخل | دين; debt mode shows a person picker (existing names + "شخص جديد" text field) and direction `أعطيتُ` / `أخذتُ`. Edit sheet for SMS items still offers only مصروف | دخل.
  - Mic button: disabled when `!isConfigured`, tapping then shows `'الإدخال الصوتي يحتاج مفتاح ذكاء اصطناعي في الإعدادات'`.

- [ ] **Step 1: Write the failing tests**
  - voice: fake speech emits `'دفعت خمسة دنانير بالسوبرماركت'` final → `state == editing`, `text` set; the user edits the text before sending and the edited text is what reaches `parseVoice`; fake AI returns expense 5000 طعام → a pending voice item with that category exists and `send()` returns it; AI failure → message shown, no pending item; `setLanguage('en-US')` persists and the next `start` uses `en-US`; not configured → `startListening` does nothing and shows the message.
  - debt: voice result `debt_gave` 20000 person `'سامي'` with an existing person `'سامي'` → approve writes a `+20000` entry for that person; unknown person `'رنا'` → approve creates the person and a `-10000` entry for `debt_took`; SMS items' edit options never include debt (`controller.kindsFor(smsItem) == [expense, income]`, `kindsFor(voiceItem)` includes the debt kinds).
- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** controller, sheet (listening animation, live text, `عربي | English` toggle, stop, editable text field, `'إرسال'`), debt approve/edit, mic button in the review app bar and next to the Home banner (always shown on Home, even when N = 0, so voice is one tap from Home).
- [ ] **Step 4: Run** `flutter analyze && flutter test` — Expected: clean / PASS.
- [ ] **Step 5: Manual check on the phone:** say "دفعت 5 JD على Route 65" and "أعطيت سامي 20 دينار"; both arrive pre-filled; approve both; the expense is in Transactions, the debt on سامي's page.
- [ ] **Step 6: Commit** `git commit -m "feat: voice entry with AI extraction, including debts"`.
