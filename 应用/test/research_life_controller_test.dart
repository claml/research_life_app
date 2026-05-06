import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/campus_places_repository.dart';
import 'package:research_life/services/database/repositories/manual_events_repository.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/database/repositories/sessions_repository.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ResearchLifeController', () {
    test('returns a clear message for empty analysis input', () async {
      final controller = await _createController();

      controller.inputController.text = '   ';
      final message = controller.analyzeCurrentInput();

      expect(message, contains('请先输入一段周描述'));
      expect(controller.currentDraft, isNull);
      expect(controller.currentPreview, isNull);
    });

    test('does not confirm before analysis has produced a draft', () async {
      final controller = await _createController();

      final message = controller.confirmDraft();

      expect(message, '当前还没有可以确认的分析结果。');
      expect(controller.sessionHistory, isEmpty);
      expect(controller.calendarEvents, isEmpty);
    });

    test('aggregates calendar events across confirmed sessions', () async {
      final controller = await _createController();

      controller.inputController.text = '这周完成论文整理。';
      controller.analyzeCurrentInput();
      controller.confirmDraft();

      controller.inputController.text = '这周完成实验记录。';
      controller.analyzeCurrentInput();
      controller.confirmDraft();

      expect(controller.sessionHistory, hasLength(2));
      expect(
        controller.calendarEvents.length,
        controller.sessionHistory[0].events.length +
            controller.sessionHistory[1].events.length,
      );
      expect(
        controller.calendarEvents.map((event) => event.id).toSet(),
        hasLength(controller.calendarEvents.length),
      );
    });

    test(
      'keeps weekly analysis sync behavior through composed analysis controller',
      () async {
        final controller = await _createController();
        final analysisController = controller.analysisController;

        analysisController.updateInputText('这周和王老师讨论论文，下周二准备继续开会。');
        analysisController.analyzeCurrentInput();
        final message = analysisController.confirmDraft();

        expect(message, '分析结果已确认，已同步到主页、人物关系和历史记录。');
        expect(controller.currentPreview, same(analysisController.preview));
        expect(controller.sessionHistory, hasLength(1));
        expect(controller.calendarEvents, hasLength(2));
        expect(
          controller.latestSession?.people.map((person) => person.name),
          contains('王老师'),
        );
      },
    );

    test('deduplicates repeated analysis events in calendar', () async {
      final controller = await _createController();

      controller.inputController.text = '下周二准备和导师开会确认论文框架。';
      controller.analyzeCurrentInput();
      controller.confirmDraft();

      controller.inputController.text = '下周二准备和导师开会确认论文框架。';
      controller.analyzeCurrentInput();
      final message = controller.confirmDraft();

      expect(message, '已更新同一天或本周已有的周分析上传记录。');
      expect(controller.sessionHistory, hasLength(1));
      expect(controller.calendarEvents, hasLength(1));
      expect(controller.calendarEvents.single.title, '下周二准备和导师开会确认论文框架');
    });

    test('loads an existing weekly analysis upload for editing', () async {
      final controller = await _createController();

      controller.inputController.text = '这周完成论文整理。';
      controller.analyzeCurrentInput();
      controller.confirmDraft();

      final sessionId = controller.latestSession!.id;
      final loadMessage = controller.loadSessionForEditing(sessionId);

      expect(loadMessage, contains('已载入'));
      expect(controller.editingSession?.id, sessionId);
      expect(controller.inputController.text, '这周完成论文整理。');

      controller.inputController.text = '这周完成实验记录。';
      controller.analyzeCurrentInput();
      final saveMessage = controller.confirmDraft();

      expect(saveMessage, '已更新同一天或本周已有的周分析上传记录。');
      expect(controller.sessionHistory, hasLength(1));
      expect(controller.latestSession!.id, sessionId);
      expect(controller.latestSession!.input.rawText, '这周完成实验记录。');
      expect(controller.editingSession, isNull);
      expect(controller.calendarEvents.single.title, '这周完成实验记录');
    });

    test('deletes a confirmed analysis session from derived views', () async {
      final controller = await _createController();

      controller.inputController.text = '这周和王老师讨论论文。';
      controller.analyzeCurrentInput();
      controller.confirmDraft();

      final sessionId = controller.latestSession!.id;
      final message = controller.deleteSessionRecord(sessionId);

      expect(message, '已删除历史记录，并移除相关人物、待办和规划事件。');
      expect(controller.sessionHistory, isEmpty);
      expect(controller.latestSession, isNull);
      expect(controller.calendarEvents, isEmpty);
      expect(controller.currentDraft, isNull);
      expect(controller.currentPreview, isNull);
      expect(controller.inputController.text, isEmpty);
    });
    test(
      'updates owning historical session when editing an analysis event',
      () async {
        final controller = await _createController();

        controller.inputController.text = '这周完成论文整理。';
        controller.analyzeCurrentInput();
        controller.confirmDraft();

        controller.inputController.text = '这周完成实验记录。';
        controller.analyzeCurrentInput();
        controller.confirmDraft();

        final oldestSessionBefore = controller.sessionHistory.last;
        final message = controller.updateEditableEvent(
          eventId: oldestSessionBefore.events.first.id,
          title: '下周准备和导师开会',
          category: ItemCategory.work,
          type: EventType.plan,
        );

        final oldestSessionAfter = controller.sessionHistory.last;
        expect(message, '已更新记录。');
        expect(oldestSessionAfter.events.first.title, '下周准备和导师开会');
        expect(oldestSessionAfter.preview.completedTasks, isEmpty);
        expect(oldestSessionAfter.preview.plannedTasks, hasLength(1));
        expect(controller.latestSession?.title, '第 2 次分析');
      },
    );

    test(
      'renames person inside non-latest session without changing latest session',
      () async {
        final controller = await _createController();

        controller.inputController.text = '这周和王老师开会讨论论文。';
        controller.analyzeCurrentInput();
        controller.confirmDraft();

        controller.inputController.text = '这周和陈同学讨论实验安排。';
        controller.analyzeCurrentInput();
        controller.confirmDraft();

        final oldestSessionBefore = controller.sessionHistory.last;
        final personId = oldestSessionBefore.people.first.id;

        final message = controller.renamePerson(
          personId: personId,
          nextName: '李老师',
        );

        final oldestSessionAfter = controller.sessionHistory.last;
        expect(message, '已将人物称谓更新为“李老师”。');
        expect(
          oldestSessionAfter.people.map((person) => person.name),
          contains('李老师'),
        );
        expect(
          controller.latestSession?.people
                  .map((person) => person.name)
                  .toList() ??
              const <String>[],
          isNot(contains('李老师')),
        );
      },
    );

    test(
      'freezes relative time against analysis draft creation time',
      () async {
        final controller = await _createController();

        controller.inputController.text = '明天和导师开会确认论文。';
        controller.analyzeCurrentInput();

        final analyzedDraft = controller.currentDraft!;
        controller.confirmDraft();

        final latestSession = controller.latestSession!;
        expect(
          latestSession.events.first.startAt,
          analyzedDraft.createdAt.add(const Duration(days: 1)),
        );
      },
    );

    test(
      'spans this-week records without a specific day on calendar',
      () async {
        final controller = await _createController();

        controller.inputController.text = '这周我完成了论文第二章的资料整理。';
        controller.analyzeCurrentInput();

        final analyzedDraft = controller.currentDraft!;
        controller.confirmDraft();

        final anchor = analyzedDraft.createdAt;
        final expectedEnd = DateTime(anchor.year, anchor.month, anchor.day);
        final expectedStart = expectedEnd.subtract(
          Duration(days: anchor.weekday - DateTime.monday),
        );
        final event = controller.calendarEvents.single;

        expect(event.title, '这周我完成了论文第二章的资料整理');
        expect(event.startAt, expectedStart);
        expect(event.endAt, expectedEnd);
      },
    );

    test('builds weekly report prompt with sorted events and counts', () async {
      final controller = await _createController();

      final prompt = controller.buildWeeklyReportPrompt(
        start: DateTime(2025, 12, 29),
        end: DateTime(2026, 1, 4),
        rangeEvents: [
          EventItem(
            id: 'plan_late',
            title: '下周准备和导师开会',
            category: ItemCategory.work,
            type: EventType.plan,
            startAt: DateTime(2026, 1, 4),
            personNames: ['导师'],
          ),
          EventItem(
            id: 'record_early',
            title: '完成论文整理',
            category: ItemCategory.work,
            type: EventType.record,
            startAt: DateTime(2025, 12, 29),
            personNames: ['王老师'],
          ),
          EventItem(
            id: 'record_mid',
            title: '跑步五公里',
            category: ItemCategory.health,
            type: EventType.record,
            startAt: DateTime(2025, 12, 31),
            personNames: ['王老师'],
          ),
        ],
        templateOverride: '''
日期={{date_range}}
完成={{record_count}}
计划={{plan_count}}
人物={{people_count}}
已完成:
{{completed_items}}
待计划:
{{planned_items}}
人物:
{{people}}
全部:
{{all_events}}
''',
      );

      expect(prompt, contains('日期=12/29 - 1/4'));
      expect(prompt, contains('完成=2'));
      expect(prompt, contains('计划=1'));
      expect(prompt, contains('人物=2'));
      expect(prompt, contains('- 12/29：完成论文整理（协作：王老师）'));
      expect(prompt, contains('- 12/31：跑步五公里（协作：王老师）'));
      expect(prompt, contains('- 1/4：下周准备和导师开会（协作：导师）'));
      expect(prompt, contains('12/29｜记录｜工作｜完成论文整理'));
      expect(prompt, contains('1/4｜计划｜工作｜下周准备和导师开会'));
      expect(
        prompt.indexOf('12/29：完成论文整理'),
        lessThan(prompt.indexOf('12/31：跑步五公里')),
      );
    });

    test('builds weekly report prompt with empty event lists', () async {
      final controller = await _createController();

      final prompt = controller.buildWeeklyReportPrompt(
        start: DateTime(2026, 4, 20),
        end: DateTime(2026, 4, 26),
        rangeEvents: const [],
        templateOverride:
            '{{date_range}}|{{record_count}}|{{plan_count}}|{{people_count}}|{{completed_items}}|{{planned_items}}|{{people}}|{{all_events}}',
      );

      expect(prompt, '4/20 - 4/26|0|0|0|无|无|无|无');
    });

    test('loads confirmed sessions from sqlite on startup', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_session_persistence_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final sessionsRepository = SessionsRepository(database);
      final workspaceService = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final firstController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        sessionsRepository: sessionsRepository,
      );
      addTearDown(firstController.dispose);

      firstController.inputController.text = '这周完成论文整理。';
      firstController.analyzeCurrentInput();
      firstController.confirmDraft();
      await firstController.waitForPendingSessionPersistence();

      final secondController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        sessionsRepository: sessionsRepository,
      );
      addTearDown(secondController.dispose);

      await secondController.ensureSessionHistoryLoaded();

      expect(secondController.sessionHistory, hasLength(1));
      expect(secondController.latestSession?.title, '第 1 次分析');
      expect(secondController.calendarEvents, hasLength(1));
    });

    test('persists confirmed session deletion to sqlite', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_session_delete_persistence_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final sessionsRepository = SessionsRepository(database);
      final workspaceService = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final firstController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        sessionsRepository: sessionsRepository,
      );
      addTearDown(firstController.dispose);

      firstController.inputController.text = '这周完成论文整理。';
      firstController.analyzeCurrentInput();
      firstController.confirmDraft();
      final sessionId = firstController.latestSession!.id;
      await firstController.waitForPendingSessionPersistence();

      firstController.deleteSessionRecord(sessionId);
      await firstController.waitForPendingSessionPersistence();

      final secondController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        sessionsRepository: sessionsRepository,
      );
      addTearDown(secondController.dispose);

      await secondController.ensureSessionHistoryLoaded();

      expect(secondController.sessionHistory, isEmpty);
      expect(secondController.calendarEvents, isEmpty);
      expect(await database.select(database.sessions).get(), isEmpty);
      expect(await database.select(database.events).get(), isEmpty);
      expect(await database.select(database.persons).get(), isEmpty);
      expect(await database.select(database.eventPersons).get(), isEmpty);
    });

    test('persists institution calendar imports as editable history', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_calendar_persistence_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final sessionsRepository = SessionsRepository(database);
      final workspaceService = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final firstController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        sessionsRepository: sessionsRepository,
      );
      addTearDown(firstController.dispose);

      const rawCalendar = '''
CALENDAR_IMPORT_V1
TITLE: 测试大学 2026 学年校历
2026-02-23 | 2026-03-01 | 寒假 | life | plan
2026-03-02 | 2026-07-10 | 春季学期 | study | plan
''';

      final importMessage = firstController.importInstitutionCalendar(
        rawCalendar,
      );
      await firstController.waitForPendingSessionPersistence();

      expect(importMessage, contains('已保存到历史记录'));
      expect(firstController.sessionHistory, hasLength(1));
      expect(firstController.sessionHistory.single.isInstitutionCalendar, true);
      expect(firstController.institutionCalendarEvents, hasLength(2));
      expect(firstController.calendarEvents, hasLength(2));

      final secondController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        sessionsRepository: sessionsRepository,
      );
      addTearDown(secondController.dispose);

      await secondController.ensureSessionHistoryLoaded();

      expect(secondController.sessionHistory, hasLength(1));
      expect(secondController.latestSession, isNull);
      expect(secondController.institutionCalendarTitle, '测试大学 2026 学年校历');
      expect(secondController.institutionCalendarEvents, hasLength(2));
      expect(
        secondController.calendarEvents.first.origin,
        EventOrigin.institutionCalendar,
      );
    });

    test('edits and deletes institution calendar history records', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_calendar_edit_delete_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final sessionsRepository = SessionsRepository(database);
      final workspaceService = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final controller = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        sessionsRepository: sessionsRepository,
      );
      addTearDown(controller.dispose);

      const originalCalendar = '''
CALENDAR_IMPORT_V1
TITLE: 测试大学 2026 学年校历
2026-02-23 | 2026-03-01 | 寒假 | life | plan
''';
      const updatedCalendar = '''
CALENDAR_IMPORT_V1
TITLE: 测试大学 2026 学年校历
2026-03-02 | 2026-07-10 | 春季学期 | study | plan
2026-06-15 | 2026-06-21 | 期末考试周 | study | plan
''';

      controller.importInstitutionCalendar(originalCalendar);
      await controller.waitForPendingSessionPersistence();
      final sessionId = controller.sessionHistory.single.id;

      final loadMessage = controller.loadInstitutionCalendarForEditing(
        sessionId,
      );
      expect(loadMessage, contains('已载入'));
      expect(
        controller.editingInstitutionCalendarText,
        originalCalendar.trim(),
      );

      final updateMessage = controller.importInstitutionCalendar(
        updatedCalendar,
      );
      await controller.waitForPendingSessionPersistence();

      expect(updateMessage, contains('已更新校历导入记录'));
      expect(controller.sessionHistory, hasLength(1));
      expect(controller.sessionHistory.single.id, sessionId);
      expect(controller.institutionCalendarEvents, hasLength(2));
      expect(controller.institutionCalendarEvents.first.title, '春季学期');
      expect(controller.editingInstitutionCalendarSessionId, isNull);

      final deleteMessage = controller.deleteSessionRecord(sessionId);
      await controller.waitForPendingSessionPersistence();

      expect(deleteMessage, contains('已删除校历导入记录'));
      expect(controller.sessionHistory, isEmpty);
      expect(controller.institutionCalendarEvents, isEmpty);
      expect(controller.calendarEvents, isEmpty);
      expect(await database.select(database.sessions).get(), isEmpty);
      expect(await database.select(database.events).get(), isEmpty);
    });

    test('loads manual events from sqlite on startup', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_manual_event_persistence_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final manualEventsRepository = ManualEventsRepository(database);
      final workspaceService = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final firstController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        manualEventsRepository: manualEventsRepository,
      );
      addTearDown(firstController.dispose);

      firstController.addManualEvent(
        date: DateTime(2026, 4, 26),
        title: '写周报',
        category: ItemCategory.work,
        type: EventType.plan,
      );
      await firstController.waitForPendingManualEventPersistence();

      final secondController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        manualEventsRepository: manualEventsRepository,
      );
      addTearDown(secondController.dispose);

      await secondController.ensureManualEventsLoaded();

      expect(secondController.manualEvents, hasLength(1));
      expect(secondController.manualEvents.single.title, '写周报');
      expect(secondController.calendarEvents, hasLength(1));
    });

    test('seeds default campus places only once', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_campus_places_seed_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final campusPlacesRepository = CampusPlacesRepository(database);
      final workspaceService = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final firstController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        campusPlacesRepository: campusPlacesRepository,
      );
      addTearDown(firstController.dispose);

      await firstController.ensureCampusPlacesLoaded();

      expect(firstController.campusPlaces, isNotEmpty);
      expect(await campusPlacesRepository.hasSeededDefaults(), isTrue);

      for (final place in firstController.campusPlaces.toList()) {
        firstController.deleteCampusPlace(place.id);
      }
      await firstController.waitForPendingCampusPlacePersistence();

      final secondController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        campusPlacesRepository: campusPlacesRepository,
      );
      addTearDown(secondController.dispose);

      await secondController.ensureCampusPlacesLoaded();

      expect(secondController.campusPlaces, isEmpty);
    });

    test('persists campus place updates across controller restart', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_campus_places_update_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final campusPlacesRepository = CampusPlacesRepository(database);
      final workspaceService = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDir,
      );
      final firstController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        campusPlacesRepository: campusPlacesRepository,
      );
      addTearDown(firstController.dispose);
      await firstController.ensureCampusPlacesLoaded();

      final place = firstController.createCampusPlace(
        name: '新地点',
        category: PlaceCategory.lab,
        note: '实验记录',
        normalizedDx: 0.2,
        normalizedDy: 0.3,
        iconKey: 'flask',
        colorKey: 'berry',
      );
      firstController.toggleCampusPlaceFavorite(place.id);
      firstController.markCampusPlaceVisited(place.id);
      await firstController.waitForPendingCampusPlacePersistence();

      final secondController = ResearchLifeController(
        importService: const ImportService(),
        analysisService: const AnalysisService(),
        reviewService: const ReviewService(),
        institutionCalendarService: const InstitutionCalendarService(),
        localWorkspaceService: workspaceService,
        campusPlacesRepository: campusPlacesRepository,
      );
      addTearDown(secondController.dispose);

      await secondController.ensureCampusPlacesLoaded();
      final restoredPlace = secondController.campusPlaceById(place.id);

      expect(restoredPlace, isNotNull);
      expect(restoredPlace!.name, '新地点');
      expect(restoredPlace.isFavorite, isTrue);
      expect(restoredPlace.heatScore, 1);
      expect(restoredPlace.lastVisitedAt, isNotNull);
    });

    test(
      'migrates weekly prompt template from legacy json to sqlite repository',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'research_life_controller_preferences_migration_test',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final workspaceService = LocalWorkspaceService(
          storageDirectoryResolver: () async => tempDir,
        );
        await workspaceService.saveWeeklyPromptTemplate('legacy template');

        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final preferencesRepository = PreferencesRepository(database);
        final controller = ResearchLifeController(
          importService: const ImportService(),
          analysisService: const AnalysisService(),
          reviewService: const ReviewService(),
          institutionCalendarService: const InstitutionCalendarService(),
          localWorkspaceService: workspaceService,
          preferencesRepository: preferencesRepository,
        );
        addTearDown(controller.dispose);

        await controller.ensureWeeklyPromptTemplateLoaded();

        expect(controller.weeklyPromptTemplate, 'legacy template');
        expect(
          await preferencesRepository.loadWeeklyPromptTemplate(),
          'legacy template',
        );
      },
    );

    test(
      'keeps weekly prompt template unchanged when saving blank text',
      () async {
        final controller = await _createController();
        final previousTemplate = controller.weeklyPromptTemplate;

        final message = await controller.saveWeeklyPromptTemplate('  \n ');

        expect(message, '常用提示词模板不能为空。');
        expect(controller.weeklyPromptTemplate, previousTemplate);
      },
    );

    test('persists local LLM analysis settings through preferences', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'research_life_controller_local_llm_settings_test',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final preferencesRepository = PreferencesRepository(database);

      ResearchLifeController createController() {
        final controller = ResearchLifeController(
          importService: const ImportService(),
          analysisService: const AnalysisService(),
          reviewService: const ReviewService(),
          institutionCalendarService: const InstitutionCalendarService(),
          localWorkspaceService: LocalWorkspaceService(
            storageDirectoryResolver: () async => tempDir,
          ),
          preferencesRepository: preferencesRepository,
        );
        addTearDown(controller.dispose);
        return controller;
      }

      final firstController = createController();
      const settings = LocalLlmAnalysisSettings(
        enableLocalLlmAnalysis: true,
        ollamaBaseUrl: 'http://localhost:11434',
        ollamaModel: 'qwen3:8b',
        ollamaTimeoutSeconds: 90,
        fallbackToRules: false,
        strictJsonSchema: true,
      );

      final message = await firstController.saveLocalLlmAnalysisSettings(
        settings,
      );

      expect(message, '本地 LLM 周分析设置已保存。');
      final stored = await preferencesRepository.loadLocalLlmAnalysisSettings();
      expect(stored, isNotNull);
      expect(jsonDecode(stored!)['ollamaModel'], 'qwen3:8b');

      final secondController = createController();
      await secondController.ensureLocalLlmAnalysisSettingsLoaded();

      expect(
        secondController.localLlmAnalysisSettings.enableLocalLlmAnalysis,
        isTrue,
      );
      expect(
        secondController.localLlmAnalysisSettings.ollamaBaseUrl,
        'http://localhost:11434',
      );
      expect(
        secondController.localLlmAnalysisSettings.ollamaModel,
        LocalLlmAnalysisSettings.defaultOllamaModel,
      );
      expect(
        secondController.localLlmAnalysisSettings.ollamaTimeoutSeconds,
        90,
      );
      expect(
        secondController.localLlmAnalysisSettings.fallbackToRules,
        isFalse,
      );
      expect(
        secondController.localLlmAnalysisSettings.strictJsonSchema,
        isTrue,
      );
    });

    test('keeps existing home image when replacement copy fails', () async {
      final controller = await _createController();
      await controller.ensureHomeGalleryReady();

      final homeImageFolder = controller.homeImageFolderPath!;
      final existingImage = File(
        '$homeImageFolder${Platform.pathSeparator}research_wall.png',
      );
      await existingImage.writeAsBytes(const [1, 2, 3]);

      final message = await controller.replaceHomeImageFromPath(
        HomeImageSlot.researchWall,
        '$homeImageFolder${Platform.pathSeparator}missing.png',
      );

      expect(message, contains('替换图片失败'));
      expect(await existingImage.exists(), isTrue);
    });
  });
}

Future<ResearchLifeController> _createController() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'research_life_controller_test',
  );
  addTearDown(() => tempDir.delete(recursive: true));

  final controller = ResearchLifeController(
    importService: const ImportService(),
    analysisService: const AnalysisService(),
    reviewService: const ReviewService(),
    institutionCalendarService: const InstitutionCalendarService(),
    localWorkspaceService: LocalWorkspaceService(
      storageDirectoryResolver: () async => tempDir,
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}
