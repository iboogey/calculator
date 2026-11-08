import 'package:calculator/app/data/providers/ai_client.dart';

/// An AI client that answers with [reply] and records every prompt.
class FakeAiClient implements AiClient {
  FakeAiClient(this.reply);

  /// A reply string, or anything else to throw.
  Object reply;
  final prompts = <String>[];

  @override
  Future<String> complete(String prompt, {required Duration timeout}) async {
    prompts.add(prompt);
    final r = reply;
    if (r is! String) throw r;
    return r;
  }
}
