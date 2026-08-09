import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';

void main() {
  group('InstitutionCalendarService', () {
    const service = InstitutionCalendarService();

    test('parses valid calendar text with ranges', () {
      const rawText = '''
CALENDAR_IMPORT_V1
TITLE: 测试大学 2026 学年校历
2026-02-23 | 2026-03-01 | 寒假 | life | plan
2026-03-02 | 2026-07-10 | 春季学期 | study | plan
2026-04-04 | 2026-04-06 | 清明节放假 | life | plan
''';

      final result = service.parse(rawText);

      expect(result.title, '测试大学 2026 学年校历');
      expect(result.events, hasLength(3));
      expect(result.events.first.category, ItemCategory.life);
      expect(result.events.first.type, EventType.plan);
      expect(result.events.first.endAt, DateTime(2026, 3, 1));
      expect(result.events[1].sourceLabel, contains('校历导入'));
    });

    test('throws on invalid category', () {
      const rawText = '''
2026-02-23 | 2026-03-01 | 寒假 | vacation | plan
''';

      expect(
        () => service.parse(rawText),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
