import 'package:http/http.dart' as http;

import '../ai_client.dart';

class OpenAiClient implements AiClient {
  OpenAiClient({required this.apiKey, String? model, required this.httpClient})
    : model = model ?? defaultModel;

  // Source: https://developers.openai.com/api/docs/models (cheapest listed,
  // supports Chat Completions per its model page).
  static const defaultModel = 'gpt-6-luna';

  final String apiKey;
  final String model;
  final http.Client httpClient;

  @override
  Future<String> complete(String prompt, {required Duration timeout}) {
    // max_completion_tokens (not max_tokens) and no temperature: accepted by
    // reasoning-capable models. The cap leaves headroom for reasoning tokens.
    return postForText(
      httpClient,
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {'Authorization': 'Bearer $apiKey'},
      body: {
        'model': model,
        'max_completion_tokens': aiMaxOutputTokens * 2,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      },
      timeout: timeout,
      extract: (json) =>
          ((json as Map)['choices'] as List).first['message']['content']
              as String,
    );
  }
}
