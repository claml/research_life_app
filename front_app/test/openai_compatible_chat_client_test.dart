import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/agent/agent_models.dart';
import 'package:research_life/services/agent/ai_profile.dart';
import 'package:research_life/services/agent/openai_compatible_chat_client.dart';

void main() {
  group('OpenAiCompatibleChatClient', () {
    test('constructing the client does not contact the provider', () async {
      final server = await _RecordingServer.start();
      addTearDown(server.close);

      OpenAiCompatibleChatClient();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(server.requestCount, 0);
    });

    test(
      'posts only the model and ordered messages with bearer auth',
      () async {
        final server = await _RecordingServer.start();
        addTearDown(server.close);

        final completion = await OpenAiCompatibleChatClient().complete(
          profile: _profile(server.baseUrl, model: 'model-a'),
          messages: const [
            AiChatTurn(role: 'system', content: '保持简洁'),
            AiChatTurn(role: 'user', content: '问题'),
          ],
          credential: ' test-key ',
        );
        final request = await server.nextRequest;

        expect(request.path, '/v1/chat/completions');
        expect(request.authorization, 'Bearer test-key');
        expect(request.jsonBody.keys, unorderedEquals(['model', 'messages']));
        expect(request.jsonBody['model'], 'model-a');
        expect(request.jsonBody['messages'], [
          {'role': 'system', 'content': '保持简洁'},
          {'role': 'user', 'content': '问题'},
        ]);
        expect(completion.content, '回答');
      },
    );

    test('does not duplicate v1 in a base URL ending in v1', () async {
      final server = await _RecordingServer.start();
      addTearDown(server.close);

      await OpenAiCompatibleChatClient().complete(
        profile: _profile('${server.baseUrl}/v1/'),
        messages: const [AiChatTurn(role: 'user', content: 'hello')],
        credential: 'key',
      );

      expect((await server.nextRequest).path, '/v1/chat/completions');
    });

    test('uses a full chat completions URL exactly once', () async {
      final server = await _RecordingServer.start();
      addTearDown(server.close);

      await OpenAiCompatibleChatClient().complete(
        profile: _profile('${server.baseUrl}/custom/chat/completions/'),
        messages: const [AiChatTurn(role: 'user', content: 'hello')],
        credential: 'key',
      );

      expect((await server.nextRequest).path, '/custom/chat/completions');
    });

    test('appends chat completions to an explicit custom path', () async {
      final server = await _RecordingServer.start();
      addTearDown(server.close);

      await OpenAiCompatibleChatClient().complete(
        profile: _profile('${server.baseUrl}/api/paas/v4'),
        messages: const [AiChatTurn(role: 'user', content: 'hello')],
        credential: 'key',
      );

      expect((await server.nextRequest).path, '/api/paas/v4/chat/completions');
    });

    test('ollama sends no authorization header when key is absent', () async {
      final server = await _RecordingServer.start();
      addTearDown(server.close);

      await OpenAiCompatibleChatClient().complete(
        profile: _profile(
          '${server.baseUrl}/v1',
          provider: 'ollama',
          requiresCredential: false,
        ),
        messages: const [AiChatTurn(role: 'user', content: 'hello')],
        credential: null,
      );

      expect((await server.nextRequest).authorization, isNull);
    });

    test('a blank credential does not add authorization', () async {
      final server = await _RecordingServer.start();
      addTearDown(server.close);

      await OpenAiCompatibleChatClient().complete(
        profile: _profile(server.baseUrl),
        messages: const [AiChatTurn(role: 'user', content: 'hello')],
        credential: '  ',
      );

      expect((await server.nextRequest).authorization, isNull);
    });

    test('parses content reasoning model and finish reason', () async {
      final server = await _RecordingServer.start(
        responseBody: {
          'model': 'returned-model',
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '最终回答',
                'reasoning_content': '推理过程',
              },
              'finish_reason': 'stop',
            },
          ],
        },
      );
      addTearDown(server.close);

      final completion = await OpenAiCompatibleChatClient().complete(
        profile: _profile(server.baseUrl),
        messages: const [AiChatTurn(role: 'user', content: '问题')],
        credential: 'key',
      );

      expect(completion.content, '最终回答');
      expect(completion.reasoningContent, '推理过程');
      expect(completion.model, 'returned-model');
      expect(completion.finishReason, 'stop');
    });

    test('empty choices is an invalid response', () async {
      final server = await _RecordingServer.start(
        responseBody: {'model': 'model-a', 'choices': <Object?>[]},
      );
      addTearDown(server.close);

      await _expectKind(
        () => OpenAiCompatibleChatClient().complete(
          profile: _profile(server.baseUrl),
          messages: const [AiChatTurn(role: 'user', content: '问题')],
          credential: 'key',
        ),
        AiChatClientExceptionKind.invalidResponse,
      );
    });

    for (final content in <Object?>[null, '']) {
      test(
        'missing or empty content ($content) is an invalid response',
        () async {
          final server = await _RecordingServer.start(
            responseBody: {
              'model': 'model-a',
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': content},
                  'finish_reason': 'stop',
                },
              ],
            },
          );
          addTearDown(server.close);

          await _expectKind(
            () => OpenAiCompatibleChatClient().complete(
              profile: _profile(server.baseUrl),
              messages: const [AiChatTurn(role: 'user', content: '问题')],
              credential: 'key',
            ),
            AiChatClientExceptionKind.invalidResponse,
          );
        },
      );
    }

    for (final status in [HttpStatus.unauthorized, HttpStatus.forbidden]) {
      test('$status maps to authentication without leaking data', () async {
        await _expectHttpError(
          status: status,
          expectedKind: AiChatClientExceptionKind.authentication,
        );
      });
    }

    test('429 maps to rate limited without leaking data', () async {
      await _expectHttpError(
        status: HttpStatus.tooManyRequests,
        expectedKind: AiChatClientExceptionKind.rateLimited,
      );
    });

    for (final status in [
      HttpStatus.internalServerError,
      HttpStatus.badGateway,
      HttpStatus.serviceUnavailable,
    ]) {
      test('$status maps to server without leaking data', () async {
        await _expectHttpError(
          status: status,
          expectedKind: AiChatClientExceptionKind.server,
        );
      });
    }

    test('an unreachable endpoint maps to unreachable', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(force: true);

      await _expectKind(
        () =>
            OpenAiCompatibleChatClient(
              connectTimeout: const Duration(milliseconds: 300),
            ).complete(
              profile: _profile('http://127.0.0.1:$port'),
              messages: const [
                AiChatTurn(role: 'user', content: 'private-user'),
              ],
              credential: 'private-key',
            ),
        AiChatClientExceptionKind.unreachable,
      );
    });

    test('a receive timeout maps to timeout', () async {
      final server = await _RecordingServer.start(
        responseDelay: const Duration(milliseconds: 200),
      );
      addTearDown(server.close);

      await _expectKind(
        () =>
            OpenAiCompatibleChatClient(
              receiveTimeout: const Duration(milliseconds: 30),
            ).complete(
              profile: _profile(server.baseUrl),
              messages: const [
                AiChatTurn(role: 'user', content: 'private-user'),
              ],
              credential: 'private-key',
            ),
        AiChatClientExceptionKind.timeout,
      );
    });

    test(
      'a send timeout maps to timeout',
      () async {
        final server = await _RecordingServer.start(readRequestBody: false);
        addTearDown(server.close);
        final largeContent = List<String>.filled(24 * 1024 * 1024, 'x').join();

        await _expectKind(
          () =>
              OpenAiCompatibleChatClient(
                sendTimeout: const Duration(milliseconds: 20),
                receiveTimeout: const Duration(seconds: 2),
              ).complete(
                profile: _profile(server.baseUrl),
                messages: [AiChatTurn(role: 'user', content: largeContent)],
                credential: 'private-key',
              ),
          AiChatClientExceptionKind.timeout,
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('Dio cancellation maps to cancelled', () async {
      final releaseResponse = Completer<void>();
      final server = await _RecordingServer.start(
        beforeResponse: () => releaseResponse.future,
      );
      addTearDown(() async {
        if (!releaseResponse.isCompleted) releaseResponse.complete();
        await server.close();
      });
      final token = CancelToken();
      final request = OpenAiCompatibleChatClient().complete(
        profile: _profile(server.baseUrl),
        messages: const [AiChatTurn(role: 'user', content: 'private-user')],
        credential: 'private-key',
        cancelToken: token,
      );
      await server.nextRequest;

      token.cancel('private-cancel-reason');

      await _expectKind(() => request, AiChatClientExceptionKind.cancelled);
    });

    test('relative and non-http base URLs are invalid responses', () async {
      for (final url in ['localhost:11434/v1', 'ftp://localhost/v1']) {
        await _expectKind(
          () => OpenAiCompatibleChatClient().complete(
            profile: _profile(url),
            messages: const [AiChatTurn(role: 'user', content: 'private-user')],
            credential: 'private-key',
          ),
          AiChatClientExceptionKind.invalidResponse,
        );
      }
    });
  });
}

