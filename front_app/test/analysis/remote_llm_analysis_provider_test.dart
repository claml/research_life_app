import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/analysis/remote_llm_analysis_provider.dart';

void main() {
  group('RemoteLlmAnalysisProvider', () {
    test('posts weekly analysis request to Research Life backend', () async {
      final transport = _FakeRemoteLlmTransport(
        postHandler: (path, body) {
          expect(path, '/api/v1/analysis/weekly');
          expect(body['prompt'], '分析这周记录');
          expect(body['format'], {'type': 'object'});
          expect(body['options'], {'temperature': 0});
          return const RemoteLlmTransportResponse(
            response: '{"summary":"ok"}',
            model: 'deepseek-chat',
          );
        },
      );
      final provider = RemoteLlmAnalysisProvider(transport: transport);

      final response = await provider.generateAnalysisJson(
        prompt: '分析这周记录',
        format: {'type': 'object'},
        options: const {'temperature': 0},
      );

      expect(response, '{"summary":"ok"}');
      expect(transport.posts, ['/api/v1/analysis/weekly']);
    });

    test('merges extraBody fields into the request body', () async {
      final transport = _FakeRemoteLlmTransport(
        postHandler: (path, body) {
          expect(body['provider'], 'deepseek');
          expect(body['baseUrl'], 'https://api.deepseek.com');
          expect(body['modelName'], 'deepseek-chat');
          expect(body['apiKey'], 'sk-test');
          return const RemoteLlmTransportResponse(response: '{"summary":"ok"}');
        },
      );
      final provider = RemoteLlmAnalysisProvider(transport: transport);

      await provider.generateAnalysisJson(
        prompt: '分析这周记录',
        format: 'json',
        extraBody: const {
          'provider': 'deepseek',
          'baseUrl': 'https://api.deepseek.com',
          'modelName': 'deepseek-chat',
          'apiKey': 'sk-test',
        },
      );
    });

    test('ignores empty extraBody', () async {
      final transport = _FakeRemoteLlmTransport(
        postHandler: (_, body) {
          expect(body.containsKey('provider'), isFalse);
          return const RemoteLlmTransportResponse(response: '{"summary":"ok"}');
        },
      );
      final provider = RemoteLlmAnalysisProvider(transport: transport);

      await provider.generateAnalysisJson(
        prompt: 'x',
        format: 'json',
        extraBody: const {},
      );
    });

    test('rejects empty response string', () async {
      final provider = RemoteLlmAnalysisProvider(
        transport: _FakeRemoteLlmTransport(
          postHandler: (_, _) =>
              const RemoteLlmTransportResponse(response: '  '),
        ),
      );

      await expectLater(
        () => provider.generateAnalysisJson(prompt: 'x', format: 'json'),
        throwsA(isA<RemoteLlmProviderException>()),
      );
    });

    test('surfaces transport failures', () async {
      final provider = RemoteLlmAnalysisProvider(
        transport: _FakeRemoteLlmTransport(
          postHandler: (_, _) => throw const RemoteLlmProviderException('down'),
        ),
      );

      await expectLater(
        () => provider.generateAnalysisJson(prompt: 'x', format: 'json'),
        throwsA(isA<RemoteLlmProviderException>()),
      );
    });
  });
}

typedef _PostHandler =
    FutureOr<RemoteLlmTransportResponse> Function(
      String path,
      Map<String, Object?> body,
    );

class _FakeRemoteLlmTransport implements RemoteLlmTransport {
  _FakeRemoteLlmTransport({required this.postHandler});

  final _PostHandler postHandler;
  final List<String> posts = [];

  @override
  Future<RemoteLlmTransportResponse> post(
    String path, {
    required Map<String, Object?> body,
    Duration? timeout,
  }) async {
    posts.add(path);
    return postHandler(path, body);
  }
}
