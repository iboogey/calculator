import 'package:http/http.dart' as http;

import '../ai_client.dart';

class ClaudeClient implements AiClient {
  ClaudeClient({required this.apiKey, String? model, required this.httpClient})
    : model = model ?? defaultModel;

  // Source: Anthropic models overview, https://platform.claude.com/docs/en/about-claude/models/overview
  // Claude Haiku 5.5 is the current fastest/cheapest model.
  static const defaultModel = 'claude-haiku-5-5';

  final String apiKey;
  final String model;
  final http.Client httpClient;

  @override
  Future<String> complete(String prompt, {required Duration timeout}) {
    // No temperature: Haiku 5.5 rejects non-default sampling values.
    return postForText(
      httpClient,
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
      body: {
        'model': model,
        'max_tokens': aiMaxOutputTokens,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      },
      timeout: timeout,
      extract: (json) {
        final blocks = (json as Map)['content'] as List;
        return blocks
            .where((b) => (b as Map)['type'] == 'text')
            .map((b) => (b as Map)['text'] as String)
            .join();
      },
    );
  }
}
