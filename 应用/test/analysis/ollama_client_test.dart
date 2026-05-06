import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/analysis/ollama_client.dart';

void main() {
  group('OllamaClient', () {
    test('generate posts non-streaming request and parses response', () async {
      final transport = _FakeOllamaTransport(
        postHandler: (uri, body) {
          expect(uri.path, '/api/generate');
          expect(body['model'], 'qwen2.5:7b');
          expect(body['prompt'], '整理这周记录');
          expect(body['stream'], false);
          expect(body['format'], {
            'type': 'object',
            'properties': {
              'summary': {'type': 'string'},
            },
          });
          expect(body['options'], {'temperature': 0.2, 'num_ctx': 4096});
          return OllamaTransportResponse(
            statusCode: 200,
            body: jsonEncode({
              'model': 'qwen2.5:7b',
              'created_at': '2026-05-04T05:30:00Z',
              'response': '{"summary":"ok"}',
              'done': true,
              'done_reason': 'stop',
            }),
          );
        },
      );
      final client = OllamaClient(transport: transport);

      final response = await client.generate(
        model: 'qwen2.5:7b',
        prompt: '整理这周记录',
        format: {
          'type': 'object',
          'properties': {
            'summary': {'type': 'string'},
          },
        },
        options: {'temperature': 0.2, 'num_ctx': 4096},
      );

      expect(response.model, 'qwen2.5:7b');
      expect(response.response, '{"summary":"ok"}');
      expect(response.done, true);
      expect(response.doneReason, 'stop');
      expect(response.createdAt, DateTime.parse('2026-05-04T05:30:00Z'));
      expect(transport.posts, hasLength(1));
    });

    test('listModels parses /api/tags and checkHealth succeeds', () async {
      final transport = _FakeOllamaTransport(
        getHandler: (uri) {
          expect(uri.path, '/api/tags');
          return OllamaTransportResponse(
            statusCode: 200,
            body: jsonEncode({
              'models': [
                {
                  'name': 'qwen2.5:7b',
                  'model': 'qwen2.5:7b',
                  'modified_at': '2026-05-04T05:00:00Z',
                  'size': 123,
                  'digest': 'abc',
                  'details': {'family': 'qwen2'},
                },
              ],
            }),
          );
        },
      );
      final client = OllamaClient(transport: transport);

      final models = await client.listModels();
      final healthy = await client.checkHealth();

      expect(models, hasLength(1));
      expect(models.single.name, 'qwen2.5:7b');
      expect(models.single.size, 123);
      expect(models.single.details, {'family': 'qwen2'});
      expect(healthy, true);
      expect(transport.gets, hasLength(2));
    });

    test('throws connection exception for socket failures', () async {
      final client = OllamaClient(
        transport: _FakeOllamaTransport(
          getHandler: (_) => throw const SocketException('refused'),
        ),
      );

      expect(client.listModels, throwsA(isA<OllamaConnectionException>()));
    });

    test('throws timeout exception for slow requests', () async {
      final client = OllamaClient(
        transport: _FakeOllamaTransport(
          getHandler: (_) => throw TimeoutException('slow'),
        ),
      );

      expect(client.listModels, throwsA(isA<OllamaTimeoutException>()));
    });

    test('throws status exception for non-2xx responses', () async {
      final client = OllamaClient(
        transport: _FakeOllamaTransport(
          getHandler: (_) => const OllamaTransportResponse(
            statusCode: 500,
            body: '{"error":"boom"}',
          ),
        ),
      );

      await expectLater(
        client.listModels(),
        throwsA(
          isA<OllamaHttpStatusException>()
              .having((error) => error.statusCode, 'statusCode', 500)
              .having(
                (error) => error.responseBody,
                'responseBody',
                contains('boom'),
              ),
        ),
      );
    });

    test('throws invalid json exception for malformed responses', () async {
      final client = OllamaClient(
        transport: _FakeOllamaTransport(
          getHandler: (_) =>
              const OllamaTransportResponse(statusCode: 200, body: 'not json'),
        ),
      );

      expect(client.listModels, throwsA(isA<OllamaInvalidJsonException>()));
    });

    test(
      'throws invalid json exception for unexpected response shape',
      () async {
        final client = OllamaClient(
          transport: _FakeOllamaTransport(
            postHandler: (_, _) => const OllamaTransportResponse(
              statusCode: 200,
              body: '{"done":true}',
            ),
          ),
        );

        expect(
          () => client.generate(model: 'qwen2.5:7b', prompt: 'hello'),
          throwsA(isA<OllamaInvalidJsonException>()),
        );
      },
    );
  });
}

typedef _GetHandler = FutureOr<OllamaTransportResponse> Function(Uri uri);
typedef _PostHandler =
    FutureOr<OllamaTransportResponse> Function(
      Uri uri,
      Map<String, Object?> body,
    );

class _FakeOllamaTransport implements OllamaTransport {
  _FakeOllamaTransport({this.getHandler, this.postHandler});

  final _GetHandler? getHandler;
  final _PostHandler? postHandler;
  final List<Uri> gets = [];
  final List<_FakePost> posts = [];

  @override
  Future<OllamaTransportResponse> get(
    Uri uri, {
    required Duration timeout,
  }) async {
    gets.add(uri);
    final handler = getHandler;
    if (handler == null) {
      throw StateError('Unexpected GET $uri');
    }
    return handler(uri);
  }

  @override
  Future<OllamaTransportResponse> post(
    Uri uri, {
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    posts.add(_FakePost(uri, body));
    final handler = postHandler;
    if (handler == null) {
      throw StateError('Unexpected POST $uri');
    }
    return handler(uri, body);
  }

  @override
  void close({bool force = false}) {}
}

class _FakePost {
  const _FakePost(this.uri, this.body);

  final Uri uri;
  final Map<String, Object?> body;
}
