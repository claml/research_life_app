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
    this.zoneId,
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
  final int? zoneId;
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
    int? zoneId,
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
      zoneId: zoneId ?? this.zoneId,
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

enum AnalysisSourceType { text, txt, md, docx, institutionCalendar }

extension AnalysisSourceTypeLabel on AnalysisSourceType {
  String get label => switch (this) {
    AnalysisSourceType.text => '文本输入',
    AnalysisSourceType.txt => 'TXT 文件',
    AnalysisSourceType.md => 'Markdown 文件',
    AnalysisSourceType.docx => 'Word 文件',
    AnalysisSourceType.institutionCalendar => '校历导入',
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

extension SessionRecordKind on SessionRecord {
  bool get isInstitutionCalendar =>
      input.sourceType == AnalysisSourceType.institutionCalendar ||
      events.any((event) => event.origin == EventOrigin.institutionCalendar);
}

enum PdfAnnotationKind {
  bookmark,
  highlight,
  underline,
  strikethrough,
  wavyUnderline,
  note,
}

extension PdfAnnotationKindLabel on PdfAnnotationKind {
  String get label => switch (this) {
    PdfAnnotationKind.bookmark => '书签',
    PdfAnnotationKind.highlight => '高亮',
    PdfAnnotationKind.underline => '下划线',
    PdfAnnotationKind.strikethrough => '删除线',
    PdfAnnotationKind.wavyUnderline => '波浪线',
    PdfAnnotationKind.note => '笔记',
  };
}

class PdfReaderPreferences {
  const PdfReaderPreferences({
    this.sideRailCollapsed = false,
    this.sideTab = defaultSideTab,
    this.highlightColorValue = defaultHighlightColorValue,
  });

  static const defaultSideTab = 'library';
  static const defaultHighlightColorValue = 0xFFFFD54F;
  static const _supportedSideTabs = {'library', 'thumbnails', 'annotations'};

  final bool sideRailCollapsed;
  final String sideTab;
  final int highlightColorValue;

  factory PdfReaderPreferences.fromJson(Map<String, Object?> json) {
    final rawSideTab = json['sideTab'];
    final sideTab =
        rawSideTab is String && _supportedSideTabs.contains(rawSideTab)
        ? rawSideTab
        : defaultSideTab;

    return PdfReaderPreferences(
      sideRailCollapsed: json['sideRailCollapsed'] == true,
      sideTab: sideTab,
      highlightColorValue: _readColorValue(json['highlightColorValue']),
    );
  }

  PdfReaderPreferences copyWith({
    bool? sideRailCollapsed,
    String? sideTab,
    int? highlightColorValue,
  }) {
    return PdfReaderPreferences(
      sideRailCollapsed: sideRailCollapsed ?? this.sideRailCollapsed,
      sideTab: sideTab == null || !_supportedSideTabs.contains(sideTab)
          ? this.sideTab
          : sideTab,
      highlightColorValue: highlightColorValue ?? this.highlightColorValue,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sideRailCollapsed': sideRailCollapsed,
      'sideTab': sideTab,
      'highlightColorValue': highlightColorValue,
    };
  }

  static int _readColorValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? defaultHighlightColorValue;
    }
    return defaultHighlightColorValue;
  }
}

class LocalLlmAnalysisSettings {
  const LocalLlmAnalysisSettings({
    this.enableLocalLlmAnalysis = false,
    this.ollamaBaseUrl = defaultOllamaBaseUrl,
    this.ollamaModel = defaultOllamaModel,
    this.ollamaTimeoutSeconds = defaultOllamaTimeoutSeconds,
    this.fallbackToRules = true,
    this.strictJsonSchema = true,
  });

  static const defaultOllamaBaseUrl = 'http://127.0.0.1:11434';
  static const defaultOllamaModel = 'qwen3:8b';
  static const defaultOllamaTimeoutSeconds = 60;

  final bool enableLocalLlmAnalysis;
  final String ollamaBaseUrl;
  final String ollamaModel;
  final int ollamaTimeoutSeconds;
  final bool fallbackToRules;
  final bool strictJsonSchema;

