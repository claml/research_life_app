import '../../core/models/app_models.dart';

class AnalysisService {
  const AnalysisService();

  static final RegExp _roleSuffixNamePattern = RegExp(
    r'(?:^|[和跟与同向及、，。！？\s])([\u4e00-\u9fa5]{1,2}(?:老师|同学|师兄|师姐|学长|学姐))',
  );

  static final RegExp _relationNamePattern = RegExp(
    r'(?:和|跟|与|同|向)([\u4e00-\u9fa5]{1,3}(?:老师|同学|师兄|师姐|学长|学姐|导师|朋友|男朋友|女朋友|恋人|对象)?)(?=一起|讨论|聊天|见面|开会|吃饭|同步|交流|确认|请教|联系|沟通|约|陪伴|散步|跑步|看展|看电影)',
  );

  static final RegExp _standaloneRolePattern = RegExp(
    r'(?:^|[和跟与同向及、，。！？\s])(导师|朋友|老师|同学|男朋友|女朋友|恋人|对象)(?=$|[、，。！？\s]|建议|表示|提醒|说|同步|讨论|聊天|见面|开会|吃饭|交流|确认|请教|联系|沟通|约|陪伴)',
  );

  static const _actionKeywords = <String>[
    '完成',
    '看完',
    '写了',
    '写完',
    '整理',
    '同步',
    '讨论',
    '开会',
    '参加',
    '跑步',
    '见面',
    '聊天',
    '阅读',
    '复习',
    '提交',
    '修改',
    '打扫',
    '采购',
    '做饭',
    '洗衣',
    '看展',
    '看电影',
    '陪伴',
  ];

  static const _planningCueKeywords = <String>[
    '计划',
    '准备',
    '打算',
    '安排',
    '约定',
    '约好',
    '预约',
    '预计',
    '希望',
    '争取',
    '需要',
    '继续',
    '下周',
    '明天',
    '后天',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
    '周末',
  ];

  static const _futureTimeKeywords = <String>[
    '下周一',
    '下周二',
    '下周三',
    '下周四',
    '下周五',
    '下周六',
    '下周日',
    '下周天',
    '下周末',
    '明天',
    '后天',
    '下周',
  ];

  static const _directPlanIntentKeywords = <String>[
    '打算',
    '约定',
    '约好',
    '预约',
    '预计',
    '希望',
    '争取',
    '需要',
  ];

  static final RegExp _planVerbPattern = RegExp(
    r'(?:^|[，。！？；;、\s]|我|我们|自己|还|再|本周|这周|周末|下周|明天|后天)(?:计划|安排|准备)(?=本周|这周|下周|明天|后天|和|跟|与|同|向|在|于|先|继续|完成|提交|修改|整理|复习|阅读|开会|讨论|联系|确认|去|做|跑步|看|参加|推进)',
  );

  static final RegExp _futureAuxiliaryPattern = RegExp(r'将会|将要|将于');

  static final RegExp _wantIntentPattern = RegExp(
    r'(?:^|[，。！？；;、\s]|我|我们|还|也|再)(?:要|得)(?=先|继续|完成|提交|修改|整理|复习|阅读|开会|讨论|联系|确认|去|做|跑步|跑|看|参加|推进|和|跟|与|同|向|把|在)',
  );

  static final RegExp _weekdayPlanIntentPattern = RegExp(
    r'周[一二三四五六日天末](?:上午|中午|下午|晚上)?(?:要|得|计划|准备|打算|安排)(?=先|继续|完成|提交|修改|整理|复习|阅读|开会|讨论|联系|确认|去|做|跑步|跑|看|参加|推进|和|跟|与|同|向|把|在)',
  );

  static const _studyKeywords = <String>[
    '学习',
    '复习',
    '课程',
    '笔记',
    '阅读',
    '文献',
    '考试',
  ];

  static const _workKeywords = <String>[
    '论文',
    '实验',
    '数据',
    '组会',
    '导师',
    '汇报',
    '开会',
    '项目',
    '整理',
  ];

  static const _healthKeywords = <String>[
    '跑步',
    '健身',
    '运动',
    '医院',
    '睡眠',
    '体检',
    '散步',
  ];

  static final RegExp _healthActivityPattern = RegExp(
    r'跑(?:[0-9０-９一二三四五六七八九十两半个\s]+)?(?:公里|千米|km)|五公里|半马|马拉松',
    caseSensitive: false,
  );

  static const _lifeKeywords = <String>[
    '整理房间',
    '打扫',
    '洗衣',
    '做饭',
    '采购',
    '休息',
    '看展',
    '看电影',
  ];

  static const _socialKeywords = <String>[
    '聊天',
    '见面',
    '吃饭',
    '约会',
    '讨论',
    '聚会',
    '陪伴',
  ];

