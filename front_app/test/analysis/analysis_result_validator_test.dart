import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/analysis/analysis_result_validator.dart';

void main() {
  const validator = AnalysisResultValidator();

  String minimalJson({String? clarifications}) {
    final body = '{"summary":"s","tasks":[],"persons":[],"warnings":[]';
    if (clarifications == null) {
      return '$body}';
    }
    return '$body,"clarifications":$clarifications}';
  }

  group('AnalysisResultValidator clarifications', () {
    test('tolerates missing clarifications field', () {
      final result = validator.validate(minimalJson());

      expect(result.clarifications, isEmpty);
    });

    test('parses valid clarifications', () {
      final json = minimalJson(
        clarifications:
            '[{"type":"identity","personIndex":0,"question":"王老师是历史人物王丽吗？","context":"周三和王老师开会","options":["是","否"],"historyMatch":"王丽"}]',
      );

      final result = validator.validate(json);

      expect(result.clarifications, hasLength(1));
      final item = result.clarifications.single;
      expect(item.type, ClarificationType.identity);
      expect(item.personIndex, 0);
      expect(item.question, contains('王老师'));
      expect(item.context, '周三和王老师开会');
      expect(item.options, ['是', '否']);
      expect(item.historyMatch, '王丽');
    });

    test('parses snake_case types', () {
      final json = minimalJson(
        clarifications:
            '[{"type":"name_ambiguous","question":"q"},{"type":"role_uncertain","question":"q2"},{"type":"task_people","question":"q3"},{"type":"other","question":"q4"}]',
      );

      final result = validator.validate(json);

      expect(result.clarifications, hasLength(4));
      expect(
        result.clarifications.map((item) => item.type).toList(),
        [
          ClarificationType.nameAmbiguous,
          ClarificationType.roleUncertain,
          ClarificationType.taskPeople,
          ClarificationType.other,
        ],
      );
    });

    test('skips invalid items and caps at 5', () {
      final validItems = [
        for (var index = 0; index < 7; index++)
          '{"type":"other","question":"q$index"}',
      ].join(',');
      final json = minimalJson(
        clarifications: '[null, {"type":"bad_type","question":"x"}, $validItems]',
      );

      final result = validator.validate(json);

      expect(result.clarifications, hasLength(5));
    });

    test('treats non-list clarifications as empty', () {
      final json = minimalJson(clarifications: '"oops"');

      final result = validator.validate(json);

      expect(result.clarifications, isEmpty);
    });
  });
}
