import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../core/models/app_models.dart';
import '../services/analysis/analysis_service.dart';
import '../services/calendar/institution_calendar_service.dart';
import '../services/import/import_service.dart';
import '../services/review/review_service.dart';
import '../services/storage/local_workspace_service.dart';

enum HomeImageSlot { researchWall, lifeWall }

extension HomeImageSlotLabel on HomeImageSlot {
  String get label => switch (this) {
    HomeImageSlot.researchWall => '研究墙',
    HomeImageSlot.lifeWall => '生活墙',
  };

  String get fileBaseName => switch (this) {
    HomeImageSlot.researchWall => 'research_wall',
    HomeImageSlot.lifeWall => 'life_wall',
  };
}

class ResearchLifeController extends ChangeNotifier {
  ResearchLifeController({
    required ImportService importService,
    required AnalysisService analysisService,
    required ReviewService reviewService,
    required InstitutionCalendarService institutionCalendarService,
    required LocalWorkspaceService localWorkspaceService,
  }) : _importService = importService,
       _analysisService = analysisService,
       _reviewService = reviewService,
       _institutionCalendarService = institutionCalendarService,
       _localWorkspaceService = localWorkspaceService;

  static const sampleText = '''
这周我完成了论文第二章的资料整理，周三和王老师同步了实验计划，
周四晚上和陈同学讨论数据清洗方案，周五跑了 4 公里。
下周二准备和导师开会确认论文框架，周末打算和朋友见面聊天。
''';

