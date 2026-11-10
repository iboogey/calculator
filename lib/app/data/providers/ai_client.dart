import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';
import 'ai/claude_client.dart';
import 'ai/gemini_client.dart';
import 'ai/openai_client.dart';

/// A user-facing failure from an AI provider (message is Arabic).
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => 'AiException: $message';
}

const aiInvalidKeyMessage = 'مفتاح API غير صالح';
const aiTimeoutMessage = 'انتهت مهلة الاتصال بمزوّد الذكاء الاصطناعي';
const aiGenericMessage = 'تعذّر الاتصال بمزوّد الذكاء الاصطناعي';

/// Small output cap shared by all providers; answers are short JSON.
const aiMaxOutputTokens = 512;

abstract class AiClient {
  /// Sends [prompt] as one user message and returns the model's text.
  /// Throws [AiException] on HTTP error, timeout or unexpected response.
  Future<String> complete(String prompt, {required Duration timeout});
}

AiClient createAiClient(
  AiProviderKind kind, {
  required String apiKey,
  String? model,
  http.Client? httpClient,
}) {
  final client = httpClient ?? http.Client();
  switch (kind) {
    case AiProviderKind.gemini:
      return GeminiClient(apiKey: apiKey, model: model, httpClient: client);
    case AiProviderKind.claude:
      return ClaudeClient(apiKey: apiKey, model: model, httpClient: client);
    case AiProviderKind.openai:
      return OpenAiClient(apiKey: apiKey, model: model, httpClient: client);
    case AiProviderKind.none:
      throw ArgumentError('No AI provider selected');
  }
}

/// Shared POST + error mapping for the provider clients. [extract] pulls the
/// reply text from the decoded JSON and may throw on an unexpected shape.
Future<String> postForText(
  http.Client client,
  Uri url, {
  required Map<String, String> headers,
  required Map<String, Object?> body,
  required Duration timeout,
  required String Function(Object? json) extract,
}) async {
  try {
    final response = await client
        .post(
          url,
          headers: {'content-type': 'application/json', ...headers},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AiException(aiInvalidKeyMessage);
    }
    if (response.statusCode != 200) {
      throw const AiException(aiGenericMessage);
    }
    final text = extract(jsonDecode(utf8.decode(response.bodyBytes)));
    if (text.trim().isEmpty) throw const AiException(aiGenericMessage);
    return text;
  } on AiException {
    rethrow;
  } on TimeoutException {
    throw const AiException(aiTimeoutMessage);
  } on SocketException {
    throw const AiException(aiGenericMessage);
  } on http.ClientException {
    throw const AiException(aiGenericMessage);
  } catch (_) {
    // Unexpected response shape (cast/format/state errors).
    throw const AiException(aiGenericMessage);
  }
}
