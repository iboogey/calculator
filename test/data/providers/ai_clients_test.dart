import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calculator/app/data/models/app_settings.dart';
import 'package:calculator/app/data/providers/ai/claude_client.dart';
import 'package:calculator/app/data/providers/ai/gemini_client.dart';
import 'package:calculator/app/data/providers/ai/openai_client.dart';
import 'package:calculator/app/data/providers/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _key = 'SECRET-KEY-123';
const _t = Duration(seconds: 2);

class _Case {
  _Case(this.kind, this.defaultModel, this.url, this.authHeader, this.authValue,
      this.okBody, this.modelInUrl);
  final AiProviderKind kind;
  final String defaultModel;
  final String url; // with {model}
  final String authHeader;
  final String authValue;
  final Map<String, Object?> okBody;
  final bool modelInUrl;
}

final _cases = [
  _Case(
    AiProviderKind.gemini,
    GeminiClient.defaultModel,
    'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent',
    'x-goog-api-key',
    _key,
    {
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': 'hello'},
            ],
          },
        },
      ],
    },
    true,
  ),
  _Case(
    AiProviderKind.claude,
    ClaudeClient.defaultModel,
    'https://api.anthropic.com/v1/messages',
    'x-api-key',
    _key,
    {
      'content': [
        {'type': 'text', 'text': 'hello'},
      ],
    },
    false,
  ),
  _Case(
    AiProviderKind.openai,
    OpenAiClient.defaultModel,
    'https://api.openai.com/v1/chat/completions',
    'authorization',
    'Bearer $_key',
    {
      'choices': [
        {
          'message': {'content': 'hello'},
        },
      ],
    },
    false,
  ),
];

AiClient _make(_Case c, MockClient mock, {String? model}) =>
    createAiClient(c.kind, apiKey: _key, model: model, httpClient: mock);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  for (final c in _cases) {
    group(c.kind.name, () {
      test('request shape, default model, reply extraction', () async {
        late http.Request req;
        final mock = MockClient((r) async {
          req = r;
          return _json(c.okBody);
        });
        final out = await _make(c, mock).complete('PROMPT-ص', timeout: _t);
        expect(out, 'hello');
        expect(req.method, 'POST');
        expect(
          req.url.toString(),
          c.url.replaceAll('{model}', c.defaultModel),
        );
        expect(req.headers[c.authHeader], c.authValue);
        expect(req.url.query, isEmpty);
        expect(req.url.toString(), isNot(contains(_key)));
        final body = utf8.decode(req.bodyBytes);
        expect(body, contains('PROMPT-ص'));
        if (!c.modelInUrl) expect(body, contains(c.defaultModel));
      });

      test('model override is used', () async {
        late http.Request req;
        final mock = MockClient((r) async {
          req = r;
          return _json(c.okBody);
        });
        await _make(c, mock, model: 'my-model').complete('p', timeout: _t);
        if (c.modelInUrl) {
          expect(req.url.toString(), c.url.replaceAll('{model}', 'my-model'));
        } else {
          expect(jsonDecode(req.body)['model'], 'my-model');
        }
      });

      test('401 and 403 give the invalid-key message', () async {
        for (final status in [401, 403]) {
          final mock = MockClient((_) async => _json({'error': 'x'}, status));
          await expectLater(
            _make(c, mock).complete('p', timeout: _t),
            throwsA(
              isA<AiException>().having(
                (e) => e.message,
                'message',
                aiInvalidKeyMessage,
              ),
            ),
          );
        }
      });

      test('500 gives the generic message without body or key', () async {
        final mock = MockClient((_) async => http.Response('boom $_key', 500));
        try {
          await _make(c, mock).complete('p', timeout: _t);
          fail('should throw');
        } on AiException catch (e) {
          expect(e.message, aiGenericMessage);
          expect(e.message, isNot(contains(_key)));
        }
      });

      test('no answer within timeout gives the timeout message', () async {
        final mock = MockClient((_) => Completer<http.Response>().future);
        await expectLater(
          _make(c, mock).complete(
            'p',
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(
            isA<AiException>().having(
              (e) => e.message,
              'message',
              aiTimeoutMessage,
            ),
          ),
        );
      });

      test('unexpected 200 body gives the generic message', () async {
        final mock = MockClient((_) async => _json({'unexpected': true}));
        await expectLater(
          _make(c, mock).complete('p', timeout: _t),
          throwsA(
            isA<AiException>().having(
              (e) => e.message,
              'message',
              aiGenericMessage,
            ),
          ),
        );
      });

      test('non-JSON 200 body gives the generic message', () async {
        final mock = MockClient((_) async => http.Response('<html>', 200));
        await expectLater(
          _make(c, mock).complete('p', timeout: _t),
          throwsA(isA<AiException>()),
        );
      });

      test('socket and client exceptions map to AiException', () async {
        for (final err in <Exception>[
          const SocketException('down'),
          http.ClientException('down'),
        ]) {
          final mock = MockClient((_) async => throw err);
          await expectLater(
            _make(c, mock).complete('p', timeout: _t),
            throwsA(
              isA<AiException>().having(
                (e) => e.message,
                'message',
                aiGenericMessage,
              ),
            ),
          );
        }
      });
    });
  }

  test('Claude sends anthropic-version and max_tokens 512', () async {
    late http.Request req;
    final mock = MockClient((r) async {
      req = r;
      return _json(_cases[1].okBody);
    });
    await _make(_cases[1], mock).complete('p', timeout: _t);
    expect(req.headers['anthropic-version'], '2023-06-01');
    expect(jsonDecode(req.body)['max_tokens'], 512);
  });

  test('createAiClient throws on none', () {
    expect(
      () => createAiClient(AiProviderKind.none, apiKey: 'k'),
      throwsArgumentError,
    );
  });
}
