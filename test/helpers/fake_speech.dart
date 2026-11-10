import 'dart:async';

import 'package:calculator/app/data/providers/speech_provider.dart';

/// A speech recognizer the tests drive by hand.
class FakeSpeechProvider implements SpeechProvider {
  bool available = true;
  String? localeId;
  bool stopped = false;
  int startCount = 0;
  void Function(String text, bool isFinal)? onResult;
  void Function()? onDone;

  /// When set, [init] waits for it (and answers what it completes with).
  Completer<bool>? initGate;

  /// Completes when [init] is called.
  Completer<void> initCalled = Completer<void>();

  @override
  Future<bool> init() async {
    if (!initCalled.isCompleted) initCalled.complete();
    final gate = initGate;
    return gate == null ? available : gate.future;
  }

  @override
  Future<void> start({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  }) async {
    startCount++;
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