AiProviderProfile _profile(
  String baseUrl, {
  String provider = 'custom',
  String model = 'model-a',
  bool requiresCredential = true,
}) {
  return AiProviderProfile(
    id: 'profile-a',
    provider: provider,
    displayName: 'Test provider',
    baseUrl: baseUrl,
    model: model,
    requiresCredential: requiresCredential,
  );
}

Future<void> _expectHttpError({
  required int status,
  required AiChatClientExceptionKind expectedKind,
}) async {
  const responseSecret = 'private-response-body';
  const credential = 'private-key';
  const userContent = 'private-user-message';
  final server = await _RecordingServer.start(
    statusCode: status,
    rawResponseBody: responseSecret,
  );
  try {
    final error = await _captureError(
      () => OpenAiCompatibleChatClient().complete(
        profile: _profile(server.baseUrl),
        messages: const [AiChatTurn(role: 'user', content: userContent)],
        credential: credential,
      ),
    );

    expect(error.kind, expectedKind);
    expect(error.message, isNotEmpty);
    expect(error.message, contains(RegExp(r'[\u4e00-\u9fff]')));
    for (final secret in [responseSecret, credential, userContent, 'Bearer']) {
      expect(error.message, isNot(contains(secret)));
      expect(error.toString(), isNot(contains(secret)));
    }
  } finally {
    await server.close();
  }
}

