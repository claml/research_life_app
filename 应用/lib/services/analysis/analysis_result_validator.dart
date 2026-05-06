import 'dart:convert';

import '../../core/models/app_models.dart';
import 'local_llm_analysis_models.dart';

class AnalysisResultValidator {
  const AnalysisResultValidator();

  LocalLlmAnalysisResult validate(String rawJson) {
    final root = _decodeRoot(rawJson);
    final summary = _requiredString(root, 'summary');
    final rawTasks = _requiredList(root, 'tasks');
    final rawPersons = _requiredList(root, 'persons');
    final warnings = _requiredStringList(root, 'warnings');

    final tasks = <LocalLlmTaskResult>[];
    for (var index = 0; index < rawTasks.length; index++) {
      final task = _mapValue(rawTasks[index], 'tasks[$index]');
      final title = _requiredString(task, 'title').trim();
      if (title.isEmpty) {
        throw AnalysisResultValidationException(
          'tasks[$index].title must not be empty.',
        );
      }
      final timeHint = _nullableString(task, 'timeHint')?.trim();
      tasks.add(
        LocalLlmTaskResult(
          title: title,
          description: _requiredString(task, 'description').trim(),
          category: _itemCategory(_requiredString(task, 'category'), index),
          type: _eventType(_requiredString(task, 'type'), index),
          confidence: _confidence(task, 'confidence', 'tasks[$index]'),
          people: _requiredStringList(task, 'people'),
          timeHint: timeHint == null || timeHint.isEmpty ? null : timeHint,
          evidence: _requiredString(task, 'evidence').trim(),
        ),
      );
    }

    final persons = <LocalLlmPersonResult>[];
    for (var index = 0; index < rawPersons.length; index++) {
      final person = _mapValue(rawPersons[index], 'persons[$index]');
      final name = _requiredString(person, 'name').trim();
      if (name.isEmpty) {
        throw AnalysisResultValidationException(
          'persons[$index].name must not be empty.',
        );
      }
      final relatedTaskIndexes = _requiredIntList(person, 'relatedTaskIndexes');
      for (final taskIndex in relatedTaskIndexes) {
        if (taskIndex < 0 || taskIndex >= tasks.length) {
          throw AnalysisResultValidationException(
            'persons[$index].relatedTaskIndexes contains out-of-range index $taskIndex.',
          );
        }
      }

      persons.add(
        LocalLlmPersonResult(
          name: name,
          role: _personRole(_requiredString(person, 'role'), index),
          aliases: _requiredStringList(person, 'aliases'),
          relationshipNote: _requiredString(person, 'relationshipNote').trim(),
          relatedTaskIndexes: relatedTaskIndexes,
          confidence: _confidence(person, 'confidence', 'persons[$index]'),
        ),
      );
    }

    return LocalLlmAnalysisResult(
      summary: summary.trim(),
      tasks: tasks,
      persons: persons,
      warnings: warnings,
    );
  }

  Map<String, Object?> _decodeRoot(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      throw const AnalysisResultValidationException(
        'Analysis result JSON root must be an object.',
      );
    } on AnalysisResultValidationException {
      rethrow;
    } on FormatException catch (error) {
      throw AnalysisResultValidationException(
        'Analysis result is not valid JSON.',
        cause: error,
      );
    }
  }

  Map<String, Object?> _mapValue(Object? value, String path) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    throw AnalysisResultValidationException('$path must be an object.');
  }

  Object? _requiredValue(Map<String, Object?> json, String key) {
    if (!json.containsKey(key)) {
      throw AnalysisResultValidationException('Missing required field "$key".');
    }
    return json[key];
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = _requiredValue(json, key);
    if (value is String) {
      return value;
    }
    throw AnalysisResultValidationException('Field "$key" must be a string.');
  }

  String? _nullableString(Map<String, Object?> json, String key) {
    final value = _requiredValue(json, key);
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw AnalysisResultValidationException(
      'Field "$key" must be a string or null.',
    );
  }

  List<Object?> _requiredList(Map<String, Object?> json, String key) {
    final value = _requiredValue(json, key);
    if (value is List) {
      return value.cast<Object?>();
    }
    throw AnalysisResultValidationException('Field "$key" must be a list.');
  }

  List<String> _requiredStringList(Map<String, Object?> json, String key) {
    final values = _requiredList(json, key);
    return [
      for (var index = 0; index < values.length; index++)
        if (values[index] is String)
          values[index] as String
        else
          throw AnalysisResultValidationException(
            'Field "$key[$index]" must be a string.',
          ),
    ];
  }

  List<int> _requiredIntList(Map<String, Object?> json, String key) {
    final values = _requiredList(json, key);
    return [
      for (var index = 0; index < values.length; index++)
        if (values[index] is int)
          values[index] as int
        else
          throw AnalysisResultValidationException(
            'Field "$key[$index]" must be an integer.',
          ),
    ];
  }

  double _confidence(Map<String, Object?> json, String key, String path) {
    final value = _requiredValue(json, key);
    if (value is! num) {
      throw AnalysisResultValidationException('$path.$key must be a number.');
    }
    final confidence = value.toDouble();
    if (confidence < 0 || confidence > 1) {
      throw AnalysisResultValidationException(
        '$path.$key must be between 0 and 1.',
      );
    }
    return confidence;
  }

  ItemCategory _itemCategory(String value, int index) {
    for (final category in ItemCategory.values) {
      if (category.name == value) {
        return category;
      }
    }
    throw AnalysisResultValidationException(
      'tasks[$index].category has unknown value "$value".',
    );
  }

  EventType _eventType(String value, int index) {
    for (final type in EventType.values) {
      if (type.name == value) {
        return type;
      }
    }
    throw AnalysisResultValidationException(
      'tasks[$index].type has unknown value "$value".',
    );
  }

  PersonRole _personRole(String value, int index) {
    for (final role in PersonRole.values) {
      if (role.name == value) {
        return role;
      }
    }
    throw AnalysisResultValidationException(
      'persons[$index].role has unknown value "$value".',
    );
  }
}

class AnalysisResultValidationException implements Exception {
  const AnalysisResultValidationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final causeText = cause == null ? '' : ': $cause';
    return '$message$causeText';
  }
}