  AnalysisDraft analyze(AnalysisInput input) {
    final sentences = _splitSentences(_normalizeText(input.rawText));
    final tasks = <ExtractedTaskDraft>[];
    final people = <ExtractedPersonDraft>[];
    final personIndexByName = <String, int>{};

    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      if (!_isLikelyTaskSentence(sentence)) {
        continue;
      }

      final extractedNames = _extractPersonNames(sentence);
      tasks.add(
        ExtractedTaskDraft(
          id: 'task_$i',
          content: sentence,
          category: _detectCategory(sentence),
          type: _detectEventType(sentence),
          confidence: extractedNames.isNotEmpty ? 0.92 : 0.78,
          relatedPersonNames: extractedNames,
          timeHint: _extractTimeHint(sentence),
        ),
      );

      for (final person in _extractPeople(extractedNames, sentence, i)) {
        final existingIndex = personIndexByName[person.name];
        if (existingIndex == null) {
          personIndexByName[person.name] = people.length;
          people.add(person);
          continue;
        }

        final existing = people[existingIndex];
        final mergedTaskIndexes = <int>{
          ...existing.relatedTaskIndexes,
          ...person.relatedTaskIndexes,
        }.toList()..sort();

        people[existingIndex] = existing.copyWith(
          aliases: <String>{...existing.aliases, ...person.aliases}.toList(),
          relatedTaskIndexes: mergedTaskIndexes,
        );
      }
    }

    if (tasks.isEmpty && input.rawText.trim().isNotEmpty) {
      final fallback = input.rawText
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .firstWhere(
            (line) => line.isNotEmpty,
            orElse: () => input.rawText.trim(),
          );

      tasks.add(
        ExtractedTaskDraft(
          id: 'task_fallback',
          content: fallback,
          category: ItemCategory.other,
          type: EventType.record,
          confidence: 0.45,
        ),
      );
    }

    final warnings = <String>[];
    if (tasks.isEmpty) {
      warnings.add('没有识别到明确事项，请补充更完整的周描述。');
    }
    if (people.isEmpty) {
      warnings.add('没有识别到人物，可以继续手动补充。');
    }
    if (tasks.every((task) => task.type != EventType.plan)) {
      warnings.add('暂未识别到未来计划候选。');
    }