Future<void> _expectKind(
  Future<AiChatCompletion> Function() action,
  AiChatClientExceptionKind expectedKind,
) async {
  final error = await _captureError(action);
  expect(error.kind, expectedKind);
  expect(error.message, isNotEmpty);
  expect(error.message, contains(RegExp(r'[\u4e00-\u9fff]')));
  for (final secret in [
    'private-key',
    'private-user',
    'private-cancel-reason',
    'Authorization',
    'Bearer',
  ]) {
    expect(error.message, isNot(contains(secret)));
    expect(error.toString(), isNot(contains(secret)));
  }
}

Future<AiChatClientException> _captureError(
  Future<AiChatCompletion> Function() action,
) async {
  try {
    await action();
    fail('Expected AiChatClientException');
  } on AiChatClientException catch (error) {
    return error;
  }
}

final class _RecordedRequest {
  const _RecordedRequest({
    required this.path,
    required this.authorization,
    required this.jsonBody,
  });

  final String path;
  final String? authorization;
  final Map<String, Object?> jsonBody;
}

final class _RecordingServer {
  _RecordingServer._({
    required HttpServer server,
    required this.responseBody,
    required this.rawResponseBody,
    required this.statusCode,
    required this.responseDelay,
    required this.beforeResponse,
    required this.readRequestBody,
  }) : _server = server;

  final HttpServer _server;
  final Map<String, Object?> responseBody;
  final String? rawResponseBody;
  final int statusCode;
  final Duration? responseDelay;
  final Future<void> Function()? beforeResponse;
  final bool readRequestBody;
  final Completer<_RecordedRequest> _nextRequest =
      Completer<_RecordedRequest>();
  int requestCount = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';
  Future<_RecordedRequest> get nextRequest => _nextRequest.future;

  static Future<_RecordingServer> start({
    Map<String, Object?> responseBody = const {
      'model': 'model-a',
      'choices': [
        {
          'message': {'role': 'assistant', 'content': '回答'},
          'finish_reason': 'stop',
        },
      ],
    },
    String? rawResponseBody,
    int statusCode = HttpStatus.ok,
    Duration? responseDelay,
    Future<void> Function()? beforeResponse,
    bool readRequestBody = true,
  }) async {
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final recorder = _RecordingServer._(
      server: httpServer,
      responseBody: responseBody,
      rawResponseBody: rawResponseBody,
      statusCode: statusCode,
      responseDelay: responseDelay,
      beforeResponse: beforeResponse,
      readRequestBody: readRequestBody,
    );
    httpServer.listen(recorder._handle);
    return recorder;
  }

  Future<void> _handle(HttpRequest request) async {
    requestCount += 1;
    if (!readRequestBody) return;
    final rawBody = await utf8.decoder.bind(request).join();
    final decoded = jsonDecode(rawBody);
    if (!_nextRequest.isCompleted) {
      _nextRequest.complete(
        _RecordedRequest(
          path: request.uri.path,
          authorization: request.headers.value(HttpHeaders.authorizationHeader),
          jsonBody: Map<String, Object?>.from(decoded as Map),
        ),
      );
    }
    if (responseDelay case final delay?) await Future<void>.delayed(delay);
    if (beforeResponse case final wait?) await wait();
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(rawResponseBody ?? jsonEncode(responseBody));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
