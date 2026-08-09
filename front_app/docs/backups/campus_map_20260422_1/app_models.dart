enum ItemCategory { study, work, life, health, social, other }

extension ItemCategoryLabel on ItemCategory {
  String get label => switch (this) {
        ItemCategory.study => '学习',
        ItemCategory.work => '工作',
        ItemCategory.life => '生活',
        ItemCategory.health => '健康',
        ItemCategory.social => '社交关系',
        ItemCategory.other => '其他',
      };
}

enum PersonRole { teacher, classmate, friend, partner, family, other }

extension PersonRoleLabel on PersonRole {
  String get label => switch (this) {
        PersonRole.teacher => '老师',
        PersonRole.classmate => '同学',
        PersonRole.friend => '朋友',
        PersonRole.partner => '恋人',
        PersonRole.family => '家人',
        PersonRole.other => '其他',
      };
}

enum EventType { record, plan }

extension EventTypeLabel on EventType {
  String get label => switch (this) {
        EventType.record => '记录',
        EventType.plan => '计划',
      };
}

enum EventOrigin { analysis, manual, institutionCalendar, holiday }

enum PlaceCategory {
  study,
  dining,
  dormitory,
  lab,
  sports,
  social,
  errands,
  other,
}

extension PlaceCategoryLabel on PlaceCategory {
  String get label => switch (this) {
        PlaceCategory.study => '学习',
        PlaceCategory.dining => '吃饭',
        PlaceCategory.dormitory => '宿舍',
        PlaceCategory.lab => '实验',
        PlaceCategory.sports => '运动',
        PlaceCategory.social => '社交',
        PlaceCategory.errands => '办事',
        PlaceCategory.other => '其他',
      };
}

class CampusPlace {
  const CampusPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.note,
    required this.normalizedDx,
    required this.normalizedDy,
    required this.iconKey,
    required this.colorKey,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.isMine = true,
    this.lastVisitedAt,
    this.relatedTodoIds = const [],
    this.relatedPersonIds = const [],
    this.relatedRouteIds = const [],
    this.logCount = 0,
    this.heatScore = 0,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final String note;
  final double normalizedDx;
  final double normalizedDy;
  final String iconKey;
  final String colorKey;
  final bool isFavorite;
  final bool isMine;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastVisitedAt;
  final List<String> relatedTodoIds;
  final List<String> relatedPersonIds;
  final List<String> relatedRouteIds;
  final int logCount;
  final int heatScore;

  CampusPlace copyWith({
    String? id,
    String? name,
    PlaceCategory? category,
    String? note,
    double? normalizedDx,
    double? normalizedDy,
    String? iconKey,
    String? colorKey,
    bool? isFavorite,
    bool? isMine,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastVisitedAt,
    List<String>? relatedTodoIds,
    List<String>? relatedPersonIds,
    List<String>? relatedRouteIds,
    int? logCount,
    int? heatScore,
  }) {
    return CampusPlace(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      note: note ?? this.note,
      normalizedDx: normalizedDx ?? this.normalizedDx,
      normalizedDy: normalizedDy ?? this.normalizedDy,
      iconKey: iconKey ?? this.iconKey,
      colorKey: colorKey ?? this.colorKey,
      isFavorite: isFavorite ?? this.isFavorite,
      isMine: isMine ?? this.isMine,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastVisitedAt: lastVisitedAt ?? this.lastVisitedAt,
      relatedTodoIds: relatedTodoIds ?? this.relatedTodoIds,
      relatedPersonIds: relatedPersonIds ?? this.relatedPersonIds,
      relatedRouteIds: relatedRouteIds ?? this.relatedRouteIds,
      logCount: logCount ?? this.logCount,
      heatScore: heatScore ?? this.heatScore,
    );
  }
}

enum AnalysisSourceType { text, txt, md, docx }

extension AnalysisSourceTypeLabel on AnalysisSourceType {
  String get label => switch (this) {
        AnalysisSourceType.text => '文本输入',
        AnalysisSourceType.txt => 'TXT 文件',
        AnalysisSourceType.md => 'Markdown 文件',
        AnalysisSourceType.docx => 'Word 文件',
      };
}

class AnalysisInput {
  const AnalysisInput({
    required this.rawText,
    required this.sourceType,
    this.sourcePath,
  });

  final String rawText;
  final AnalysisSourceType sourceType;
  final String? sourcePath;
}

class ExtractedTaskDraft {
  const ExtractedTaskDraft({
    required this.id,
    required this.content,
    required this.category,
    required this.type,
    required this.confidence,
    this.relatedPersonNames = const [],
    this.timeHint,
  });

  final String id;
  final String content;
  final ItemCategory category;
  final EventType type;
  final double confidence;
  final List<String> relatedPersonNames;
  final String? timeHint;