  static const _supportedImageExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
  ];

  static const defaultWeeklyPromptTemplate = '''
你是一名擅长中文周报润色的助手。请根据我提供的实际事项，整理成一段适合直接提交的周工作描述。
要求：
1. 只基于提供内容改写，不补充虚构信息。
2. 语气专业、自然、简洁，适度润色。
3. 优先写已完成工作，再带出后续计划。
4. 输出 1 到 2 段中文，不要使用标题，不要使用项目符号。
5. 如果涉及协作对象，只保留与工作推进相关的信息。

时间范围：
{{date_range}}

已完成事项（共 {{record_count}} 条）：
{{completed_items}}

计划事项（共 {{plan_count}} 条）：
{{planned_items}}

涉及人物（共 {{people_count}} 位）：
{{people}}

全部记录：
{{all_events}}
''';

  final ImportService _importService;
  final AnalysisService _analysisService;
  final ReviewService _reviewService;
  final InstitutionCalendarService _institutionCalendarService;
  final LocalWorkspaceService _localWorkspaceService;

  final TextEditingController inputController = TextEditingController();

  AnalysisInput? _currentInput;
  AnalysisDraft? _currentDraft;
  ReviewPreview? _currentPreview;
  SessionRecord? _latestSession;
  final List<SessionRecord> _sessionHistory = [];
  List<EventItem> _manualEvents = const [];
  List<EventItem> _institutionCalendarEvents = const [];
  String? _institutionCalendarTitle;
  final List<CampusPlace> _campusPlaces = _buildSampleCampusPlaces();

  bool _isBusy = false;
  bool _lastImportSucceeded = false;
  String? _sourceLabel;

  String? _storageDirectoryPath;
  String? _homeImageFolderPath;
  String? _researchWallImagePath;
  String? _lifeWallImagePath;
  bool _galleryInitialized = false;
  bool _galleryBusy = false;
  String _weeklyPromptTemplate = defaultWeeklyPromptTemplate;
  bool _weeklyPromptTemplateLoaded = false;
  bool _weeklyPromptTemplateBusy = false;

  AnalysisDraft? get currentDraft => _currentDraft;
  ReviewPreview? get currentPreview => _currentPreview;
  SessionRecord? get latestSession => _latestSession;
  List<SessionRecord> get sessionHistory => List.unmodifiable(_sessionHistory);
  List<EventItem> get manualEvents => List.unmodifiable(_manualEvents);
  List<EventItem> get institutionCalendarEvents =>
      List.unmodifiable(_institutionCalendarEvents);
  List<CampusPlace> get campusPlaces => List.unmodifiable(_campusPlaces);
  List<EventItem> get calendarEvents => List.unmodifiable([
    for (final session in _sessionHistory) ...session.events,
    ..._manualEvents,
    ..._institutionCalendarEvents,
  ]);
  String? get institutionCalendarTitle => _institutionCalendarTitle;
  String get institutionCalendarPrompt =>
      InstitutionCalendarService.importPrompt;
  String get institutionCalendarTemplate =>
      InstitutionCalendarService.exampleTemplate;
  bool get isBusy => _isBusy;
  bool get lastImportSucceeded => _lastImportSucceeded;
  String? get sourceLabel => _sourceLabel;

  String? get homeImageFolderPath => _homeImageFolderPath;
  String? get researchWallImagePath => _researchWallImagePath;
  String? get lifeWallImagePath => _lifeWallImagePath;
  String? get storageDirectoryPath => _storageDirectoryPath;
  bool get galleryBusy => _galleryBusy;
  String get weeklyPromptTemplate => _weeklyPromptTemplate;
  bool get weeklyPromptTemplateLoaded => _weeklyPromptTemplateLoaded;

  Future<String?> pickFileAndImport() async {
    const group = XTypeGroup(
      label: '研究生活导入',
      extensions: ['txt', 'md', 'docx', 'doc'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) {
      return null;
    }
    return importFileFromPath(file.path);
  }

  Future<String?> importFileFromPath(String path) async {
    _setBusy(true);
    try {
      final result = await _importService.importFile(path);
      if (!result.success || result.input == null) {
        _lastImportSucceeded = false;
        return result.message;
      }

      _lastImportSucceeded = true;
      _currentInput = result.input;
      _sourceLabel = _formatSourceLabel(result.input!);
      inputController.text = result.input!.rawText;
      _currentDraft = null;
      _currentPreview = null;
      notifyListeners();
      return result.message;
    } finally {
      _setBusy(false);
    }
  }

  String? analyzeCurrentInput() {
    final rawText = inputController.text.trim();
    if (rawText.isEmpty) {
      return '请先输入一段周描述，或导入 TXT / MD / DOCX 文件。';
    }

    final input = AnalysisInput(
      rawText: rawText,
      sourceType: _currentInput?.sourceType ?? AnalysisSourceType.text,
      sourcePath: _currentInput?.sourcePath,
    );

    _currentInput = input;
    _sourceLabel = _formatSourceLabel(input);
    _currentDraft = _analysisService.analyze(input);
    _currentPreview = _reviewService.buildPreview(_currentDraft!);
    _lastImportSucceeded = false;
    notifyListeners();
    return _currentPreview!.warnings.isEmpty
        ? null
        : _currentPreview!.warnings.first;
  }

  String? confirmDraft() {
    final draft = _currentDraft;
    final input = _currentInput;
    if (draft == null || input == null) {
      return '当前还没有可以确认的分析结果。';
    }

    final now = DateTime.now();
    final sessionKey = '${now.millisecondsSinceEpoch}';
    final sessionDraft = _buildSessionDraft(draft, sessionKey);
    final sessionPreview = _reviewService.buildPreview(sessionDraft);
    final events = _buildEventsFromDraft(sessionDraft);
    final people = _buildPeopleFromDraft(sessionDraft);
    final session = SessionRecord(
      id: 'session_$sessionKey',
      title: '第 ${_sessionHistory.length + 1} 次分析',
      input: input,
      draft: sessionDraft,
      preview: sessionPreview,
      events: events,
      people: people,
      confirmedAt: now,
    );

    _latestSession = session;
    _sessionHistory.insert(0, session);
    _currentDraft = sessionDraft;
    _currentPreview = sessionPreview;
    notifyListeners();
    return '分析结果已确认，已同步到主页、人物关系和历史记录。';
  }

  String fillSampleAndAnalyze() {
    _currentInput = null;
    _sourceLabel = AnalysisSourceType.text.label;
    inputController.text = sampleText.trim();
    return analyzeCurrentInput() ?? '已填入示例并完成分析。';
  }

  String addManualEvent({
    required DateTime date,
    required String title,
    required ItemCategory category,
    required EventType type,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '标题不能为空。';
    }

    final day = DateTime(date.year, date.month, date.day);
    final event = EventItem(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      title: normalizedTitle,
      category: category,
      type: type,
      startAt: day,
      endAt: day,
      origin: EventOrigin.manual,
      sourceLabel: '手动添加',
    );
    _manualEvents = [..._manualEvents, event];
    notifyListeners();
    return '已添加记录。';
  }

  String updateEditableEvent({
    required String eventId,
    required String title,
    required ItemCategory category,
    required EventType type,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return '标题不能为空。';
    }

    final manualIndex = _manualEvents.indexWhere(
      (event) => event.id == eventId,
    );
    if (manualIndex != -1) {
      final target = _manualEvents[manualIndex];
      if (!target.isEditable) {
        return '该记录不允许修改。';
      }

      final nextManualEvents = [..._manualEvents];
      nextManualEvents[manualIndex] = target.copyWith(
        title: normalizedTitle,
        category: category,
        type: type,
      );
      _manualEvents = nextManualEvents;
      notifyListeners();
      return '已更新记录。';
    }

    final session = _findSessionByEventId(eventId);
    if (session == null) {
      return '当前没有可修改的记录。';
    }

    final sessionIndex = session.events.indexWhere(
      (event) => event.id == eventId,
    );
    if (sessionIndex == -1) {
      return '没有找到要修改的记录。';
    }

    final target = session.events[sessionIndex];
    if (!target.isEditable) {
      return '节假日和校历内容不允许修改。';
    }

    final updatedEvents = [...session.events];
    updatedEvents[sessionIndex] = target.copyWith(
      title: normalizedTitle,
      category: category,
      type: type,
    );
    if (sessionIndex >= session.draft.tasks.length) {
      return '记录与分析草稿不同步，暂时无法修改。';
    }

    final updatedTasks = [...session.draft.tasks];
    updatedTasks[sessionIndex] = updatedTasks[sessionIndex].copyWith(
      content: normalizedTitle,
      category: category,
      type: type,
    );
    final updatedDraft = session.draft.copyWith(
      tasks: updatedTasks,
      summary: _buildDraftSummary(updatedTasks, session.draft.persons),
    );
    final updatedPreview = _reviewService.buildPreview(updatedDraft);
    final updatedSession = session.copyWith(
      draft: updatedDraft,
      preview: updatedPreview,
      events: updatedEvents,
      people: _buildPeopleFromDraft(updatedDraft),
    );
    _replaceSessionRecord(updatedSession);
    notifyListeners();
    return '已更新记录。';
  }

  String mergePersons({
    required String primaryPersonId,
    required String secondaryPersonId,
  }) {
    if (primaryPersonId == secondaryPersonId) {
      return '请选择两个不同的人物。';
    }

    final primarySession = _findSessionByPersonId(primaryPersonId);
    final secondarySession = _findSessionByPersonId(secondaryPersonId);
    if (primarySession == null || secondarySession == null) {
      return '当前没有可合并的人物数据。';
    }
    if (primarySession.id != secondarySession.id) {
      return '暂不支持跨分析会话合并人物。';
    }
    final session = primarySession;

    final primaryProfile = _findPersonProfileById(
      session.people,
      primaryPersonId,
    );
    final secondaryProfile = _findPersonProfileById(
      session.people,
      secondaryPersonId,
    );
    if (primaryProfile == null || secondaryProfile == null) {
      return '未找到要合并的人物。';
    }

    final primaryDraft = _findPersonDraftById(
      session.draft.persons,
      primaryPersonId,
    );
    final secondaryDraft = _findPersonDraftById(
      session.draft.persons,
      secondaryPersonId,
    );
    if (primaryDraft == null || secondaryDraft == null) {
      return '人物草稿数据不完整，暂时无法合并。';
    }

    final primaryKnownNames = _collectKnownPersonNames(
      profile: primaryProfile,
      draft: primaryDraft,
    );
    final secondaryKnownNames = _collectKnownPersonNames(
      profile: secondaryProfile,
      draft: secondaryDraft,
    );
    final mergedKnownNames = <String>{
      ...primaryKnownNames,
      ...secondaryKnownNames,
    };
    final updatedTasks = session.draft.tasks
        .map(
          (task) => task.copyWith(
            relatedPersonNames: _mergePersonNames(
              task.relatedPersonNames,
              mergedKnownNames: mergedKnownNames,
              primaryName: primaryProfile.name,
            ),
          ),
        )
        .toList();
    final updatedDraftPersons = session.draft.persons
        .where((person) => person.id != secondaryPersonId)
        .map((person) {
          if (person.id != primaryPersonId) {
            return person;
          }

          return person.copyWith(
            name: primaryProfile.name,
            role: _resolveMergedPersonRole(
              primaryProfile.role,
              secondaryProfile.role,
            ),
            aliases: _buildMergedAliases(
              primaryName: primaryProfile.name,
              primaryKnownNames: primaryKnownNames,
              secondaryKnownNames: secondaryKnownNames,
            ),
            relatedTaskIndexes: _collectTaskIndexesForPerson(
              updatedTasks,
              primaryProfile.name,
            ),
          );
        })
        .toList();
    final updatedDraft = session.draft.copyWith(
      tasks: updatedTasks,
      persons: updatedDraftPersons,
      summary: _buildDraftSummary(updatedTasks, updatedDraftPersons),
    );
    final updatedPreview = _reviewService.buildPreview(updatedDraft);
    final updatedEvents = session.events
        .map(
          (event) => event.copyWith(
            personNames: _mergePersonNames(
              event.personNames,
              mergedKnownNames: mergedKnownNames,
              primaryName: primaryProfile.name,
            ),
          ),
        )
        .toList();
    final updatedSession = session.copyWith(
      draft: updatedDraft,
      preview: updatedPreview,
      events: updatedEvents,
      people: _buildPeopleFromDraft(updatedDraft),
    );

    _replaceSessionRecord(updatedSession);
    notifyListeners();
    return '已将“${secondaryProfile.name}”合并到“${primaryProfile.name}”。';
  }

  String renamePerson({
    required String personId,
    required String nextName,
    bool keepOriginalNameAsAlias = true,
  }) {
    final normalizedName = nextName.trim();
    if (normalizedName.isEmpty) {
      return '称谓不能为空。';
    }

    final session = _findSessionByPersonId(personId);
    if (session == null) {
      return '当前没有可编辑的人物数据。';
    }

    final profile = _findPersonProfileById(session.people, personId);
    final draftPerson = _findPersonDraftById(session.draft.persons, personId);
    if (profile == null || draftPerson == null) {
      return '未找到要编辑的人物。';
    }
    if (normalizedName == profile.name) {
      return '称谓未发生变化。';
    }
    if (_hasPersonNameConflict(
      people: session.people,
      personId: personId,
      candidateName: normalizedName,
    )) {
      return '已存在同名人物，请直接使用“合并人物”。';
    }

    final knownNames = _collectKnownPersonNames(
      profile: profile,
      draft: draftPerson,
    );
    final updatedTasks = session.draft.tasks
        .map(
          (task) => task.copyWith(
            relatedPersonNames: _mergePersonNames(
              task.relatedPersonNames,
              mergedKnownNames: knownNames,
              primaryName: normalizedName,
            ),
          ),
        )
        .toList();
    final updatedDraftPersons = session.draft.persons.map((person) {
      if (person.id != personId) {
        return person;
      }

      return person.copyWith(
        name: normalizedName,
        aliases: _buildRenamedAliases(
          nextName: normalizedName,
          knownNames: knownNames,
          originalNames: {profile.name, draftPerson.name},
          keepOriginalNameAsAlias: keepOriginalNameAsAlias,
        ),
        relatedTaskIndexes: _collectTaskIndexesForPerson(
          updatedTasks,
          normalizedName,
        ),
      );
    }).toList();
    final updatedDraft = session.draft.copyWith(
      tasks: updatedTasks,
      persons: updatedDraftPersons,
      summary: _buildDraftSummary(updatedTasks, updatedDraftPersons),
    );
    final updatedPreview = _reviewService.buildPreview(updatedDraft);
    final updatedEvents = session.events
        .map(
          (event) => event.copyWith(
            personNames: _mergePersonNames(
              event.personNames,
              mergedKnownNames: knownNames,
              primaryName: normalizedName,
            ),
          ),
        )
        .toList();
    final updatedSession = session.copyWith(
      draft: updatedDraft,
      preview: updatedPreview,
      events: updatedEvents,
      people: _buildPeopleFromDraft(updatedDraft),
    );

    _replaceSessionRecord(updatedSession);
    notifyListeners();
    return '已将人物称谓更新为“$normalizedName”。';
  }

  String importInstitutionCalendar(String rawText) {
    final result = _institutionCalendarService.parse(rawText);
    _institutionCalendarEvents = result.events;
    _institutionCalendarTitle = result.title;
    notifyListeners();

    if (result.warnings.isEmpty) {
      return result.summary;
    }
    return '${result.summary}\n${result.warnings.join('\n')}';
  }

  String clearInstitutionCalendar() {
    if (_institutionCalendarEvents.isEmpty) {
      return '当前没有已导入的校历。';
    }

    _institutionCalendarEvents = const [];
    _institutionCalendarTitle = null;
    notifyListeners();
    return '已清空校历导入内容。';
  }

  void clearComposer() {
    inputController.clear();
    _currentInput = null;
    _currentDraft = null;
    _currentPreview = null;
    _lastImportSucceeded = false;
    _sourceLabel = null;
    notifyListeners();
  }

  void clearDraftOnly() {
    _currentDraft = null;
    _currentPreview = null;
    _lastImportSucceeded = false;
    notifyListeners();
  }

  Future<void> ensureWeeklyPromptTemplateLoaded() async {
    if (_weeklyPromptTemplateLoaded || _weeklyPromptTemplateBusy) {
      return;
    }

    _weeklyPromptTemplateBusy = true;
    try {
      final storedTemplate = await _localWorkspaceService
          .loadWeeklyPromptTemplate();
      if (storedTemplate != null && storedTemplate.trim().isNotEmpty) {
        _weeklyPromptTemplate = storedTemplate;
      }
      _weeklyPromptTemplateLoaded = true;
      notifyListeners();
    } finally {
      _weeklyPromptTemplateBusy = false;
    }
  }

  Future<String> saveWeeklyPromptTemplate(String template) async {
    final normalizedTemplate = template.trim();
    if (normalizedTemplate.isEmpty) {
      return '常用提示词模板不能为空。';
    }

    await _localWorkspaceService.saveWeeklyPromptTemplate(normalizedTemplate);
    _weeklyPromptTemplate = normalizedTemplate;
    _weeklyPromptTemplateLoaded = true;
    notifyListeners();
    return '已设为常用提示词模板。';
  }

  Future<String> resetWeeklyPromptTemplate() async {
    await _localWorkspaceService.saveWeeklyPromptTemplate(
      defaultWeeklyPromptTemplate,
    );
    _weeklyPromptTemplate = defaultWeeklyPromptTemplate;
    _weeklyPromptTemplateLoaded = true;
    notifyListeners();
    return '已恢复默认提示词模板。';
  }

  String buildWeeklyReportPrompt({
    required DateTime start,
    required DateTime end,
    required List<EventItem> rangeEvents,
    String? templateOverride,
  }) {
    final effectiveTemplate = (templateOverride ?? '').trim().isEmpty
        ? _weeklyPromptTemplate
        : templateOverride!.trim();
    final sortedEvents = [...rangeEvents]
      ..sort((left, right) => left.startAt.compareTo(right.startAt));
    final records = sortedEvents
        .where((event) => event.type == EventType.record)
        .toList();
    final plans = sortedEvents
        .where((event) => event.type == EventType.plan)
        .toList();
    final people = _collectUniquePeople(sortedEvents);

    final replacements = <String, String>{
      '{{date_range}}': '${_formatMonthDay(start)} - ${_formatMonthDay(end)}',
      '{{record_count}}': '${records.length}',
      '{{plan_count}}': '${plans.length}',
      '{{people_count}}': '${people.length}',
      '{{completed_items}}': _formatPromptEventList(records),
      '{{planned_items}}': _formatPromptEventList(plans),
      '{{people}}': _formatPeopleList(people),
      '{{all_events}}': _formatPromptEventList(sortedEvents, includeMeta: true),
    };

    var prompt = effectiveTemplate;
    for (final entry in replacements.entries) {
      prompt = prompt.replaceAll(entry.key, entry.value);
    }
    return prompt.trim();
  }

  Future<void> ensureHomeGalleryReady() async {
    if (_galleryInitialized || _galleryBusy) {
      return;
    }

    _setGalleryBusy(true);
    try {
      final storageDirectory = await _localWorkspaceService
          .resolveStorageDirectory();
      final folder = Directory(
        '${storageDirectory.parent.path}${Platform.pathSeparator}home_images',
      );
      await _migrateLegacyHomeImageFolderIfNeeded(storageDirectory, folder);
      await folder.create(recursive: true);
      await _ensureReadme(folder);

      _storageDirectoryPath = storageDirectory.path;
      _homeImageFolderPath = folder.path;
      await refreshHomeImages(notify: false);
      _galleryInitialized = true;
      notifyListeners();
    } finally {
      _setGalleryBusy(false);
    }
  }

  Future<String?> refreshHomeImages({bool notify = true}) async {
    if (_homeImageFolderPath == null) {
      return null;
    }

    _researchWallImagePath = await _findImageForSlot(
      HomeImageSlot.researchWall,
    );
    _lifeWallImagePath = await _findImageForSlot(HomeImageSlot.lifeWall);

    if (_researchWallImagePath != null) {
      await FileImage(File(_researchWallImagePath!)).evict();
    }
    if (_lifeWallImagePath != null) {
      await FileImage(File(_lifeWallImagePath!)).evict();
    }

    if (notify) {
      notifyListeners();
      return '图片已刷新。';
    }
    return null;
  }

  Future<String?> replaceHomeImage(HomeImageSlot slot) async {
    await ensureHomeGalleryReady();
    const group = XTypeGroup(
      label: '主页图片',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) {
      return null;
    }

    return replaceHomeImageFromPath(slot, file.path);
  }

  Future<String?> replaceHomeImageFromPath(
    HomeImageSlot slot,
    String sourcePath,
  ) async {
    await ensureHomeGalleryReady();
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return '图片文件夹初始化失败。';
    }

    _setGalleryBusy(true);
    final backupSuffix = '.bak_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final extension = _extensionOf(sourcePath);
      final targetPath =
          '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension';
      final tempPath =
          '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.incoming.$extension';
      final backupPaths = <String>[];
      await File(sourcePath).copy(tempPath);

      for (final existingFile in await _existingSlotFiles(slot)) {
        final backupPath = '${existingFile.path}$backupSuffix';
        await existingFile.rename(backupPath);
        backupPaths.add(backupPath);
      }

      await File(tempPath).rename(targetPath);
      await FileImage(File(targetPath)).evict();
      for (final backupPath in backupPaths) {
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          await backupFile.delete();
        }
      }
      await refreshHomeImages(notify: false);
      notifyListeners();
      return '已更新${slot.label}图片。';
    } on FileSystemException catch (error) {
      await _restoreSlotReplacement(slot, backupSuffix);
      return '替换图片失败：${error.message}';
    } finally {
      _setGalleryBusy(false);
    }
  }

  Future<String?> openHomeImageFolder() async {
    await ensureHomeGalleryReady();
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return '图片文件夹初始化失败。';
    }

    return _openFolder(folderPath, '图片文件夹');
  }

  Future<String?> openStorageFolder() async {
    await ensureHomeGalleryReady();
    final storagePath = _storageDirectoryPath;
    if (storagePath == null) {
      return '应用数据目录初始化失败。';
    }

    return _openFolder(storagePath, '应用数据目录');
  }

  CampusPlace createCampusPlace({
    required String name,
    required PlaceCategory category,
    required String note,
    required double normalizedDx,
    required double normalizedDy,
    required String iconKey,
    required String colorKey,
    bool isMine = true,
  }) {
    final now = DateTime.now();
    final place = CampusPlace(
      id: 'place_${now.microsecondsSinceEpoch}',
      name: name.trim(),
      category: category,
      note: note.trim(),
      normalizedDx: _normalizeFraction(normalizedDx),
      normalizedDy: _normalizeFraction(normalizedDy),
      iconKey: iconKey,
      colorKey: colorKey,
      createdAt: now,
      updatedAt: now,
      isMine: isMine,
    );
    _campusPlaces.insert(0, place);
    notifyListeners();
    return place;
  }

  bool updateCampusPlace({
    required String id,
    required String name,
    required PlaceCategory category,
    required String note,
    required double normalizedDx,
    required double normalizedDy,
    required String iconKey,
    required String colorKey,
    required bool isMine,
  }) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    final current = _campusPlaces[index];
    _campusPlaces[index] = current.copyWith(
      name: name.trim(),
      category: category,
      note: note.trim(),
      normalizedDx: _normalizeFraction(normalizedDx),
      normalizedDy: _normalizeFraction(normalizedDy),
      iconKey: iconKey,
      colorKey: colorKey,
      isMine: isMine,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    return true;
  }

  bool deleteCampusPlace(String id) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    _campusPlaces.removeAt(index);
    notifyListeners();
    return true;
  }

  bool toggleCampusPlaceFavorite(String id) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    final current = _campusPlaces[index];
    _campusPlaces[index] = current.copyWith(
      isFavorite: !current.isFavorite,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    return true;
  }

  bool markCampusPlaceVisited(String id) {
    final index = _campusPlaces.indexWhere((place) => place.id == id);
    if (index == -1) {
      return false;
    }

    final current = _campusPlaces[index];
    final now = DateTime.now();
    _campusPlaces[index] = current.copyWith(
      lastVisitedAt: now,
      updatedAt: now,
      heatScore: current.heatScore + 1,
    );
    notifyListeners();
    return true;
  }

  CampusPlace? campusPlaceById(String id) {
    for (final place in _campusPlaces) {
      if (place.id == id) {
        return place;
      }
    }
    return null;
  }

  @override
  void dispose() {
    inputController.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }
    _isBusy = value;
    notifyListeners();
  }

  void _setGalleryBusy(bool value) {
    if (_galleryBusy == value) {
      return;
    }
    _galleryBusy = value;
    notifyListeners();
  }

  String _formatSourceLabel(AnalysisInput input) {
    final sourcePath = input.sourcePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      return input.sourceType.label;
    }

    final segments = sourcePath.replaceAll('\\', '/').split('/');
    return '${input.sourceType.label} · ${segments.last}';
  }

  List<EventItem> _buildEventsFromDraft(AnalysisDraft draft) {
    final anchor = draft.createdAt;
    return List<EventItem>.generate(draft.tasks.length, (index) {
      final task = draft.tasks[index];
      final date = _resolveDate(task, anchor, index);
      return EventItem(
        id: 'event_${draft.id}_$index',
        title: task.content,
        category: task.category,
        type: task.type,
        startAt: date,
        endAt: date,
        origin: EventOrigin.analysis,
        personNames: task.relatedPersonNames,
        sourceLabel: _sourceLabel,
      );
    });
  }

  List<PersonProfile> _buildPeopleFromDraft(AnalysisDraft draft) {
    return draft.persons.map((person) {
      final relatedPlans = person.relatedTaskIndexes
          .where((index) => index < draft.tasks.length)
          .map((index) => draft.tasks[index])
          .where((task) => task.type == EventType.plan)
          .map((task) => task.content)
          .toList();

      return PersonProfile(
        id: person.id,
        name: person.name,
        role: person.role,
        aliases: person.aliases,
        relatedTaskCount: person.relatedTaskIndexes.length,
        relatedPlanTitles: relatedPlans,
      );
    }).toList();
  }

  AnalysisDraft _buildSessionDraft(AnalysisDraft draft, String sessionKey) {
    final updatedPeople = draft.persons
        .map(
          (person) =>
              person.copyWith(id: 'session_${sessionKey}__${person.id}'),
        )
        .toList();
    return draft.copyWith(persons: updatedPeople);
  }

  SessionRecord? _findSessionByEventId(String eventId) {
    for (final session in _sessionHistory) {
      if (session.events.any((event) => event.id == eventId)) {
        return session;
      }
    }
    return null;
  }

  SessionRecord? _findSessionByPersonId(String personId) {
    for (final session in _sessionHistory) {
      if (session.people.any((person) => person.id == personId)) {
        return session;
      }
    }
    return null;
  }

  PersonProfile? _findPersonProfileById(
    List<PersonProfile> people,
    String personId,
  ) {
    for (final person in people) {
      if (person.id == personId) {
        return person;
      }
    }
    return null;
  }

  ExtractedPersonDraft? _findPersonDraftById(
    List<ExtractedPersonDraft> people,
    String personId,
  ) {
    for (final person in people) {
      if (person.id == personId) {
        return person;
      }
    }
    return null;
  }

  Set<String> _collectKnownPersonNames({
    required PersonProfile profile,
    required ExtractedPersonDraft draft,
  }) {
    return <String>{
      profile.name,
      draft.name,
      ...profile.aliases,
      ...draft.aliases,
    }..removeWhere((name) => name.trim().isEmpty);
  }

  List<String> _buildMergedAliases({
    required String primaryName,
    required Set<String> primaryKnownNames,
    required Set<String> secondaryKnownNames,
  }) {
    final aliases = <String>[];
    final seen = <String>{};

    for (final name in [...primaryKnownNames, ...secondaryKnownNames]) {
      final normalized = name.trim();
      if (normalized.isEmpty || normalized == primaryName) {
        continue;
      }
      if (seen.add(normalized)) {
        aliases.add(normalized);
      }
    }

    return aliases;
  }

  List<String> _buildRenamedAliases({
    required String nextName,
    required Set<String> knownNames,
    required Set<String> originalNames,
    required bool keepOriginalNameAsAlias,
  }) {
    final aliases = <String>[];
    final seen = <String>{};

    for (final name in knownNames) {
      final normalized = name.trim();
      if (normalized.isEmpty || normalized == nextName) {
        continue;
      }
      if (!keepOriginalNameAsAlias && originalNames.contains(normalized)) {
        continue;
      }
      if (seen.add(normalized)) {
        aliases.add(normalized);
      }
    }

    return aliases;
  }

  List<String> _mergePersonNames(
    List<String> personNames, {
    required Set<String> mergedKnownNames,
    required String primaryName,
  }) {
    if (personNames.isEmpty) {
      return const [];
    }

    final nextNames = <String>[];
    final seen = <String>{};

    for (final name in personNames) {
      final normalized = name.trim();
      final mappedName = mergedKnownNames.contains(normalized)
          ? primaryName
          : normalized;
      if (mappedName.isEmpty) {
        continue;
      }
      if (seen.add(mappedName)) {
        nextNames.add(mappedName);
      }
    }

    return nextNames;
  }

  List<int> _collectTaskIndexesForPerson(
    List<ExtractedTaskDraft> tasks,
    String personName,
  ) {
    final indexes = <int>[];

    for (var index = 0; index < tasks.length; index++) {
      if (tasks[index].relatedPersonNames.contains(personName)) {
        indexes.add(index);
      }
    }

    return indexes;
  }

  bool _hasPersonNameConflict({
    required List<PersonProfile> people,
    required String personId,
    required String candidateName,
  }) {
    for (final person in people) {
      if (person.id == personId) {
        continue;
      }
      if (person.name == candidateName ||
          person.aliases.contains(candidateName)) {
        return true;
      }
    }
    return false;
  }

  PersonRole _resolveMergedPersonRole(
    PersonRole primaryRole,
    PersonRole secondaryRole,
  ) {
    if (primaryRole != PersonRole.other) {
      return primaryRole;
    }
    return secondaryRole;
  }

  String _buildDraftSummary(
    List<ExtractedTaskDraft> tasks,
    List<ExtractedPersonDraft> people,
  ) {
    if (tasks.isEmpty) {
      return '当前描述信息较少，暂时无法总结出稳定的本周进展。';
    }

    final categories = tasks
        .map((task) => task.category.label)
        .toSet()
        .toList();
    final categoryText = categories.isEmpty
        ? ''
        : '，覆盖 ${categories.join('、')}';
    final peopleText = people.isEmpty ? '未识别到明确人物' : '涉及 ${people.length} 位人物';
    return '本次分析共识别出 ${tasks.length} 条事项，$peopleText$categoryText。';
  }

  DateTime _resolveDate(ExtractedTaskDraft task, DateTime anchor, int index) {
    if (task.type == EventType.plan) {
      final hint = task.timeHint;
      if (hint != null) {
        final weekday = switch (hint) {
          '下周一' || '周一' => DateTime.monday,
          '下周二' || '周二' => DateTime.tuesday,
          '下周三' || '周三' => DateTime.wednesday,
          '下周四' || '周四' => DateTime.thursday,
          '下周五' || '周五' => DateTime.friday,
          '下周六' || '周六' => DateTime.saturday,
          '下周日' || '下周末' || '周日' || '周末' => DateTime.sunday,
          _ => null,
        };
        final isNextWeekHint = hint.startsWith('下周');

        if (weekday != null) {
          return isNextWeekHint
              ? _nextWeekSpecificWeekday(anchor, weekday)
              : _nextWeekday(anchor, weekday);
        }
        if (hint == '明天') {
          return anchor.add(const Duration(days: 1));
        }
        if (hint == '后天') {
          return anchor.add(const Duration(days: 2));
        }
        if (hint == '下周') {
          return anchor.add(const Duration(days: 7));
        }
      }

      return anchor.add(Duration(days: index + 1));
    }

    return anchor.subtract(Duration(days: index % 5));
  }

  List<String> _collectUniquePeople(List<EventItem> events) {
    final people = <String>[];
    final seen = <String>{};

    for (final event in events) {
      for (final person in event.personNames) {
        if (seen.add(person)) {
          people.add(person);
        }
      }
    }

    return people;
  }

  String _formatPromptEventList(
    List<EventItem> events, {
    bool includeMeta = false,
  }) {
    if (events.isEmpty) {
      return '无';
    }

    return events
        .map((event) {
          final collaboratorSuffix = event.personNames.isEmpty
              ? ''
              : '（协作：${event.personNames.join('、')}）';

          if (!includeMeta) {
            return '- ${_formatEventDateRange(event)}：${event.title}$collaboratorSuffix';
          }

          return '- ${_formatEventDateRange(event)}｜${event.type.label}｜'
              '${event.category.label}｜${event.title}$collaboratorSuffix';
        })
        .join('\n');
  }

  String _formatPeopleList(List<String> people) {
    if (people.isEmpty) {
      return '无';
    }

    return people.map((person) => '- $person').join('\n');
  }

  String _formatMonthDay(DateTime date) {
    return '${date.month}/${date.day}';
  }

  String _formatEventDateRange(EventItem event) {
    final end = event.endAt;
    if (end == null || _sameDay(event.startAt, end)) {
      return _formatMonthDay(event.startAt);
    }
    return '${_formatMonthDay(event.startAt)} - ${_formatMonthDay(end)}';
  }

  bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  DateTime _nextWeekday(DateTime from, int targetWeekday) {
    var candidate = from.add(const Duration(days: 1));
    while (candidate.weekday != targetWeekday) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return DateTime(candidate.year, candidate.month, candidate.day, 14);
  }

  DateTime _nextWeekSpecificWeekday(DateTime from, int targetWeekday) {
    final startOfDay = DateTime(from.year, from.month, from.day);
    final currentWeekMonday = startOfDay.subtract(
      Duration(days: startOfDay.weekday - DateTime.monday),
    );
    final nextWeekMonday = currentWeekMonday.add(const Duration(days: 7));
    final targetDate = nextWeekMonday.add(
      Duration(days: targetWeekday - DateTime.monday),
    );
    return DateTime(targetDate.year, targetDate.month, targetDate.day, 14);
  }

  Future<void> _ensureReadme(Directory folder) async {
    final readme = File('${folder.path}${Platform.pathSeparator}README.txt');
    if (await readme.exists()) {
      return;
    }

    await readme.writeAsString('''
研究生活主页图片文件夹
这个文件夹位于应用数据目录下。
支持的命名方式：
- research_wall.png / .jpg / .jpeg / .webp / .bmp
- life_wall.png / .jpg / .jpeg / .webp / .bmp
''');
  }

  Future<void> _migrateLegacyHomeImageFolderIfNeeded(
    Directory storageDirectory,
    Directory targetFolder,
  ) async {
    if (await targetFolder.exists()) {
      return;
    }

    final legacyFolder = Directory(
      '${storageDirectory.path}${Platform.pathSeparator}home_images',
    );
    if (!await legacyFolder.exists()) {
      return;
    }

    try {
      await legacyFolder.rename(targetFolder.path);
    } on FileSystemException {
      await _copyDirectory(legacyFolder, targetFolder);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);

    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
      if (name.isEmpty) {
        continue;
      }

      final targetPath = '${target.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  Future<List<File>> _existingSlotFiles(HomeImageSlot slot) async {
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return const [];
    }

    final files = <File>[];
    for (final extension in _supportedImageExtensions) {
      final file = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension',
      );
      if (await file.exists()) {
        files.add(file);
      }
    }
    return files;
  }

  Future<void> _restoreSlotReplacement(
    HomeImageSlot slot,
    String backupSuffix,
  ) async {
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return;
    }

    for (final extension in _supportedImageExtensions) {
      final incoming = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.incoming.$extension',
      );
      if (await incoming.exists()) {
        await incoming.delete();
      }

      final target = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension',
      );
      final backupFile = File('${target.path}$backupSuffix');
      if (await backupFile.exists()) {
        if (await target.exists()) {
          await target.delete();
        }
        await backupFile.rename(target.path);
      }
    }
  }

  Future<String?> _findImageForSlot(HomeImageSlot slot) async {
    final folderPath = _homeImageFolderPath;
    if (folderPath == null) {
      return null;
    }

    for (final extension in _supportedImageExtensions) {
      final file = File(
        '$folderPath${Platform.pathSeparator}${slot.fileBaseName}.$extension',
      );
      if (await file.exists()) {
        return file.path;
      }
    }

    return null;
  }

  String _extensionOf(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) {
      return 'png';
    }
    return path.substring(dotIndex + 1).toLowerCase();
  }

  Future<String?> _openFolder(String path, String label) async {
    try {
      await Process.start('explorer.exe', [path]);
      return '已打开$label。';
    } on ProcessException catch (error) {
      return '打开$label失败：${error.message}';
    }
  }

  void _replaceSessionRecord(SessionRecord updatedSession) {
    final index = _sessionHistory.indexWhere(
      (item) => item.id == updatedSession.id,
    );
    if (index != -1) {
      _sessionHistory[index] = updatedSession;
    }

    if (_latestSession?.id == updatedSession.id) {
      _latestSession = updatedSession;
    }
    if (_currentDraft?.id == updatedSession.draft.id) {
      _currentDraft = updatedSession.draft;
      _currentPreview = updatedSession.preview;
    }
  }

  double _normalizeFraction(double value) {
    return value.clamp(0.0, 1.0).toDouble();
  }

  static List<CampusPlace> _buildSampleCampusPlaces() {
    final now = DateTime.now();
    return [
      CampusPlace(
        id: 'place_library',
        name: '主图书馆',
        category: PlaceCategory.study,
        note: '适合安静自习，二层靠窗的位置采光最好。',
        normalizedDx: 0.34,
        normalizedDy: 0.28,
        iconKey: 'book',
        colorKey: 'forest',
        isFavorite: true,
        createdAt: now.subtract(const Duration(days: 18)),
        updatedAt: now.subtract(const Duration(days: 2)),
        lastVisitedAt: now.subtract(const Duration(hours: 6)),
        heatScore: 12,
      ),
      CampusPlace(
        id: 'place_canteen',
        name: '一食堂',
        category: PlaceCategory.dining,
        note: '中午排队较快，靠北侧窗口常有盖饭。',
        normalizedDx: 0.67,
        normalizedDy: 0.33,
        iconKey: 'food',
        colorKey: 'amber',
        isFavorite: true,
        createdAt: now.subtract(const Duration(days: 12)),
        updatedAt: now.subtract(const Duration(days: 1)),
        lastVisitedAt: now.subtract(const Duration(hours: 20)),
        heatScore: 8,
      ),
      CampusPlace(
        id: 'place_dorm',
        name: '南宿舍 A 栋',
        category: PlaceCategory.dormitory,
        note: '快递柜和洗衣房都在楼下，晚上回宿舍路线最顺。',
        normalizedDx: 0.21,
        normalizedDy: 0.76,
        iconKey: 'bed',
        colorKey: 'slate',
        createdAt: now.subtract(const Duration(days: 24)),
        updatedAt: now.subtract(const Duration(days: 4)),
        lastVisitedAt: now.subtract(const Duration(hours: 10)),
        heatScore: 15,
      ),
      CampusPlace(
        id: 'place_lab',
        name: '材料实验楼',
        category: PlaceCategory.lab,
        note: '三层东侧实验室需要提前登记，晚上刷卡后可进入。',
        normalizedDx: 0.53,
        normalizedDy: 0.58,
        iconKey: 'flask',
        colorKey: 'berry',
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 1)),
        lastVisitedAt: now.subtract(const Duration(days: 1, hours: 3)),
        heatScore: 9,
      ),
      CampusPlace(
        id: 'place_gym',
        name: '体育馆',
        category: PlaceCategory.sports,
        note: '羽毛球场需要提前预约，晚间照明稳定。',
        normalizedDx: 0.8,
        normalizedDy: 0.74,
        iconKey: 'run',
        colorKey: 'teal',
        createdAt: now.subtract(const Duration(days: 14)),
        updatedAt: now.subtract(const Duration(days: 3)),
        heatScore: 5,
      ),
      CampusPlace(
        id: 'place_service',
        name: '行政服务中心',
        category: PlaceCategory.errands,
        note: '补办校园卡、打印证明都在这里，工作日人流较多。',
        normalizedDx: 0.48,
        normalizedDy: 0.18,
        iconKey: 'office',
        colorKey: 'blue',
        isMine: false,
        createdAt: now.subtract(const Duration(days: 7)),
        updatedAt: now.subtract(const Duration(days: 2)),
        heatScore: 3,
      ),
    ];
  }
}
