import 'package:speech_to_text/speech_to_text.dart';

/// Speech-to-text. An interface so tests can use a fake.
abstract class SpeechProvider {
  /// Asks for the microphone permission and prepares recognition. Returns
  /// false when speech is unavailable or the permission is denied.
  Future<bool> init();

  /// Starts listening. [onResult] gets the text so far, and `isFinal` is true
  /// once the recognizer has settled on it.
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  });

  Future<void> stop();
}

/// [SpeechProvider] backed by the Android speech recognizer.
class DeviceSpeechProvider implements SpeechProvider {
  final _speech = SpeechToText();

  @override
  Future<bool> init() async {
    try {
      return await _speech.initialize();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) =>
      _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(seconds: 30),
          partialResults: true,
        ),
        onResult: (result) =>
            onResult(result.recognizedWords, result.finalResult),
      );

  @override
  Future<void> stop() => _speech.stop();
}
