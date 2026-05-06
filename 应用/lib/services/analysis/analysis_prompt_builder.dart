import '../../core/models/app_models.dart';

class AnalysisPromptBuilder {
  const AnalysisPromptBuilder();

  String buildPrompt(AnalysisInput input) {
    return '''
你是“研究生活”应用的本地周分析引擎。请分析用户提供的周记文本，抽取事项、人物关系和提醒。

输出要求：
1. 只输出一个合法 JSON 对象。
2. 不要输出 Markdown、代码块、解释文字、前后缀或注释。
3. 所有字段必须遵循提供的 JSON schema。
4. category 只能使用 study/work/life/health/social/other。
5. type 只能使用 record/plan。
6. role 只能使用 teacher/classmate/friend/partner/family/other。
7. confidence 必须是 0 到 1 之间的数字。
8. relatedTaskIndexes 使用 tasks 数组的 0 基下标。
9. 如果信息不确定，把说明放入 warnings，不要虚构。

周记文本：
${input.rawText.trim()}
''';
  }

  Map<String, Object?> buildJsonSchema() {
    return {
      'type': 'object',
      'additionalProperties': false,
      'required': ['summary', 'tasks', 'persons', 'warnings'],
      'properties': {
        'summary': {'type': 'string'},
        'tasks': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'required': [
              'title',
              'description',
              'category',
              'type',
              'confidence',
              'people',
              'timeHint',
              'evidence',
            ],
            'properties': {
              'title': {'type': 'string'},
              'description': {'type': 'string'},
              'category': {
                'type': 'string',
                'enum': ['study', 'work', 'life', 'health', 'social', 'other'],
              },
              'type': {
                'type': 'string',
                'enum': ['record', 'plan'],
              },
              'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
              'people': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'timeHint': {
                'anyOf': [
                  {'type': 'string'},
                  {'type': 'null'},
                ],
              },
              'evidence': {'type': 'string'},
            },
          },
        },
        'persons': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'required': [
              'name',
              'role',
              'aliases',
              'relationshipNote',
              'relatedTaskIndexes',
              'confidence',
            ],
            'properties': {
              'name': {'type': 'string'},
              'role': {
                'type': 'string',
                'enum': [
                  'teacher',
                  'classmate',
                  'friend',
                  'partner',
                  'family',
                  'other',
                ],
              },
              'aliases': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'relationshipNote': {'type': 'string'},
              'relatedTaskIndexes': {
                'type': 'array',
                'items': {'type': 'integer'},
              },
              'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
            },
          },
        },
        'warnings': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    };
  }
}
