/// Which AI service suggests categories and parses voice notes.
enum AiProviderKind { none, gemini, claude, openai }

class AppSettings {
  const AppSettings({
    this.periodStartDay = 1,
    this.currencyCode = 'JOD',
    this.currencyDecimals = 3,
    this.reminderEnabled = true,
    this.reminderMinutes = 21 * 60,
    this.lastMonthEndPromptPeriod,
    this.lastBackupAt,
    this.smsImportEnabled = false,
    this.aiProvider = AiProviderKind.none,
    this.aiModel,
    this.voiceLanguage = 'ar-JO',
  });

  factory AppSettings.fromMap(Map<String, Object?> map) {
    final backupAt = map['last_backup_at'] as int?;
    final provider = map['ai_provider'] as String?;
    return AppSettings(
      periodStartDay: map['period_start_day'] as int,
      currencyCode: map['currency_code'] as String,
      currencyDecimals: map['currency_decimals'] as int,
      reminderEnabled: map['reminder_enabled'] == 1,
      reminderMinutes: map['reminder_minutes'] as int,
      lastMonthEndPromptPeriod: map['last_month_end_prompt_period'] as String?,
      lastBackupAt:
          backupAt == null ? null : DateTime.fromMillisecondsSinceEpoch(backupAt),
      smsImportEnabled: map['sms_import_enabled'] == 1,
      aiProvider: provider == null
          ? AiProviderKind.none
          : AiProviderKind.values.byName(provider),
      aiModel: map['ai_model'] as String?,
      voiceLanguage: map['voice_language'] as String? ?? 'ar-JO',
    );
  }

  final int periodStartDay;
  final String currencyCode;
  final int currencyDecimals;
  final bool reminderEnabled;

  /// Minutes after midnight for the daily reminder (1260 = 21:00).
  final int reminderMinutes;
  final String? lastMonthEndPromptPeriod;
  final DateTime? lastBackupAt;
  final bool smsImportEnabled;
  final AiProviderKind aiProvider;
  final String? aiModel;
  final String voiceLanguage;

  AppSettings copyWith({
    int? periodStartDay,
    String? currencyCode,
    int? currencyDecimals,
    bool? reminderEnabled,
    int? reminderMinutes,
    String? lastMonthEndPromptPeriod,
    DateTime? lastBackupAt,
    bool? smsImportEnabled,
    AiProviderKind? aiProvider,
    String? aiModel,
    bool clearAiModel = false,
    String? voiceLanguage,
  }) =>
      AppSettings(
        periodStartDay: periodStartDay ?? this.periodStartDay,
        currencyCode: currencyCode ?? this.currencyCode,
        currencyDecimals: currencyDecimals ?? this.currencyDecimals,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        lastMonthEndPromptPeriod:
            lastMonthEndPromptPeriod ?? this.lastMonthEndPromptPeriod,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        smsImportEnabled: smsImportEnabled ?? this.smsImportEnabled,
        aiProvider: aiProvider ?? this.aiProvider,
        aiModel: clearAiModel ? null : aiModel ?? this.aiModel,
        voiceLanguage: voiceLanguage ?? this.voiceLanguage,
      );

  Map<String, Object?> toMap() => {
        'period_start_day': periodStartDay,
        'currency_code': currencyCode,
        'currency_decimals': currencyDecimals,
        'reminder_enabled': reminderEnabled ? 1 : 0,
        'reminder_minutes': reminderMinutes,
        'last_month_end_prompt_period': lastMonthEndPromptPeriod,
        'last_backup_at': lastBackupAt?.millisecondsSinceEpoch,
        'sms_import_enabled': smsImportEnabled ? 1 : 0,
        'ai_provider': aiProvider.name,
        'ai_model': aiModel,
        'voice_language': voiceLanguage,
      };

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.periodStartDay == periodStartDay &&
      other.currencyCode == currencyCode &&
      other.currencyDecimals == currencyDecimals &&
      other.reminderEnabled == reminderEnabled &&
      other.reminderMinutes == reminderMinutes &&
      other.lastMonthEndPromptPeriod == lastMonthEndPromptPeriod &&
      other.lastBackupAt == lastBackupAt &&
      other.smsImportEnabled == smsImportEnabled &&
      other.aiProvider == aiProvider &&
      other.aiModel == aiModel &&
      other.voiceLanguage == voiceLanguage;

  @override
  int get hashCode => Object.hash(periodStartDay, currencyCode,
      currencyDecimals, reminderEnabled, reminderMinutes,
      lastMonthEndPromptPeriod, lastBackupAt, smsImportEnabled, aiProvider,
      aiModel, voiceLanguage);
}
