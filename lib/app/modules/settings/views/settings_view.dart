import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/arabic_count.dart';
import '../../../core/utils/currencies.dart';
import '../../../data/models/app_settings.dart';
import '../../../routes/app_routes.dart';
import '../../../widgets/app_bottom_nav.dart';
import '../controllers/settings_controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: Obx(() {
        final settings = controller.settings;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            const _SectionTitle('الشهر المالي'),
            Card(
              child: ListTile(
                title: const Text('يبدأ الشهر يوم'),
                subtitle: const Text('مثلاً يوم إيداع الراتب'),
                trailing: DropdownButton<int>(
                  value: settings.periodStartDay,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var day = 1; day <= 28; day++)
                      DropdownMenuItem(value: day, child: Text('$day')),
                  ],
                  onChanged: (day) {
                    if (day != null) controller.setStartDay(day);
                  },
                ),
              ),
            ),
            const _SectionTitle('العملة'),
            Card(
              child: ListTile(
                title: const Text('العملة'),
                trailing: DropdownButton<String>(
                  value: settings.currencyCode,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final currency in Currencies.all)
                      DropdownMenuItem(
                        value: currency.code,
                        child: Text('${currency.name} (${currency.symbol})'),
                      ),
                  ],
                  onChanged: (code) {
                    if (code != null) controller.setCurrency(code);
                  },
                ),
              ),
            ),
            const _SectionTitle('التذكير اليومي'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('ذكّرني بتسجيل مصاريفي'),
                    value: settings.reminderEnabled,
                    onChanged: controller.setReminderEnabled,
                  ),
                  ListTile(
                    enabled: settings.reminderEnabled,
                    title: const Text('الساعة'),
                    trailing: Text(
                      controller.reminderLabel,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () => _pickTime(context, settings.reminderMinutes),
                  ),
                  if (!controller.permissionGranted)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'الإشعارات معطّلة لهذا التطبيق. فعّلها من إعدادات الجهاز لتصلك التذكيرات وتنبيهات الميزانية.',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const _SectionTitle('الاستيراد الذكي'),
            Card(
              child: Column(
                children: [
                  if (controller.smsSupported)
                    SwitchListTile(
                      title: const Text('استيراد رسائل البنك'),
                      subtitle:
                          const Text('تُقرأ الرسائل على الهاتف فقط ولا تُحفظ'),
                      value: controller.smsImportOn,
                      onChanged: controller.setSmsImport,
                    ),
                  ListTile(
                    title: const Text('مزوّد الذكاء الاصطناعي'),
                    trailing: DropdownButton<AiProviderKind>(
                      value: settings.aiProvider,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                            value: AiProviderKind.none, child: Text('بدون')),
                        DropdownMenuItem(
                            value: AiProviderKind.gemini,
                            child: Text('Gemini')),
                        DropdownMenuItem(
                            value: AiProviderKind.claude,
                            child: Text('Claude')),
                        DropdownMenuItem(
                            value: AiProviderKind.openai,
                            child: Text('OpenAI')),
                      ],
                      onChanged: (kind) {
                        if (kind != null) controller.setAiProvider(kind);
                      },
                    ),
                  ),
                  if (settings.aiProvider != AiProviderKind.none) ...[
                    _ApiKeyField(
                      key: ValueKey('key-${settings.aiProvider.name}'),
                      controller: controller,
                    ),
                    _ModelField(
                      key: ValueKey('model-${settings.aiProvider.name}'),
                      controller: controller,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton(
                          onPressed: controller.testingConnection.value
                              ? null
                              : controller.testAiConnection,
                          child: const Text('اختبار الاتصال'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const _SectionTitle('إدارة'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.event_repeat_outlined),
                    title: const Text('المصاريف الثابتة'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: controller.openRecurring,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('المفضّلة'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: controller.openFavorites,
                  ),
                ],
              ),
            ),
            const _SectionTitle('النسخ الاحتياطي'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('نسخة احتياطية الآن'),
                    subtitle: Text(
                      controller.lastBackupLabel,
                      style: TextStyle(
                          color: controller.backupOverdue
                              ? AppColors.warning
                              : AppColors.muted),
                    ),
                    onTap: controller.exportBackup,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('استرجاع من ملف'),
                    onTap: () => _restore(context),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
      bottomNavigationBar: const AppBottomNav(current: Routes.settings),
    );
  }

  Future<void> _restore(BuildContext context) async {
    final summary = await controller.pickBackup();
    if (summary == null || !context.mounted) return;
    final when = summary.exportedAt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع النسخة؟'),
        content: Text(
          'ستُحذف بياناتك الحالية وتحلّ محلّها نسخة '
          '${when.day}/${when.month}/${when.year}: '
          '${ArabicCount.restoreSummary(summary.transactionCount, summary.goalCount)}.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استرجاع'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final restored = await controller.restore(summary);
    if (restored && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تمت استعادة النسخة')));
    }
  }

  Future<void> _pickTime(BuildContext context, int minutes) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked != null) controller.setReminderTime(picked.hour, picked.minute);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The key text lives only in this widget's state until saved; the stored key
/// is never read back or shown.
class _ApiKeyField extends StatefulWidget {
  const _ApiKeyField({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  final _text = TextEditingController();
  bool _hidden = true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _text.text;
    if (value.trim().isEmpty) return;
    final saved = await widget.controller.saveApiKey(value);
    if (saved && mounted) _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final has = widget.controller.hasApiKey.value;
      return _build(has);
    });
  }

  Widget _build(bool has) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('apiKeyField'),
              controller: _text,
              obscureText: _hidden,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'مفتاح API',
                helperText: has ? 'تم حفظ المفتاح' : null,
                suffixIcon: IconButton(
                  tooltip: _hidden ? 'إظهار' : 'إخفاء',
                  icon: Icon(_hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
          IconButton(
            key: const Key('saveApiKey'),
            tooltip: 'حفظ',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
          if (has)
            IconButton(
              tooltip: 'حذف المفتاح',
              icon: const Icon(Icons.delete_outline),
              onPressed: widget.controller.deleteApiKey,
            ),
        ],
      ),
    );
  }
}

class _ModelField extends StatefulWidget {
  const _ModelField({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<_ModelField> createState() => _ModelFieldState();
}

class _ModelFieldState extends State<_ModelField> {
  late final _text = TextEditingController(
      text: widget.controller.settings.aiModel ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.controller.settings.aiProvider;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _text,
        autocorrect: false,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'النموذج',
          hintText: widget.controller.defaultModelFor(kind),
        ),
        onSubmitted: widget.controller.setAiModel,
        onTapOutside: (_) => widget.controller.setAiModel(_text.text),
      ),
    );
  }
}
