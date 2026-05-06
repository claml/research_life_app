import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/analysis/analysis_prompt_builder.dart';
import 'package:research_life/services/analysis/analysis_result_validator.dart';
import 'package:research_life/services/analysis/local_llm_analysis_service.dart';
import 'package:research_life/services/analysis/ollama_client.dart';

void main() {
  group('AnalysisPromptBuilder', () {
    test('asks for JSON only and exposes required schema fields', () {
      const builder = AnalysisPromptBuilder();
      const input = AnalysisInput(
        rawText: '这周完成论文整理。',
        sourceType: AnalysisSourceType.text,
      );

      final prompt = builder.buildPrompt(input);
      final schema = builder.buildJsonSchema();

      expect(prompt, contains('只输出一个合法 JSON 对象'));
      expect(prompt, contains('不要输出 Markdown'));
      expect(schema['required'], containsAll(['summary', 'tasks', 'persons']));
      final properties = schema['properties'] as Map<String, Object?>;
      expect(properties.keys, containsAll(['summary', 'tasks', 'persons']));
    });
  });

  group('AnalysisResultValidator', () {
    const validator = AnalysisResultValidator();

    test('validates legal structured output', () {
      final result = validator.validate(jsonEncode(_validResult()));

      expect(result.summary, '本周推进论文并安排后续会议。');
      expect(result.tasks, hasLength(2));
      expect(result.tasks.first.category, ItemCategory.work);
      expect(result.tasks.first.type, EventType.record);
      expect(result.tasks.first.confidence, 0.92);
      expect(result.tasks.first.people, ['王老师']);
      expect(result.persons.single.name, '王老师');
      expect(result.persons.single.role, PersonRole.teacher);
      expect(result.persons.single.relatedTaskIndexes, [0, 1]);
    });

    test('rejects invalid JSON', () {
      expect(
        () => validator.validate('{not json'),
        throwsA(isA<AnalysisResultValidationException>()),
      );
    });

    test('rejects missing required fields', () {
      final json = _validResult()..remove('tasks');

      expect(
        () => validator.validate(jsonEncode(json)),
        throwsA(
          isA<AnalysisResultValidationException>().having(
            (error) => error.message,
            'message',
            contains('Missing required field "tasks"'),
          ),
        ),
      );
    });

    test('rejects unknown enums', () {
      final json = _validResult();
      (json['tasks'] as List).first['category'] = 'career';

      expect(
        () => validator.validate(jsonEncode(json)),
        throwsA(
          isA<AnalysisResultValidationException>().having(
            (error) => error.message,
            'message',
            contains('unknown value "career"'),
          ),
        ),
      );
    });

    test('rejects out-of-range confidence', () {
      final json = _validResult();
      (json['tasks'] as List).first['confidence'] = 1.2;

      expect(
        () => validator.validate(jsonEncode(json)),
        throwsA(
          isA<AnalysisResultValidationException>().having(
            (error) => error.message,
            'message',
            contains('between 0 and 1'),
          ),
        ),
      );
    });

    test('rejects out-of-range related task indexes', () {
      final json = _validResult();
      (json['persons'] as List).first['relatedTaskIndexes'] = [3];

      expect(
        () => validator.validate(jsonEncode(json)),
        throwsA(
          isA<AnalysisResultValidationException>().having(
            (error) => error.message,
            'message',
            contains('out-of-range index 3'),
          ),
        ),
      );
    });

    test('rejects empty task title', () {
      final json = _validResult();
      (json['tasks'] as List).first['title'] = '  ';

      expect(
        () => validator.validate(jsonEncode(json)),
        throwsA(
          isA<AnalysisResultValidationException>().having(
            (error) => error.message,
            'message',
            contains('title must not be empty'),
          ),
        ),
      );
    });
  });

  group('LocalLlmAnalysisService', () {
    test(
      'calls Ollama with schema and converts result to AnalysisDraft',
      () async {
        final transport = _FakeOllamaTransport(
          postHandler: (uri, body) {
            expect(uri.path, '/api/generate');
            expect(body['model'], 'qwen2.5:7b');
            expect(body['stream'], false);
            expect(body['prompt'], contains('不要输出 Markdown'));
            expect(body['format'], isA<Map<String, Object?>>());
            expect(body['options'], {'temperature': 0.1});
            return OllamaTransportResponse(
              statusCode: 200,
              body: jsonEncode({
                'model': 'qwen2.5:7b',
                'response': jsonEncode(_validResult()),
                'done': true,
              }),
            );
          },
        );
        final service = LocalLlmAnalysisService(
          client: OllamaClient(transport: transport),
          model: 'qwen2.5:7b',
          options: const {'temperature': 0.1},
        );

        final draft = await service.analyze(
          const AnalysisInput(
            rawText: '这周和王老师讨论论文，下周二继续开会。',
            sourceType: AnalysisSourceType.text,
          ),
        );

        expect(draft.summary, '本周推进论文并安排后续会议。');
        expect(draft.tasks, hasLength(2));
        expect(draft.tasks.first.id, 'llm_task_0');
        expect(draft.tasks.first.content, '和王老师讨论论文');
        expect(draft.tasks.first.category, ItemCategory.work);
        expect(draft.tasks.first.relatedPersonNames, ['王老师']);
        expect(draft.persons.single.id, 'llm_person_0');
        expect(draft.persons.single.name, '王老师');
        expect(draft.persons.single.relatedTaskIndexes, [0, 1]);
        expect(draft.warnings, isEmpty);
      },
    );

    test('surfaces validation exceptions from invalid model output', () async {
      final service = LocalLlmAnalysisService(
        client: OllamaClient(
          transport: _FakeOllamaTransport(
            postHandler: (_, _) => const OllamaTransportResponse(
              statusCode: 200,
              body: '{"response":"not json","done":true}',
            ),
          ),
        ),
        model: 'qwen2.5:7b',
      );

      expect(
        () => service.analyze(
          const AnalysisInput(
            rawText: '这周完成论文整理。',
            sourceType: AnalysisSourceType.text,
          ),
        ),
        throwsA(isA<AnalysisResultValidationException>()),
      );
    });
  });
}

