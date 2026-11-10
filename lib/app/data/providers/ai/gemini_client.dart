import 'package:http/http.dart' as http;

import '../ai_client.dart';

class GeminiClient implements AiClient {
  GeminiClient({required this.apiKey, String? model, required this.httpClient})
    : model = model ?? defaultModel;

  // Source: https://aistudio.google.com/docs/models (ai.google.dev redirects here)
  static const defaultModel = 'gemini-3.5-flash-lite';

  final String apiKey;
  final String model;
  final http.Client httpClient;

  @override
  Future<String> complete(String prompt, {required Duration timeout}) {
    return postForText(
      httpClient,
      Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
      ),
      headers: {'x-goog-api-key': apiKey},
      body: {
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0,
          'maxOutputTokens': aiMaxOutputTokens,
        },
      },
      timeout: timeout,
      extract: (json) {
        final parts =
            ((json as Map)['candidates'] as List).first['content']['parts']
                as List;
        return parts.map((p) => (p as Map)['text'] as String? ?? '').join();
      },
    );
  }
}
