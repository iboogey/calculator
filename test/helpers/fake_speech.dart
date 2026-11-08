import 'package:calculator/app/data/providers/speech_provider.dart';

/// A speech recognizer the tests drive by hand.
class FakeSpeechProvider implements SpeechProvider {
  bool available = true;
  String? localeId;
  bool stopped = false;
  void Function(String text, bool isFinal)? onResult;

  @override
  Future<bool> init() async => available;

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    this.localeId = localeId;
    this.onResult = onResult;
    stopped = false;
  }

  @override
  Future<void> stop() async => stopped = true;

  /// Delivers recognized text as if the user had spoken it.
  void emit(String text, {bool isFinal = false}) =>
      onResult?.call(text, isFinal);
}
