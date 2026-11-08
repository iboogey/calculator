import 'package:calculator/app/data/providers/speech_provider.dart';

/// A speech recognizer the tests drive by hand.
class FakeSpeechProvider implements SpeechProvider {
  bool available = true;
  String? localeId;
  bool stopped = false;
  void Function(String text, bool isFinal)? onResult;
  void Function()? onDone;

  @override
  Future<bool> init() async => available;

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  }) async {
    this.localeId = localeId;
    this.onResult = onResult;
    this.onDone = onDone;
    stopped = false;
  }

  @override
  Future<void> stop() async => stopped = true;

  /// Delivers recognized text as if the user had spoken it.
  void emit(String text, {bool isFinal = false}) =>
      onResult?.call(text, isFinal);

  /// Ends the session as if the recognizer had stopped by itself.
  void done() => onDone?.call();
}