    return AnalysisDraft(
      id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
      tasks: tasks,
      persons: people,
      summary: _buildSummary(tasks, people),
      warnings: warnings,
      createdAt: DateTime.now(),
    );
  }

  List<String> _splitSentences(String text) {
    return text
        .split(RegExp(r'[。！？!?；;\n\r]+'))
        .map((part) => part.trim())
        .expand((part) => part.split(RegExp(r'[，,]+')))
        .map((part) => part.trim())
        .where((part) => part.length >= 2)
        .toList();
  }

  String _normalizeText(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map(
          (line) => line
              .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '')
              .replaceFirst(RegExp(r'^\s*[-*+]\s*'), '')
              .replaceFirst(RegExp(r'^\s*\d+[.)、]\s*'), '')
              .replaceAll(RegExp(r'[^\S\r\n]+'), ' ')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }

  EventType _detectEventType(String sentence) {
    return _hasFuturePlanCue(sentence) ? EventType.plan : EventType.record;
  }

  ItemCategory _detectCategory(String sentence) {
    if (_hasHealthCue(sentence)) {
      return ItemCategory.health;
    }
    if (_containsAny(sentence, _studyKeywords)) {
      return ItemCategory.study;
    }
    if (_containsAny(sentence, _workKeywords)) {
      return ItemCategory.work;
    }
    if (_containsAny(sentence, _lifeKeywords)) {
      return ItemCategory.life;
    }
    if (_containsAny(sentence, _socialKeywords) ||
        _extractPersonNames(sentence).isNotEmpty) {
      return ItemCategory.social;
    }
    return ItemCategory.other;
  }

  bool _hasHealthCue(String sentence) {
    return _containsAny(sentence, _healthKeywords) ||
        _healthActivityPattern.hasMatch(sentence);
  }

  bool _containsAny(String sentence, List<String> keywords) {
    return keywords.any(sentence.contains);
  }

  bool _isLikelyTaskSentence(String sentence) {
    if (sentence.length < 2) {
      return false;
    }
    if (_containsAny(sentence, _actionKeywords)) {
      return true;
    }
    if (_containsAny(sentence, _planningCueKeywords) ||
        _hasFuturePlanCue(sentence)) {
      return true;
    }
    if (_extractPersonNames(sentence).isNotEmpty) {
      return true;
    }
    return _containsAny(sentence, _studyKeywords) ||
        _containsAny(sentence, _workKeywords) ||
        _hasHealthCue(sentence) ||
        _containsAny(sentence, _lifeKeywords) ||
        _containsAny(sentence, _socialKeywords);
  }

  List<String> _extractPersonNames(String sentence) {
    final found = <String>{};

    for (final match in _roleSuffixNamePattern.allMatches(sentence)) {
      _addPersonCandidate(found, match.group(1));
    }
    for (final match in RegExp(r'(男朋友|女朋友|恋人|对象)').allMatches(sentence)) {
      _addPersonCandidate(found, match.group(1));
    }
    for (final match in _standaloneRolePattern.allMatches(sentence)) {
      _addPersonCandidate(found, match.group(1));
    }
    for (final match in _relationNamePattern.allMatches(sentence)) {
      _addPersonCandidate(found, match.group(1));
    }

    return found.toList();
  }

  bool _hasFuturePlanCue(String sentence) {
    if (_containsAny(sentence, _futureTimeKeywords)) {
      return true;
    }
    if (_containsAny(sentence, _directPlanIntentKeywords)) {
      return true;
    }
    return _planVerbPattern.hasMatch(sentence) ||
        _futureAuxiliaryPattern.hasMatch(sentence) ||
        _wantIntentPattern.hasMatch(sentence) ||
        _weekdayPlanIntentPattern.hasMatch(sentence);
  }

  List<ExtractedPersonDraft> _extractPeople(
    List<String> extractedNames,
    String sentence,
    int taskIndex,
  ) {
    return extractedNames
        .map(
          (name) => ExtractedPersonDraft(
            id: 'person_${name}_$taskIndex',
            name: name,
            role: _detectRole(name, sentence),
            aliases: const [],
            relatedTaskIndexes: [taskIndex],
          ),
        )
        .toList();
  }

  PersonRole _detectRole(String name, String _) {
    if (name.contains('老师') || name.contains('导师')) {
      return PersonRole.teacher;
    }
    if (name.contains('同学') ||
        name.contains('师兄') ||
        name.contains('师姐') ||
        name.contains('学长') ||
        name.contains('学姐')) {
      return PersonRole.classmate;
    }
    if (name.contains('男朋友') ||
        name.contains('女朋友') ||
        name.contains('恋人') ||
        name.contains('对象')) {
      return PersonRole.partner;
    }
    if (name.contains('朋友')) {
      return PersonRole.friend;
    }
    if (name.contains('家人') || name.contains('父母')) {
      return PersonRole.family;
    }
    return PersonRole.other;
  }

  void _addPersonCandidate(Set<String> found, String? rawValue) {
    final value = _normalizePersonCandidate(rawValue);
    if (value != null) {
      found.add(value);
    }
  }

  String? _normalizePersonCandidate(String? rawValue) {
    if (rawValue == null) {
      return null;
    }

    var value = rawValue.trim();
    value = value.replaceAll(RegExp(r'^[和跟与及]+'), '');
    value = value.replaceAll(
      RegExp(r'^(今天|昨天|明天|后天|本周|这周|上周|下周|周[一二三四五六日天末]|上午|中午|下午|晚上|今晚|昨晚)+'),
      '',
    );
    value = value.trim();

    if (value.isEmpty || _looksLikeVerb(value) || _looksLikeTime(value)) {
      return null;
    }
    if (const {'事情', '内容', '问题', '方案', '实验', '知识'}.contains(value)) {
      return null;
    }

    return value;
  }

  String _buildSummary(
    List<ExtractedTaskDraft> tasks,
    List<ExtractedPersonDraft> people,
  ) {
    if (tasks.isEmpty) {
      return '当前描述信息较少，暂时无法总结出稳定的本周进展。';
    }

    final categories = tasks
        .map((task) => _categoryLabel(task.category))
        .toSet()
        .toList();
    final categoryText = categories.isEmpty
        ? ''
        : '，覆盖 ${categories.join('、')}';
    final peopleText = people.isEmpty ? '未识别到明确人物' : '涉及 ${people.length} 位人物';
    return '本次分析共识别出 ${tasks.length} 条事项，$peopleText$categoryText。';
  }

  String _categoryLabel(ItemCategory category) {
    return switch (category) {
      ItemCategory.study => '学习',
      ItemCategory.work => '工作',
      ItemCategory.life => '生活',
      ItemCategory.health => '健康',
      ItemCategory.social => '社交关系',
      ItemCategory.other => '其他',
    };
  }

  String? _extractTimeHint(String sentence) {
    const hints = [
      '下周一',
      '下周二',
      '下周三',
      '下周四',
      '下周五',
      '下周六',
      '下周日',
      '下周天',
      '下周末',
      '明天',
      '后天',
      '下周',
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
      '周天',
      '周末',
      '本周',
      '这周',
    ];

    for (final hint in hints) {
      if (sentence.contains(hint)) {
        return hint;
      }
    }
    return null;
  }

  bool _looksLikeVerb(String value) {
    const verbs = [
      '讨论',
      '同步',
      '安排',
      '准备',
      '完成',
      '提交',
      '阅读',
      '修改',
      '见面',
      '开会',
      '看展',
      '看电影',
    ];
    return verbs.any(value.contains);
  }

  bool _looksLikeTime(String value) {
    const tokens = ['周', '天', '上午', '中午', '下午', '晚上', '今晚', '昨晚'];
    return tokens.any(value.contains);
  }
}