  ExtractedTaskDraft copyWith({
    String? id,
    String? content,
    ItemCategory? category,
    EventType? type,
    double? confidence,
    List<String>? relatedPersonNames,
    String? timeHint,
  }) {
    return ExtractedTaskDraft(
      id: id ?? this.id,
      content: content ?? this.content,
      category: category ?? this.category,
      type: type ?? this.type,
      confidence: confidence ?? this.confidence,
      relatedPersonNames: relatedPersonNames ?? this.relatedPersonNames,
      timeHint: timeHint ?? this.timeHint,
    );
  }
}

class ExtractedPersonDraft {
  const ExtractedPersonDraft({
    required this.id,
    required this.name,
    required this.role,
    this.aliases = const [],
    this.relatedTaskIndexes = const [],
  });

  final String id;
  final String name;
  final PersonRole role;
  final List<String> aliases;
  final List<int> relatedTaskIndexes;

  ExtractedPersonDraft copyWith({
    String? id,
    String? name,
    PersonRole? role,
    List<String>? aliases,
    List<int>? relatedTaskIndexes,
  }) {
    return ExtractedPersonDraft(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      aliases: aliases ?? this.aliases,
      relatedTaskIndexes: relatedTaskIndexes ?? this.relatedTaskIndexes,
    );
  }
}

class AnalysisDraft {
  const AnalysisDraft({
    required this.id,
    required this.tasks,
    required this.persons,
    required this.summary,
    required this.warnings,
    required this.createdAt,
  });

  final String id;
  final List<ExtractedTaskDraft> tasks;
  final List<ExtractedPersonDraft> persons;
  final String summary;
  final List<String> warnings;
  final DateTime createdAt;

  AnalysisDraft copyWith({
    String? id,
    List<ExtractedTaskDraft>? tasks,
    List<ExtractedPersonDraft>? persons,
    String? summary,
    List<String>? warnings,
    DateTime? createdAt,
  }) {
    return AnalysisDraft(
      id: id ?? this.id,
      tasks: tasks ?? this.tasks,
      persons: persons ?? this.persons,
      summary: summary ?? this.summary,
      warnings: warnings ?? this.warnings,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ReviewPreview {
  const ReviewPreview({
    required this.id,
    required this.completedTasks,
    required this.plannedTasks,
    required this.persons,
    required this.summary,
    required this.warnings,
    required this.relationLabels,
  });

  final String id;
  final List<ExtractedTaskDraft> completedTasks;
  final List<ExtractedTaskDraft> plannedTasks;
  final List<ExtractedPersonDraft> persons;
  final String summary;
  final List<String> warnings;
  final List<String> relationLabels;
}

class EventItem {
  const EventItem({
    required this.id,
    required this.title,
    required this.category,
    required this.type,
    required this.startAt,
    this.endAt,
    this.origin = EventOrigin.analysis,
    this.personNames = const [],
    this.sourceLabel,
  });

  final String id;
  final String title;
  final ItemCategory category;
  final EventType type;
  final DateTime startAt;
  final DateTime? endAt;
  final EventOrigin origin;
  final List<String> personNames;
  final String? sourceLabel;

  bool get isEditable =>
      origin == EventOrigin.analysis || origin == EventOrigin.manual;

  EventItem copyWith({
    String? id,
    String? title,
    ItemCategory? category,
    EventType? type,
    DateTime? startAt,
    DateTime? endAt,
    EventOrigin? origin,
    List<String>? personNames,
    String? sourceLabel,
  }) {
    return EventItem(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      type: type ?? this.type,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      origin: origin ?? this.origin,
      personNames: personNames ?? this.personNames,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }
}

class PersonProfile {
  const PersonProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.aliases,
    required this.relatedTaskCount,
    required this.relatedPlanTitles,
  });

  final String id;
  final String name;
  final PersonRole role;
  final List<String> aliases;
  final int relatedTaskCount;
  final List<String> relatedPlanTitles;

  PersonProfile copyWith({
    String? id,
    String? name,
    PersonRole? role,
    List<String>? aliases,
    int? relatedTaskCount,
    List<String>? relatedPlanTitles,
  }) {
    return PersonProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      aliases: aliases ?? this.aliases,
      relatedTaskCount: relatedTaskCount ?? this.relatedTaskCount,
      relatedPlanTitles: relatedPlanTitles ?? this.relatedPlanTitles,
    );
  }
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.title,
    required this.input,
    required this.draft,
    required this.preview,
    required this.events,
    required this.people,
    required this.confirmedAt,
  });

  final String id;
  final String title;
  final AnalysisInput input;
  final AnalysisDraft draft;
  final ReviewPreview preview;
  final List<EventItem> events;
  final List<PersonProfile> people;
  final DateTime confirmedAt;

  SessionRecord copyWith({
    String? id,
    String? title,
    AnalysisInput? input,
    AnalysisDraft? draft,
    ReviewPreview? preview,
    List<EventItem>? events,
    List<PersonProfile>? people,
    DateTime? confirmedAt,
  }) {
    return SessionRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      input: input ?? this.input,
      draft: draft ?? this.draft,
      preview: preview ?? this.preview,
      events: events ?? this.events,
      people: people ?? this.people,
      confirmedAt: confirmedAt ?? this.confirmedAt,
    );
  }
}
