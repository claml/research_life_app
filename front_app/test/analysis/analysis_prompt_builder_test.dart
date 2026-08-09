import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/analysis/analysis_prompt_builder.dart';

void main() {
  const builder = AnalysisPromptBuilder();
  const input = AnalysisInput(
    rawText: '这周和王老师开会。',
    sourceType: AnalysisSourceType.text,
  );

  group('AnalysisPromptBuilder', () {
    test('builds base prompt without history or answers', () {
      final prompt = builder.buildPrompt(input);

      expect(prompt, contains('周记文本：'));
      expect(prompt, contains('这周和王老师开会。'));
      expect(prompt, isNot(contains('历史人物（')));
      expect(prompt, contains('人物澄清要求'));
    });

    test('injects history persons section', () {
      final prompt = builder.buildPrompt(
        input,
        historyPersonText:
            '- 王丽 | 称呼：王老师 | 角色：老师 | 最近出现：2026-07-20',
      );

      expect(prompt, contains('历史人物（仅用于判断周记中人物与历史人物是否为同一人'));
      expect(prompt, contains('王丽'));
      expect(prompt, contains('角色：老师'));
    });

    test('appends clarification answers for second round only', () {
      final prompt = builder.buildPrompt(
        input,
        historyPersonText: '- 王丽 | 角色：老师 | 最近出现：2026-07-20',
        clarificationAnswers: ['问题：王老师是否与历史人物王丽是同一人？\n回答：是'],
      );

      expect(prompt, contains('用户对人物疑问的回答'));
      expect(prompt, contains('问题：王老师是否与历史人物王丽是同一人？'));
      expect(prompt, contains('回答：是'));
      expect(prompt, contains('clarifications 必须输出空数组'));
      expect(prompt, isNot(contains('人物澄清要求')));
    });

    test('schema requires clarifications field with enum types', () {
      final schema = builder.buildJsonSchema();
      final required = (schema['required']! as List).cast<String>();
      final properties = schema['properties']! as Map<String, Object?>;

      expect(required, contains('clarifications'));
      final clarifications =
          properties['clarifications']! as Map<String, Object?>;
      expect(clarifications['type'], 'array');
      final item = clarifications['items']! as Map<String, Object?>;
      final itemProperties = item['properties']! as Map<String, Object?>;
      expect(item['required'], ['type', 'question']);
      expect(itemProperties.containsKey('type'), isTrue);
      expect(itemProperties.containsKey('personIndex'), isTrue);
      expect(itemProperties.containsKey('question'), isTrue);
      expect(itemProperties.containsKey('context'), isTrue);
      expect(itemProperties.containsKey('options'), isTrue);
      expect(itemProperties.containsKey('historyMatch'), isTrue);
    });
  });
}
