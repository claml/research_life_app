import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/core/utils/workspace_file_kind.dart';
import 'package:research_life/services/search/global_search_service.dart';

PdfLibraryDocument _doc({
  required String id,
  required String title,
  String path = r'D:\资料\论文.pdf',
  WorkspaceFileKind fileKind = WorkspaceFileKind.pdf,
  bool isDeleted = false,
}) {
  return PdfLibraryDocument(
    id: id,
    title: title,
    path: path,
    createdAt: DateTime(2026, 4, 26),
    updatedAt: DateTime(2026, 4, 26),
    fileKind: fileKind,
    isDeleted: isDeleted,
  );
}

EventItem _event({
  required String id,
  required String title,
  EventType type = EventType.plan,
  DateTime? startAt,
  ItemCategory category = ItemCategory.study,
  List<String> personNames = const [],
}) {
  return EventItem(
    id: id,
    title: title,
    category: category,
    type: type,
    startAt: startAt ?? DateTime(2026, 4, 26),
    personNames: personNames,
  );
}

SessionRecord _session({
  required String id,
  required String title,
  String summary = '',
  List<PersonProfile> people = const [],
}) {
  return SessionRecord(
    id: id,
    title: title,
    input: AnalysisInput(rawText: '', sourceType: AnalysisSourceType.text),
    draft: AnalysisDraft(
      id: 'draft_$id',
      tasks: const [],
      persons: const [],
      summary: '',
      warnings: const [],
      createdAt: DateTime(2026, 4, 26),
    ),
    preview: ReviewPreview(
      id: 'preview_$id',
      completedTasks: const [],
      plannedTasks: const [],
      persons: const [],
      summary: summary,
      warnings: const [],
      relationLabels: const [],
    ),
    events: const [],
    people: people,
    confirmedAt: DateTime(2026, 4, 26),
  );
}

CampusPlace _place({
  required String id,
  required String name,
  String note = '',
  PlaceCategory category = PlaceCategory.lab,
}) {
  return CampusPlace(
    id: id,
    name: name,
    category: category,
    note: note,
    normalizedDx: 0.5,
    normalizedDy: 0.5,
    iconKey: 'flask',
    colorKey: 'blue',
    createdAt: DateTime(2026, 4, 26),
    updatedAt: DateTime(2026, 4, 26),
  );
}

void main() {
  final documents = [
    _doc(id: 'doc_1', title: '深度学习综述'),
    _doc(id: 'doc_2', title: '神经网络原理'),
    _doc(id: 'doc_hidden', title: '隐藏文献', isDeleted: true),
  ];

  final events = [
    _event(id: 'e1', title: '和王老师讨论论文框架', personNames: const ['王老师']),
    _event(
      id: 'e2',
      title: '完成实验记录',
      type: EventType.record,
      category: ItemCategory.life,
    ),
  ];

  final sessions = [
    _session(
      id: 's1',
      title: '2026/4/20 - 4/26 周分析',
      summary: '本周完成文献阅读并和导师沟通',
      people: const [
        PersonProfile(
          id: 'p1',
          name: '王老师',
          role: PersonRole.teacher,
          aliases: ['王教授'],
          relatedTaskCount: 3,
          relatedPlanTitles: [],
        ),
      ],
    ),
  ];

  final places = [_place(id: 'pl1', name: '信息楼 3 号实验室', note: '深度学习组')];

  group('GlobalSearchService.search', () {
    test('returns empty for blank query', () {
      final results = GlobalSearchService.search(
        query: '   ',
        documents: documents,
        events: events,
        sessions: sessions,
        places: places,
      );

      expect(results, isEmpty);
    });

    test('matches documents by title and skips deleted ones', () {
      final results = GlobalSearchService.search(
        query: '神经',
        documents: documents,
        events: events,
        sessions: sessions,
        places: places,
      );

      expect(results, hasLength(1));
      expect(results.single.kind, SearchKind.document);
      expect(results.single.title, '神经网络原理');
    });

    test('matches events by title and person names', () {
      final results = GlobalSearchService.search(
        query: '王老师',
        documents: documents,
        events: events,
        sessions: sessions,
        places: places,
      );

      final eventResults = results.where((r) => r.kind == SearchKind.event);
      expect(eventResults, hasLength(1));
      expect(eventResults.single.title, '和王老师讨论论文框架');
    });

    test('matches people by name and aliases, deduplicated', () {
      final results = GlobalSearchService.search(
        query: '王教授',
        documents: documents,
        events: events,
        sessions: sessions,
        places: places,
      );

      final personResults = results.where((r) => r.kind == SearchKind.person);
      expect(personResults, hasLength(1));
      expect(personResults.single.title, '王老师');
    });

    test('matches sessions by title and summary', () {
      final results = GlobalSearchService.search(
        query: '导师沟通',
        documents: documents,
        events: events,
        sessions: sessions,
        places: places,
      );

      final sessionResults = results.where((r) => r.kind == SearchKind.session);
      expect(sessionResults, hasLength(1));
      expect(sessionResults.single.title, contains('周分析'));
    });

    test('matches campus places by name and note', () {
      final results = GlobalSearchService.search(
        query: '实验室',
        documents: documents,
        events: events,
        sessions: sessions,
        places: places,
      );

      final placeResults = results.where((r) => r.kind == SearchKind.place);
      expect(placeResults, hasLength(1));
      expect(placeResults.single.title, '信息楼 3 号实验室');
    });

    test('search is case-insensitive', () {
      final results = GlobalSearchService.search(
        query: 'DEEP',
        documents: [
          ...documents,
          _doc(id: 'doc_en', title: 'Deep Learning Notes'),
        ],
        events: events,
        sessions: sessions,
        places: places,
      );

      expect(results, isNotEmpty);
      expect(results.first.title, 'Deep Learning Notes');
    });

    test('caps results at 60 entries', () {
      final manyDocuments = [
        for (var index = 0; index < 80; index += 1)
          _doc(id: 'doc_$index', title: '批量文献 $index'),
      ];

      final results = GlobalSearchService.search(
        query: '批量',
        documents: manyDocuments,
        events: const [],
        sessions: const [],
        places: const [],
      );

      expect(results.length, 60);
    });
  });
}
