import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/pending_item.dart';
import '../controllers/voice_controller.dart';

/// Listens as soon as it opens, shows the words live, lets the user fix them
/// and sends them. Pops the stored [PendingItem] once sent.
class VoiceSheet extends StatefulWidget {
  const VoiceSheet({super.key, required this.voice});

  final VoiceController voice;

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> {
  final _field = TextEditingController();
  late final Worker _syncField;

  VoiceController get _voice => widget.voice;

  @override
  void initState() {
    super.initState();
    _syncField = ever<String>(_voice.text, (value) {
      if (_field.text != value) _field.text = value;
    });
    _voice.startListening();
  }

  @override
  void dispose() {
    _syncField.dispose();
    _field.dispose();
    _voice.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    final item = await _voice.send();
    if (item != null && mounted) Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Obx(() {
            final state = _voice.state.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'ar-JO', label: Text('عربي')),
                    ButtonSegment(value: 'en-US', label: Text('English')),
                  ],
                  selected: {_voice.language},
                  onSelectionChanged: state == VoiceState.sending
                      ? null
                      : (s) => _voice.setLanguage(s.first),
                ),
                const SizedBox(height: 20),
                ...switch (state) {
                  VoiceState.listening => _listening(),
                  VoiceState.idle => _idle(),
                  VoiceState.editing ||
                  VoiceState.sending =>
                    _editing(sending: state == VoiceState.sending),
                },
              ],
            );
          }),
        ),
      ),
    );
  }

  List<Widget> _listening() {
    final words = _voice.text.value;
    return [
      const Center(child: _PulsingMic()),
      const SizedBox(height: 16),
      Text(
        words.isEmpty ? 'تحدّث الآن…' : words,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          color: words.isEmpty ? AppColors.muted : AppColors.ink,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: _voice.stopListening,
        icon: const Icon(Icons.stop),
        label: const Text('إيقاف'),
      ),
    ];
  }

  List<Widget> _idle() => [
        Center(
          child: IconButton.filled(
            iconSize: 36,
            tooltip: 'ابدأ التحدّث',
            onPressed: _voice.startListening,
            icon: const Icon(Icons.mic),
          ),
        ),
        const SizedBox(height: 12),
        const Text('اضغط الميكروفون وتحدّث',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted)),
      ];

  List<Widget> _editing({required bool sending}) => [
        TextField(
          controller: _field,
          enabled: !sending,
          minLines: 2,
          maxLines: 5,
          onChanged: _voice.edit,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'إعادة التسجيل',
              onPressed: sending ? null : _voice.startListening,
              icon: const Icon(Icons.mic_none),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed:
                    sending || _voice.text.value.trim().isEmpty ? null : _send,
                child: sending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('إرسال'),
              ),
            ),
          ],
        ),
      ];
}

/// A mic that gently pulses while listening.
class _PulsingMic extends StatefulWidget {
  const _PulsingMic();

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.9, end: 1.1).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(
          color: AppColors.primarySoft,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic, size: 40, color: AppColors.primary),
      ),
    );
  }
}