  factory LocalLlmAnalysisSettings.fromJson(Map<String, Object?> json) {
    return LocalLlmAnalysisSettings(
      enableLocalLlmAnalysis: json['enableLocalLlmAnalysis'] == true,
      ollamaBaseUrl: _readNonEmptyString(
        json['ollamaBaseUrl'],
        defaultOllamaBaseUrl,
      ),
      ollamaModel: _readNonEmptyString(json['ollamaModel'], defaultOllamaModel),
      ollamaTimeoutSeconds: _readPositiveInt(
        json['ollamaTimeoutSeconds'],
        defaultOllamaTimeoutSeconds,
      ),
      fallbackToRules: json['fallbackToRules'] is bool
          ? json['fallbackToRules'] == true
          : true,
      strictJsonSchema: json['strictJsonSchema'] is bool
          ? json['strictJsonSchema'] == true
          : true,
    );
  }

  LocalLlmAnalysisSettings copyWith({
    bool? enableLocalLlmAnalysis,
    String? ollamaBaseUrl,
    String? ollamaModel,
    int? ollamaTimeoutSeconds,
    bool? fallbackToRules,
    bool? strictJsonSchema,
  }) {
    return LocalLlmAnalysisSettings(
      enableLocalLlmAnalysis:
          enableLocalLlmAnalysis ?? this.enableLocalLlmAnalysis,
      ollamaBaseUrl: _normalizeBaseUrl(ollamaBaseUrl ?? this.ollamaBaseUrl),
      ollamaModel: _normalizeModel(ollamaModel ?? this.ollamaModel),
      ollamaTimeoutSeconds: _normalizeTimeout(
        ollamaTimeoutSeconds ?? this.ollamaTimeoutSeconds,
      ),
      fallbackToRules: fallbackToRules ?? this.fallbackToRules,
      strictJsonSchema: strictJsonSchema ?? this.strictJsonSchema,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enableLocalLlmAnalysis': enableLocalLlmAnalysis,
      'ollamaBaseUrl': ollamaBaseUrl,
      'ollamaModel': ollamaModel,
      'ollamaTimeoutSeconds': ollamaTimeoutSeconds,
      'fallbackToRules': fallbackToRules,
      'strictJsonSchema': strictJsonSchema,
    };
  }

  static String _readNonEmptyString(Object? value, String fallback) {
    if (value is! String || value.trim().isEmpty) {
      return fallback;
    }
    return value.trim();
  }

  static int _readPositiveInt(Object? value, int fallback) {
    final parsed = value is int
        ? value
        : value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;
    return _normalizeTimeout(parsed ?? fallback);
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? defaultOllamaBaseUrl : trimmed;
  }

  static String _normalizeModel(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? defaultOllamaModel : trimmed;
  }

  static int _normalizeTimeout(int value) {
    if (value < 5) {
      return 5;
    }
    if (value > 600) {
      return 600;
    }
    return value;
  }
}

class PdfLibraryDocument {
  const PdfLibraryDocument({
    required this.id,
    required this.title,
    required this.path,
    required this.createdAt,
    required this.updatedAt,
    this.category = '未分类',
    this.lastPage = 1,
    this.pageCount,
    this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String path;
  final String category;
  final int lastPage;
  final int? pageCount;
  final DateTime? lastOpenedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  PdfLibraryDocument copyWith({
    String? id,
    String? title,
    String? path,
    String? category,
    int? lastPage,
    int? pageCount,
    DateTime? lastOpenedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PdfLibraryDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      category: category ?? this.category,
      lastPage: lastPage ?? this.lastPage,
      pageCount: pageCount ?? this.pageCount,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class PdfAnnotationRect {
  const PdfAnnotationRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => (top - bottom).abs();
}

class PdfTextAnnotation {
  const PdfTextAnnotation({
    required this.id,
    required this.documentId,
    required this.pageNumber,
    required this.kind,
    required this.colorValue,
    required this.opacity,
    required this.selectedText,
    required this.rects,
    required this.createdAt,
    required this.updatedAt,
    this.note,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final PdfAnnotationKind kind;
  final int colorValue;
  final double opacity;
  final String selectedText;
  final String? note;
  final List<PdfAnnotationRect> rects;
  final DateTime createdAt;
  final DateTime updatedAt;

  PdfTextAnnotation copyWith({
    String? id,
    String? documentId,
    int? pageNumber,
    PdfAnnotationKind? kind,
    int? colorValue,
    double? opacity,
    String? selectedText,
    String? note,
    List<PdfAnnotationRect>? rects,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PdfTextAnnotation(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      pageNumber: pageNumber ?? this.pageNumber,
      kind: kind ?? this.kind,
      colorValue: colorValue ?? this.colorValue,
      opacity: opacity ?? this.opacity,
      selectedText: selectedText ?? this.selectedText,
      note: note ?? this.note,
      rects: rects ?? this.rects,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
