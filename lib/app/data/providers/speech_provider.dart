import 'package:speech_to_text/speech_to_text.dart';

/// Speech-to-text. An interface so tests can use a fake.
abstract class SpeechProvider {
  /// Asks for the microphone permission and prepares recognition. Returns
  /// false when speech is unavailable or the permission is denied.
  Future<bool> init();

  /// Starts listening. [onResult] gets the text so far, and `isFinal` is true
  /// once the recognizer has settled on it. [onDone] fires once when the
  /// session ends by itself (silence, time limit or an error).
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  });

  Future<void> stop();
}

/// [SpeechProvider] backed by the Android speech recognizer.
class DeviceSpeechProvider implements SpeechProvider {
  final _speech = SpeechToText();

  /// The current session's [start] `onDone`, cleared once fired.
  void Function()? _onDone;

  @override
  Future<bool> init() async {
    try {
      // The plugin keeps the listeners of its first successful initialize,
      // so they forward to whichever session is current.
      return await _speech.initialize(
        onStatus: (status) {
          // "done" comes after the final result; "notListening" comes before
          // it, so it is not treated as the end.
          if (status == SpeechToText.doneStatus) _finish();
        },
        onError: (_) => _finish(),
      );
    } catch (_) {
      return false;
    }
  }

  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  }) {
    _onDone = onDone;
    return _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        partialResults: true,
      ),
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
    );
  }

  @override
  Future<void> stop() => _speech.stop();
}
