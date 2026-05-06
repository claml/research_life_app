import '../../core/models/app_models.dart';

class InstitutionCalendarImportResult {
  const InstitutionCalendarImportResult({
    required this.events,
    required this.summary,
    this.title,
    this.warnings = const [],
  });

  final List<EventItem> events;
  final String summary;
  final String? title;
  final List<String> warnings;
}

class InstitutionCalendarService {
  const InstitutionCalendarService();

  static const String importPrompt = '''
你将从学校/学院/机构的校历、工作安排或放假通知中提取结构化日历信息。

请严格按下面格式输出，除了 TITLE 行和事件行，不要输出任何解释、备注、Markdown 标题、列表符号或代码块围栏：

CALENDAR_IMPORT_V1
TITLE: <机构名称 + 年度说明，可选但建议保留>
<开始日期> | <结束日期> | <事件标题> | <分类> | <类型>
<开始日期> | <结束日期> | <事件标题> | <分类> | <类型>

规则：
1. 日期统一使用 YYYY-MM-DD。
2. 如果是单日事件，开始日期和结束日期写同一天。
3. 分类只能从以下值中选择一个：
study / work / life / health / social / other
4. 类型只能从以下值中选择一个：
plan / record
5. 假期、学期、考试周、选课、注册、答辩、开学、离校等未来安排，默认使用 plan。
6. 不确定的内容不要编造；无法确定日期的内容不要输出。
7. 一行只写一个事件，不要合并多个不连续日期。
8. 不要输出表头“开始日期|结束日期...”这一行。

输出示例：
CALENDAR_IMPORT_V1
TITLE: XX大学 2026 学年校历
2026-02-23 | 2026-03-01 | 寒假 | life | plan
2026-03-02 | 2026-07-10 | 春季学期 | study | plan
2026-04-04 | 2026-04-06 | 清明节放假 | life | plan
2026-06-15 | 2026-06-21 | 期末考试周 | study | plan
''';

  static const String exampleTemplate = '''
CALENDAR_IMPORT_V1
TITLE: XX大学 2026 学年校历
2026-02-23 | 2026-03-01 | 寒假 | life | plan
2026-03-02 | 2026-07-10 | 春季学期 | study | plan
2026-04-04 | 2026-04-06 | 清明节放假 | life | plan
2026-06-15 | 2026-06-21 | 期末考试周 | study | plan
2026-09-01 | 2026-09-01 | 秋季学期开学 | study | plan
''';

  InstitutionCalendarImportResult parse(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('请输入校历文本内容。');
    }

    final normalizedLines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (normalizedLines.isEmpty) {
      throw const FormatException('未读取到有效内容。');
    }

    var index = 0;
    if (normalizedLines.first == 'CALENDAR_IMPORT_V1') {
      index = 1;
    }

    String? title;
    if (index < normalizedLines.length &&
        normalizedLines[index].toUpperCase().startsWith('TITLE:')) {
      title = normalizedLines[index].substring(6).trim();
      index += 1;
    }

    final warnings = <String>[];
    final events = <EventItem>[];

    for (var i = index; i < normalizedLines.length; i++) {
      final line = normalizedLines[i];
      if (line.startsWith('#')) {
        continue;
      }

      final segments = line.split('|').map((part) => part.trim()).toList();
      if (segments.length < 5) {
        warnings.add('第 ${i + 1} 行格式不完整，已跳过。');
        continue;
      }

      final startAt = _parseDate(segments[0], i + 1, '开始日期');
      final endAt = _parseDate(segments[1], i + 1, '结束日期');
      if (endAt.isBefore(startAt)) {
        throw FormatException('第 ${i + 1} 行结束日期早于开始日期。');
      }

      final titleValue = segments[2];
      if (titleValue.isEmpty) {
        throw FormatException('第 ${i + 1} 行事件标题为空。');
      }

      final category = _parseCategory(segments[3], i + 1);
      final type = _parseType(segments[4], i + 1);

      events.add(
        EventItem(
          id: 'calendar_${startAt.millisecondsSinceEpoch}_${events.length}',
          title: titleValue,
          category: category,
          type: type,
          startAt: startAt,
          endAt: endAt,
          origin: EventOrigin.institutionCalendar,
          sourceLabel: title == null || title.isEmpty ? '校历导入' : '校历导入 · $title',
        ),
      );
    }

    if (events.isEmpty) {
      throw const FormatException('没有解析到任何有效校历事件，请检查文本格式。');
    }

    return InstitutionCalendarImportResult(
      events: events,
      title: title,
      warnings: warnings,
      summary: title == null || title.isEmpty
          ? '已导入 ${events.length} 条校历事件。'
          : '已导入 ${events.length} 条校历事件：$title',
    );
  }

  DateTime _parseDate(String raw, int line, String fieldName) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) {
      throw FormatException('第 $line 行$fieldName 格式错误，必须是 YYYY-MM-DD。');
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw FormatException('第 $line 行$fieldName 不是有效日期。');
    }
    return DateTime(year, month, day);
  }

  ItemCategory _parseCategory(String raw, int line) {
    return switch (raw.toLowerCase()) {
      'study' || '学习' => ItemCategory.study,
      'work' || '工作' => ItemCategory.work,
      'life' || '生活' || '假期' || '放假' => ItemCategory.life,
      'health' || '健康' => ItemCategory.health,
      'social' || '社交' => ItemCategory.social,
      'other' || '其他' => ItemCategory.other,
      _ => throw FormatException(
          '第 $line 行分类不支持。请使用 study/work/life/health/social/other。',
        ),
    };
  }

  EventType _parseType(String raw, int line) {
    return switch (raw.toLowerCase()) {
      'plan' || '计划' => EventType.plan,
      'record' || '记录' => EventType.record,
      _ => throw FormatException(
          '第 $line 行类型不支持。请使用 plan 或 record。',
        ),
    };
  }
}
