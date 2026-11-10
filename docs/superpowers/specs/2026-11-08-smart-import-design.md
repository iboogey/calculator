# Smart Import (Bank SMS + Voice) — Design Spec

**Date:** 2026-11-08
**Status:** Approved (2026-11-09)
**Builds on:** `docs/superpowers/specs/2026-10-01-expense-tracker-design.md` and `docs/superpowers/specs/2026-11-08-debts-and-fusha-design.md`
**Changes a base constraint:** the base spec's "No internet" rule (§2) is relaxed. See §5.

---

## 1. Why

The user types every expense by hand. Their bank already texts them about every card purchase, CliQ transfer and bank fee, so most of that typing is wasted. They want the app to read these texts and get each one ready as an entry. They also want to add entries by voice, speaking Arabic, English or a mix.

**The user approves every entry.** Some payments are already in the app. The car instalment, for example, is a recurring rule that creates its expense automatically, and the bank text for it would count it twice. Nothing reaches the books until the user taps approve.

## 2. Goals

- On app open and on resume, new bank SMS become **pending items** in one review list.
- Each pending item arrives pre-filled: kind, amount (exact, in fils), date, shop or person, and a suggested category.
- The user can approve, edit or dismiss each item. Nothing is saved until they approve.
- Possible duplicates (recurring rules, existing transactions) are flagged on the item.
- **Bank texts only ever become expenses or income (decided by the user, 2026-11-09).** Debts are added only by hand (the existing Debts screens) or by voice. When a CliQ transfer was really a loan, the user dismisses it and records the debt themselves.
- The app remembers the category chosen for each shop, so the user corrects a shop only once.
- An optional AI provider (Gemini, Claude or OpenAI, with the user's own key) suggests categories for shops never seen before, and powers voice entry.
- Voice entry: press the mic, speak, and get a pending item to review.

## 3. Non-goals

- No iPhone support for SMS reading (iOS doesn't allow it). On iOS the SMS feature is hidden. Voice still works.
- No background scanning while the app is closed (no WorkManager or SMS broadcast receiver). Scanning happens on app open and resume only.
- No other banks' message formats for now. The templates are written for the user's bank (§6.2), and new formats are added in code later.
- No automatic approval, not even for shops the app has learned.
- No bank balance tracking. The balance and account in the text are matched by the parser but thrown away right after.
- No AI for reading the messages themselves. Parsing is deterministic code.

## 4. Anti-goals (would be a failure even if it works)

- Anything reaching transactions or debts without an explicit approve tap.
- A parsed amount that differs from the SMS by even one fils.
- The same SMS showing up again after it was approved or dismissed, including after a backup restore.
- **Bank messages kept by the app (decided by the user, 2026-11-09).** The app never stores SMS text, account numbers or balances, and keeps no record of handled messages. A pending item lives only until it is approved or dismissed. Then it is deleted, and an approved one survives only as a normal transaction (or, for voice, a debt entry). Nothing from the bank goes into the backup.
- An API key, a real SMS, a real name or a real account number committed to the public GitHub repo, including in tests and fixtures.
- An API key ending up in the backup file.
- The full SMS text, balance or account number being sent to an AI provider.
- The app breaking, or the review list failing to load, when there is no key, no internet, or the AI returns garbage.

## 5. Constraints

All base constraints hold (money as `int` thousandths, dates as `YYYY-MM-DD`, Arabic RTL فصحى UI, GetX Pattern, repositories as the only data access, `DatabaseService.notifyChanged()` after writes, `MessageService` for errors), **except:**

- **Internet (decided by the user, 2026-11-08):** the app may go online, **only** for AI calls, and only when the user has entered a key. Add the `INTERNET` permission to the release manifest. Update the README ("fully offline, no internet") and add a note to the base spec's §2.
- **The repo is public.** No secrets or personal data in the repo. Test fixtures use made-up names, account numbers and balances in the real templates (examples in §6.2).
- **Android only for SMS.** Requires the `READ_SMS` runtime permission. The app is sideloaded for personal use, so the Play Store's SMS policy doesn't apply now. Note it in the README as a blocker for any future Play Store release.
- New platform code (SMS reading, secure storage, speech-to-text, HTTP) sits behind provider interfaces and is faked in tests, like `NotificationProvider` and `FileExchangeProvider`.

---

## 6. Behaviour

### 6.1 Scanning

- `StartupService.refresh()` (app start and resume) also runs the SMS scan when SMS import is on and the permission is granted.
- **First scan:** messages dated from the start of the current financial period (`Period` with `periodStartDay`). Older messages are skipped. *(Builder's call; easy to change.)*
- **Later scans:** only messages newer than the last scan point. The app stores just one timestamp: the date of the newest SMS it has read. *(This replaces per-message records, by the user's decision.)*
- Every message goes through the parser (§6.2). Messages matching no template are ignored and not stored. This covers announcements like maintenance notices.
- The scan doesn't filter by sender. A message counts only if it matches a template exactly.
- **No re-imports:** the scan point only moves forward, so an SMS is read once. After that it exists only as a pending item until the user approves or dismisses it. Then the pending row is **deleted**. The balance and account number are read during parsing (to recognise the template) but never stored.
- **Scan point and backup:** the scan point is device-only. It is **not** in the backup, and a restore leaves the device's current value alone, so a restore never re-imports anything. On a fresh install with no scan point, the first-scan rule applies.
- After a scan that adds items, any open screen updates (`notifyChanged`).

### 6.2 Templates (deterministic parser, pure Dart, in `core/logic/`)

Four templates. Amounts are read with `Money` parsing into fils, never `double`. Whitespace is normalized first: the bank pads merchant and city fields with runs of spaces.

| # | Template (Arabic, as sent) | Meaning | Extracted |
|---|---|---|---|
| 1 | `تفويض حركة على حسابكم {acct} بقيمة {amt} دينار اردني من {merchant} {city} {country} الرصيد المتوفر {bal} دينار اردني` | Card purchase → expense | amount, account, merchant, city, balance |
| 2 | `حوالة كليك صادرة بمبلغ {amt} دينار اردني من حسابكم {acct} الى {name} الرصيد المتوفر {bal} دينار اردني` | CliQ sent | amount, account, person name, balance |
| 3 | `حوالة كليك واردة بمبلغ {amt} دينار اردني لحسابكم {acct} من {name} الرصيد المتوفر {bal} دينار اردني` | CliQ received | amount, account, person name, balance |
| 4 | `قيد مبلغ {amt} دينار اردني على حسابكم {acct} وذلك {reason}` | Bank fee or charge → expense | amount, account, reason (no balance) |

Template 1 merchant field: the bank cuts the merchant name to a fixed width and pads it with spaces, then the city, then a 3-letter country code. Split on runs of 2+ spaces. Real examples: `ROUTE 65                 AMMAN       JOR` and `ABU BAKER FISH REST 2  AQABA         JOR`. Merchant names can be truncated (`SESBANIA ELECTRICITY R`). Keep them as-is: the bank truncates the same way every time.

**Fixture examples (fabricated, use these styles in tests):**

```
تفويض حركة على حسابكم 1234567 - 001 بقيمة 3.5 دينار اردني من SAMPLE SUPER MARKET      AMMAN       JOR الرصيد المتوفر 120.250 دينار اردني
حوالة كليك صادرة بمبلغ 25.0 دينار اردني من حسابكم 1234567 - 001 الى SAMI KHALED HADDAD الرصيد المتوفر 95.250 دينار اردني
حوالة كليك واردة بمبلغ 10.0 دينار اردني لحسابكم 1234567 - 001 من RANA OMAR SALEH الرصيد المتوفر 105.250 دينار اردني
قيد مبلغ 0.5 دينار اردني على حسابكم 7654321 - 002 وذلك عمولة خدمات مصرفية الية
متعاملنا الكريم، قد تتأثر بعض خدماتنا البنكية ليلة الجمعة من الساعة 02:00 – 06:00 صباحاً.   ← must be ignored
```

All accounts count. The user has two, and both are imported.

### 6.3 Pending items: what each becomes

| Source | Becomes | Category suggestion |
|---|---|---|
| Card purchase | Expense | From memory (§6.4), then AI, otherwise none |
| CliQ sent | Expense | From memory, otherwise none (never AI) |
| CliQ received | Income | From memory, otherwise "دخل آخر" *(builder's call)* |
| Bank fee | Expense | From memory, otherwise "أخرى" |
| Voice | Expense, income or a debt entry, whatever the AI extracted (§6.7) | From the AI's answer |

An SMS item can only switch between expense and income in the edit sheet. It **never** offers a debt option. The user records debts by hand or by voice and dismisses the SMS.

### 6.4 Memory (learning from approvals)

- **Name → category:** when the user approves an SMS item, store `name key → category id`. The name is the merchant (card purchase), the CliQ name (transfers) or the reason (bank fee). The key is the name trimmed, with spaces collapsed and in upper case, prefixed with its type (`shop:`, `cliq:`, `fee:`), so a shop and a person with the same name don't mix. One table holds all of it.
- Many CliQ transfers go to shops and service providers (a barber, a small store), so CliQ names are learned exactly like shops: approve "AHMAD SAMIR ALI" as طعام once, and طعام is suggested next time.
- Later approvals overwrite earlier ones (last choice wins). Voice items don't feed memory.
- **CliQ names are never sent to the AI.** They are often real people's names. An unknown CliQ name gets no AI suggestion. *(Builder's call, for privacy.)*
- Lookup order for a category suggestion: **memory → AI (if configured) → none.** An AI suggestion is never stored until the user approves it.
- Memory tables are included in the backup (§6.10).

### 6.5 Duplicate warning

Each pending item is checked when shown. If it matches either rule below, the card shows a warning line: "قد يكون مسجّلًا مسبقًا: {label}".

- **Recurring rule:** an active income or expense rule with the same amount and same kind whose due date is within ±3 days of the SMS date.
- **Existing transaction:** a transaction with the same amount and kind within ±1 day.

The warning is information only. Approve and dismiss both stay available. A typical case: the car instalment is a recurring rule, the bank texts it, the warning shows, and the user dismisses it.

### 6.6 Review screen and Home entry point

- **Home:** a banner "لديك {N} حركات جديدة للمراجعة", shown with the other Home banners when N > 0. Tapping it opens the review screen. *(Placement among existing banners is the builder's call.)*
- **Review screen** (new module `import_review`): a list of pending items, newest first. Each card shows:
  - the source icon (SMS or mic), date and time, signed amount
  - the shop or person name (and the city for card purchases)
  - the suggested category chip (or "بلا تصنيف" when there is none). Voice debt items show "دين: {person}" instead.
  - the duplicate warning, if any
  - three actions: **اعتماد** (approve), **تعديل** (edit), **تجاهل** (dismiss)
- **Approve** writes the item as suggested: a transaction (`TransactionRepository`), or for a voice debt item a debt entry (`DebtRepository.addEntry`). It deletes the pending row and updates memory. An item with no category can't be approved directly: approve opens edit.
- **Edit** opens a sheet to change kind (expense / income), category, amount, date and note, then saves and approves in one go. For voice debt items, it edits person, direction (أعطيتُ / أخذتُ), amount, date and note instead. *(Reusing `TransactionFormView` / the debt entry sheet with prefilled arguments, or a dedicated sheet, is the builder's call.)*
- **Approve and dismiss both delete the pending row.** Dismiss shows an Undo snackbar, which puts the item back.
- There is no "approve all" button. Every item needs its own tap, by the user's decision.
- The **mic button** for voice entry lives in the review screen's app bar or as a FAB, and on Home next to the review banner. *(Exact placement is the builder's call. It must be reachable from Home in one tap.)*
- Empty state: "لا توجد حركات جديدة".
- **Note:** the approved transaction's note defaults to the shop or person name (e.g. "ROUTE 65").

### 6.7 Voice entry

One path for every provider (decided by the user, 2026-11-09): **Android speech-to-text → text → AI with the extraction prompt.**

1. The user presses the mic. Android's speech recognizer listens live and shows the words as they are recognized. A language toggle **عربي | English** sits on the listening sheet, default عربي (`ar-JO`), and the last choice is remembered. Mixed sentences work best in the Arabic mode.
2. When the user stops talking (or taps stop), the final text is shown and can be fixed by typing before sending. *(Builder's call: it lets the user fix a misheard number.)*
3. The text goes to the chosen provider, whichever it is (Gemini, Claude or OpenAI), with the extraction prompt. The provider must return JSON: `{kind: expense|income|debt_gave|debt_took, amount: "5.250", category: <one of the app's category names or null>, person: <string or null>, note: <string or null>, date: "YYYY-MM-DD" or null}`. The prompt includes the app's category list, existing debt person names, today's date and the currency.
4. The result becomes a pending item (source `voice`) and its edit sheet opens immediately, pre-filled, so the user can confirm it in one tap.
5. A failure (no internet, bad JSON, missing amount) shows a فصحى error message through `MessageService`. Nothing is created.
6. With no key set, the mic button is shown disabled. Tapping it explains that voice needs an AI key in Settings.

**Known limit:** on many phones, Android's recognizer is Google's speech service, which processes the voice online, the same as voice typing on the keyboard. The user accepted this by choosing this path.

Example utterances the prompt must handle: "دفعت خمسة دنانير بالسوبرماركت", "paid 19 JD at Route 65", "أعطيت سامي ٢٠ دينار", "دفعت 5 JD على البنزين".

### 6.8 AI providers

- **Interface** (`AiProvider`, in `data/providers/`): `suggestCategory(merchant, city, categories) → categoryName?` and `parseVoice(text, context) → VoiceResult`. One implementation per provider (Gemini, Claude, OpenAI), using plain HTTPS calls with the `http` package (no vendor SDKs).
- **What is sent:**
  - category suggestion: only the merchant name, the city and the category list
  - voice: the recognized text, the category list, debt person names and today's date
  - never the SMS text, account numbers or balances
- **Model:** each provider has a default model ID, which the builder picks: the current cheap or fast model at implementation time, since IDs change. The user can override it with a text field in Settings.
- **When it's called:** category suggestion runs during the scan, only for items whose merchant isn't in memory, at most once per distinct merchant per scan. It is skipped silently if the call fails or there's no key: the item just has no category.
- **Timeouts:** 15 s for categorization, 20 s for voice.

### 6.9 Settings

A new section **"الاستيراد الذكي"** in Settings:

- **استيراد رسائل البنك:** switch. Turning it on requests `READ_SMS`. If permission is denied, the switch turns back off with an explanation. Hidden on iOS.
- **مزوّد الذكاء الاصطناعي:** dropdown with بدون (none) / Gemini / Claude / OpenAI. Default بدون.
- **مفتاح API:** a masked field with show/hide, saved with **`flutter_secure_storage`** (Android Keystore), one key per provider. Never stored in SQLite, never logged, never in the backup. A "حذف المفتاح" (delete key) action is included.
- **النموذج:** optional text field. Empty means the provider's default.
- **اختبار الاتصال:** a button that makes one tiny call and shows success or the error.
- The provider choice and model name are stored in the `settings` table, so they are backed up. The key is not.

### 6.10 Data model and backup

- New tables, plus a migration from DB version 2 to 3:
  - `pending_items` (only items waiting for review; rows are deleted on approve or dismiss): id, source (`sms` / `voice`), kind, amount (int fils), occurred_at, merchant, city, person_name, raw_type (template #), suggested_category_id, suggested_person_id (voice debts only), note, created_at. No account, no balance, no SMS text.
  - `learned_categories`: name_key PK (prefixed `shop:` / `cliq:` / `fee:`), category_id (FK `categories` ON DELETE CASCADE)
- New `settings` columns: `sms_import_enabled`, `ai_provider`, `ai_model`, `voice_language`. The SMS scan point is stored outside the backed-up `settings` row (a device-only table or local key, builder's call), so restore never touches it.
- **Backup:** schema version 3 includes `learned_categories` and the new settings columns. `pending_items` and the scan point are **not** backed up. A restore leaves both as they are on the device. Version 1 and 2 files still restore.
- A restore never re-imports SMS (the scan point isn't in the backup).
- Raw SMS bodies are **not** stored. Only the parsed fields are.

### 6.11 Errors and edge cases

- SMS permission revoked later: the scan is skipped silently, and Settings shows the switch as off.
- A message matches a template but the amount fails to parse: it's skipped and logged in debug only.
- A category or person deleted while an item is pending: the suggestion falls back to none or a picker, and memory rows pointing to it are removed (FK cascade or a check on read).
- Clock or ordering issues: items are sorted by `occurred_at` from the SMS date, not by scan time.
- A huge first inbox: the scan reads only messages from the current period, so it stays bounded.

---

## 7. Phases (build order, decided)

1. **SMS import without AI:** parser + tests, SMS provider, `pending_items`, review screen, Home banner, memory, duplicate warning, settings switch, backup v3.
2. **AI providers:** settings section, secure key storage, `AiProvider` × 3, category suggestion during scan, test-connection button, internet permission, README/spec updates.
3. **Voice entry:** Android speech-to-text with an Arabic/English toggle, extraction prompt, voice → pending item → edit sheet.

Each phase is usable on its own.

## 8. Testing

- The parser is fully unit-tested with fabricated fixtures in all four templates, plus non-matching messages (announcements, OTP-style texts) and edge cases: padded merchant fields, truncated names, amounts like `10.0`, `5.24`, `176.464`.
- Repositories are tested on the in-memory test database (existing `test_database.dart` pattern): the scan point only moving forward, approve → transaction (and the pending row deleted), voice debt → debt entry, memory updates, migration v2 → v3, backup v3 round-trip, v2 file restore.
- AI providers are tested against a fake HTTP client: request shape (prove no SMS text, account or balance is sent), JSON parsing, garbage responses, timeouts.
- Controllers are tested with fake SMS / AI / secure-storage providers.
- **No real SMS, names, account numbers or keys anywhere in `test/`.**

## 9. Left to the builder

- The SMS reading mechanism: a small Kotlin method channel querying `content://sms/inbox`, or a maintained pub package. Prefer whichever is smaller and maintained.
- The speech-to-text package.
- Default model IDs for each provider.
- Exact Home placement of the banner and the mic button, and the edit sheet's implementation (§6.6).
- Prompt wording, kept in one place per task.
