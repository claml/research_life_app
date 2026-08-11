import '../utils/workspace_file_kind.dart';

List<T> nullSafeList<T>(List<T>? value) => value ?? <T>[];

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

enum TodoPriority { none, low, medium, high }

extension TodoPriorityLabel on TodoPriority {
  String get label => switch (this) {
    TodoPriority.none => '无',
    TodoPriority.low => '低',
    TodoPriority.medium => '中',
    TodoPriority.high => '高',
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

class ClarificationItem {
  const ClarificationItem({
    required this.type,
    required this.question,
    this.personIndex,
    this.context,
    this.options = const [],
    this.historyMatch,
  });

  final ClarificationType type;
  final String question;
  final int? personIndex;
  final String? context;
  final List<String> options;
  final String? historyMatch;
}

enum ClarificationType {
  identity,
  nameAmbiguous,
  roleUncertain,
  taskPeople,
  other,
}

extension ClarificationTypeLabel on ClarificationType {
  String get label => switch (this) {
    ClarificationType.identity => '身份归属',
    ClarificationType.nameAmbiguous => '称呼歧义',
    ClarificationType.roleUncertain => '角色不确定',
    ClarificationType.taskPeople => '事项归属',
    ClarificationType.other => '其他',
  };

  String get wireValue => switch (this) {
    ClarificationType.identity => 'identity',
    ClarificationType.nameAmbiguous => 'name_ambiguous',
    ClarificationType.roleUncertain => 'role_uncertain',
    ClarificationType.taskPeople => 'task_people',
    ClarificationType.other => 'other',
  };
}

class AnalysisDraft {
  const AnalysisDraft({
    required this.id,
    required this.tasks,
    required this.persons,
    required this.summary,
    required this.warnings,
    required this.createdAt,
    this.clarifications = const [],
  });

  final String id;
  final List<ExtractedTaskDraft> tasks;
  final List<ExtractedPersonDraft> persons;
  final String summary;
  final List<String> warnings;
  final DateTime createdAt;
  final List<ClarificationItem> clarifications;

  AnalysisDraft copyWith({
    String? id,
    List<ExtractedTaskDraft>? tasks,
    List<ExtractedPersonDraft>? persons,
    String? summary,
    List<String>? warnings,
    DateTime? createdAt,
    List<ClarificationItem>? clarifications,
  }) {
    return AnalysisDraft(
      id: id ?? this.id,
      tasks: tasks ?? this.tasks,
      persons: persons ?? this.persons,
      summary: summary ?? this.summary,
      warnings: warnings ?? this.warnings,
      createdAt: createdAt ?? this.createdAt,
      clarifications: clarifications ?? nullSafeList(this.clarifications),
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
    this.isDone = false,
    this.priority = TodoPriority.none,
    this.completedAt,
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
  final bool isDone;
  final TodoPriority priority;
  final DateTime? completedAt;

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
    bool? isDone,
    TodoPriority? priority,
    DateTime? completedAt,
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
      isDone: isDone ?? this.isDone,
      priority: priority ?? this.priority,
      completedAt: completedAt ?? this.completedAt,
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

enum PdfAnnotationContentType {
  text,
  latex,
  mixed;

  static PdfAnnotationContentType parse(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'latex':
        return PdfAnnotationContentType.latex;
      case 'mixed':
        return PdfAnnotationContentType.mixed;
      default:
        return PdfAnnotationContentType.text;
    }
  }

  String get wireValue => name;
}

class PdfNoteDocumentGroup {
  const PdfNoteDocumentGroup({required this.document, required this.notes});

  final PdfLibraryDocument document;
  final List<PdfTextAnnotation> notes;

  DateTime get latestUpdated => notes
      .map((note) => note.updatedAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);
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

/// 毛玻璃（Frosted Glass）外观配置，应用到所有毛玻璃面板。
class GlassSettings {
  const GlassSettings({
    this.blurSigma = defaultBlurSigma,
    this.opacity = defaultOpacity,
    this.noiseEnabled = true,
    this.highlightEnabled = true,
  });

  static const double defaultBlurSigma = 28;
  static const double defaultOpacity = 0.78;
  static const double minBlurSigma = 10;
  static const double maxBlurSigma = 40;
  static const double minOpacity = 0.3;
  static const double maxOpacity = 0.95;

  /// 高斯模糊强度（sigma，越大越糊）。
  final double blurSigma;

  /// 白色材质不透明度（顶部值；底部自动取 64%）。
  final double opacity;

  /// 是否显示细腻噪点纹理。
  final bool noiseEnabled;

  /// 是否显示顶部高光亮线。
  final bool highlightEnabled;

  GlassSettings copyWith({
    double? blurSigma,
    double? opacity,
    bool? noiseEnabled,
    bool? highlightEnabled,
  }) {
    return GlassSettings(
      blurSigma: blurSigma ?? this.blurSigma,
      opacity: opacity ?? this.opacity,
      noiseEnabled: noiseEnabled ?? this.noiseEnabled,
      highlightEnabled: highlightEnabled ?? this.highlightEnabled,
    );
  }

  factory GlassSettings.fromJson(Map<String, Object?> json) {
    return GlassSettings(
      blurSigma: _readBoundedDouble(
        json['blurSigma'],
        defaultBlurSigma,
        min: minBlurSigma,
        max: maxBlurSigma,
      ),
      opacity: _readBoundedDouble(
        json['opacity'],
        defaultOpacity,
        min: minOpacity,
        max: maxOpacity,
      ),
      noiseEnabled: json['noiseEnabled'] != false,
      highlightEnabled: json['highlightEnabled'] != false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'blurSigma': blurSigma,
      'opacity': opacity,
      'noiseEnabled': noiseEnabled,
      'highlightEnabled': highlightEnabled,
    };
  }

  static double _readBoundedDouble(
    Object? value,
    double fallback, {
    required double min,
    required double max,
  }) {
    if (value is num) {
      return value.toDouble().clamp(min, max);
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed.clamp(min, max);
      }
    }
    return fallback;
  }
}

class RemoteLlmAnalysisSettings {
  const RemoteLlmAnalysisSettings({
    this.enableRemoteLlmAnalysis = false,
    this.remoteTimeoutSeconds = defaultRemoteTimeoutSeconds,
    this.fallbackToRules = true,
    this.strictJsonSchema = true,
    this.provider,
    this.baseUrl,
    this.modelName,
    this.apiKey,
  });

  static const defaultRemoteTimeoutSeconds = 120;

  final bool enableRemoteLlmAnalysis;
  final int remoteTimeoutSeconds;
  final bool fallbackToRules;
  final bool strictJsonSchema;

  /// 服务商预设标识：deepseek / openai / moonshot / zhipu / ollama / custom。
  final String? provider;

  /// 自定义服务商 Base URL（OpenAI 兼容 /chat/completions）。
  final String? baseUrl;

  /// 模型名，例如 deepseek-v4-flash、gpt-4o-mini。
  final String? modelName;

  /// 用户自己的 API Key，仅保存在本机偏好中，随周分析请求透传给后端。
  final String? apiKey;

  factory RemoteLlmAnalysisSettings.fromJson(Map<String, Object?> json) {
    return RemoteLlmAnalysisSettings(
      enableRemoteLlmAnalysis: json['enableRemoteLlmAnalysis'] == true,
      remoteTimeoutSeconds: _readPositiveInt(
        json['remoteTimeoutSeconds'],
        defaultRemoteTimeoutSeconds,
      ),
      fallbackToRules: json['fallbackToRules'] is bool
          ? json['fallbackToRules'] == true
          : true,
      strictJsonSchema: json['strictJsonSchema'] is bool
          ? json['strictJsonSchema'] == true
          : true,
      provider: _readNullableString(json['provider']),
      baseUrl: _readNullableString(json['baseUrl']),
      modelName: _readNullableString(json['modelName']),
      apiKey: _readNullableString(json['apiKey']),
    );
  }

  RemoteLlmAnalysisSettings copyWith({
    bool? enableRemoteLlmAnalysis,
    int? remoteTimeoutSeconds,
    bool? fallbackToRules,
    bool? strictJsonSchema,
    String? provider,
    String? baseUrl,
    String? modelName,
    String? apiKey,
  }) {
    return RemoteLlmAnalysisSettings(
      enableRemoteLlmAnalysis:
          enableRemoteLlmAnalysis ?? this.enableRemoteLlmAnalysis,
      remoteTimeoutSeconds: _normalizeTimeout(
        remoteTimeoutSeconds ?? this.remoteTimeoutSeconds,
      ),
      fallbackToRules: fallbackToRules ?? this.fallbackToRules,
      strictJsonSchema: strictJsonSchema ?? this.strictJsonSchema,
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      modelName: modelName ?? this.modelName,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enableRemoteLlmAnalysis': enableRemoteLlmAnalysis,
      'remoteTimeoutSeconds': remoteTimeoutSeconds,
      'fallbackToRules': fallbackToRules,
      'strictJsonSchema': strictJsonSchema,
      'provider': provider,
      'baseUrl': baseUrl,
      'modelName': modelName,
      'apiKey': apiKey,
    };
  }

  static String? _readNullableString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
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
    this.fileKind = WorkspaceFileKind.pdf,
    this.category = '未分类',
    this.lastPage = 1,
    this.pageCount,
    this.lastOpenedAt,
    this.serverId,
    this.syncVersion = 1,
    this.syncState = 'local',
    this.deviceId,
    this.isDeleted = false,
    this.storageKey,
    this.contentHash,
    this.cloudOnly = false,
    this.parentServerId,
    this.inReadingList = true,
  });

  final String id;
  final String title;
  final String path;
  final WorkspaceFileKind fileKind;
  final String category;
  final int lastPage;
  final int? pageCount;
  final DateTime? lastOpenedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? serverId;
  final int syncVersion;
  final String syncState;
  final String? deviceId;
  final bool isDeleted;
  final String? storageKey;
  final String? contentHash;
  final bool cloudOnly;
  final int? parentServerId;
  final bool inReadingList;

  PdfLibraryDocument copyWith({
    String? id,
    String? title,
    String? path,
    WorkspaceFileKind? fileKind,
    String? category,
    int? lastPage,
    int? pageCount,
    DateTime? lastOpenedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? serverId,
    int? syncVersion,
    String? syncState,
    String? deviceId,
    bool? isDeleted,
    String? storageKey,
    String? contentHash,
    bool? cloudOnly,
    int? parentServerId,
    bool? inReadingList,
  }) {
    return PdfLibraryDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      path: path ?? this.path,
      fileKind: fileKind ?? this.fileKind,
      category: category ?? this.category,
      lastPage: lastPage ?? this.lastPage,
      pageCount: pageCount ?? this.pageCount,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      serverId: serverId ?? this.serverId,
      syncVersion: syncVersion ?? this.syncVersion,
      syncState: syncState ?? this.syncState,
      deviceId: deviceId ?? this.deviceId,
      isDeleted: isDeleted ?? this.isDeleted,
      storageKey: storageKey ?? this.storageKey,
      contentHash: contentHash ?? this.contentHash,
      cloudOnly: cloudOnly ?? this.cloudOnly,
      parentServerId: parentServerId ?? this.parentServerId,
      inReadingList: inReadingList ?? this.inReadingList,
    );
  }
}

class CloudFileEntry {
  const CloudFileEntry({
    required this.serverId,
    required this.clientId,
    required this.title,
    required this.entryType,
    this.parentId,
    this.relativePath,
    this.systemRoot = false,
    this.category = '未分类',
    this.lastPage = 1,
    this.pageCount,
    this.storageKey,
    this.contentHash,
    this.version = 1,
    this.updatedAt,
  });