Map<String, Object?> _validResult() {
  return {
    'summary': '本周推进论文并安排后续会议。',
    'tasks': [
      {
        'title': '和王老师讨论论文',
        'description': '围绕论文进展和后续修改方向进行了讨论。',
        'category': 'work',
        'type': 'record',
        'confidence': 0.92,
        'people': ['王老师'],
        'timeHint': '这周',
        'evidence': '这周和王老师讨论论文',
      },
      {
        'title': '下周二继续开会',
        'description': '计划下周二继续和王老师开会推进论文。',
        'category': 'work',
        'type': 'plan',
        'confidence': 0.86,
        'people': ['王老师'],
        'timeHint': '下周二',
        'evidence': '下周二继续开会',
      },
    ],
    'persons': [
      {
        'name': '王老师',
        'role': 'teacher',
        'aliases': ['导师'],
        'relationshipNote': '论文协作对象',
        'relatedTaskIndexes': [0, 1],
        'confidence': 0.9,
      },
    ],
    'warnings': <String>[],
  };
}

typedef _PostHandler =
    FutureOr<OllamaTransportResponse> Function(
      Uri uri,
      Map<String, Object?> body,
    );

class _FakeOllamaTransport implements OllamaTransport {
  _FakeOllamaTransport({required this.postHandler});

  final _PostHandler postHandler;

  @override
  Future<OllamaTransportResponse> get(Uri uri, {required Duration timeout}) {
    throw StateError('Unexpected GET $uri');
  }

  @override
  Future<OllamaTransportResponse> post(
    Uri uri, {
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    return postHandler(uri, body);
  }

  @override
  void close({bool force = false}) {}
}