  final int serverId;
  final String clientId;
  final String title;
  final String entryType;
  final int? parentId;
  final String? relativePath;
  final bool systemRoot;
  final String category;
  final int lastPage;
  final int? pageCount;
  final String? storageKey;
  final String? contentHash;
  final int version;
  final DateTime? updatedAt;

  bool get isFolder => entryType == 'folder';

  factory CloudFileEntry.fromJson(Map<String, dynamic> json) {
    return CloudFileEntry(
      serverId: json['serverId'] is int
          ? json['serverId'] as int
          : int.tryParse('${json['serverId']}') ?? 0,
      clientId: '${json['clientId'] ?? ''}',
      title: '${json['title'] ?? '未命名'}',
      entryType: '${json['entryType'] ?? 'file'}',
      parentId: json['parentId'] is int
          ? json['parentId'] as int
          : int.tryParse('${json['parentId']}'),
      relativePath: json['relativePath'] as String?,
      systemRoot: json['systemRoot'] == true,
      category: '${json['category'] ?? '未分类'}',
      lastPage: json['lastPage'] is int
          ? json['lastPage'] as int
          : int.tryParse('${json['lastPage']}') ?? 1,
      pageCount: json['pageCount'] is int
          ? json['pageCount'] as int
          : int.tryParse('${json['pageCount']}'),
      storageKey: json['storageKey'] as String?,
      contentHash: json['contentHash'] as String?,
      version: json['version'] is int
          ? json['version'] as int
          : int.tryParse('${json['version']}') ?? 1,
      updatedAt: _cloudDate(json['updatedAt']),
    );
  }
}

DateTime? _cloudDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
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
    this.contentType = PdfAnnotationContentType.text,
    this.latexContent,
    this.serverId,
    this.syncVersion = 1,
    this.syncState = 'local',
    this.deviceId,
    this.isDeleted = false,
  });

  final String id;
  final String documentId;
  final int pageNumber;
  final PdfAnnotationKind kind;
  final int colorValue;
  final double opacity;
  final String selectedText;
  final String? note;
  final PdfAnnotationContentType contentType;
  final String? latexContent;
  final List<PdfAnnotationRect> rects;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? serverId;
  final int syncVersion;
  final String syncState;
  final String? deviceId;
  final bool isDeleted;

  bool get hasLatex =>
      contentType != PdfAnnotationContentType.text &&
      latexContent != null &&
      latexContent!.trim().isNotEmpty;

  PdfTextAnnotation copyWith({
    String? id,
    String? documentId,
    int? pageNumber,
    PdfAnnotationKind? kind,
    int? colorValue,
    double? opacity,
    String? selectedText,
    String? note,
    PdfAnnotationContentType? contentType,
    String? latexContent,
    List<PdfAnnotationRect>? rects,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? serverId,
    int? syncVersion,
    String? syncState,
    String? deviceId,
    bool? isDeleted,
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
      contentType: contentType ?? this.contentType,
      latexContent: latexContent ?? this.latexContent,
      rects: rects ?? this.rects,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      serverId: serverId ?? this.serverId,
      syncVersion: syncVersion ?? this.syncVersion,
      syncState: syncState ?? this.syncState,
      deviceId: deviceId ?? this.deviceId,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// 独立 Markdown 笔记（与 PDF 批注 note 分离存储）。
class UserNote {
  const UserNote({
    required this.id,
    required this.title,
    this.contentMarkdown = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String contentMarkdown;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserNote copyWith({
    String? title,
    String? contentMarkdown,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserNote(
      id: id,
      title: title ?? this.title,
      contentMarkdown: contentMarkdown ?? this.contentMarkdown,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
