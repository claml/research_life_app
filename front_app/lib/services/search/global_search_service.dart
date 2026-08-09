import '../../core/models/app_models.dart';

/// 搜索结果类型，决定点击后的跳转动作。
enum SearchKind { document, event, person, session, place }

/// 一条全局搜索结果。
class GlobalSearchResult {
  const GlobalSearchResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.target,
    this.documentId,
  });

  final SearchKind kind;

  /// 主标题（如文献标题 / 事件标题 / 人物名）。
  final String title;

  /// 副标题（分类、日期、来源等）。
  final String subtitle;

  /// 点击后要跳转的导航目标。
  final Object target;

  /// 文献类结果的文件 id（用于打开阅读/文档查阅）。
  final String? documentId;
}

/// 全局搜索：跨文献、记录与计划、人物、分析会话、校园地点的统一匹配。
/// 纯函数、无副作用，便于单元测试。
abstract final class GlobalSearchService {
  /// 在各类数据中执行 [query] 匹配，返回统一结果列表。
  static List<GlobalSearchResult> search({
    required String query,
    required List<PdfLibraryDocument> documents,
    required List<EventItem> events,
    required List<SessionRecord> sessions,
    required List<CampusPlace> places,
  }) {
    final keyword = query.trim().toLowerCase();
    if (keyword.isEmpty) {
      return const [];
    }

    final results = <GlobalSearchResult>[
      ..._searchDocuments(keyword, documents),
      ..._searchEvents(keyword, events),
      ..._searchPeople(keyword, sessions),
      ..._searchSessions(keyword, sessions),
      ..._searchPlaces(keyword, places),
    ];

    // 限制单次展示量，避免超长列表拖慢界面。
    return results.take(60).toList();
  }

  static List<GlobalSearchResult> _searchDocuments(
    String keyword,
    List<PdfLibraryDocument> documents,
  ) {
    final results = <GlobalSearchResult>[];
    for (final document in documents) {
      if (document.isDeleted) {
        continue;
      }
      final title = document.title;
      final fileName = _fileNameFromPath(document.path);
      if (!_matchesAny(keyword, [title, fileName, document.category])) {
        continue;
      }
      results.add(
        GlobalSearchResult(
          kind: SearchKind.document,
          title: title,
          subtitle: '${document.fileKind.label} · ${document.category}',
          target: document,
          documentId: document.id,
        ),
      );
    }
    return results;
  }

  static List<GlobalSearchResult> _searchEvents(
    String keyword,
    List<EventItem> events,
  ) {
    final results = <GlobalSearchResult>[];
    for (final event in events) {
      final haystack = <String>[
        event.title,
        event.category.label,
        event.sourceLabel ?? '',
        ...event.personNames,
      ];
      if (!_matchesAny(keyword, haystack)) {
        continue;
      }
      results.add(
        GlobalSearchResult(
          kind: SearchKind.event,
          title: event.title,
          subtitle:
              '${event.type.label} · ${event.category.label} · '
              '${_formatDate(event.startAt)}',
          target: event,
        ),
      );
    }
    return results;
  }

  static List<GlobalSearchResult> _searchPeople(
    String keyword,
    List<SessionRecord> sessions,
  ) {
    final results = <GlobalSearchResult>[];
    final seenNames = <String>{};
    for (final session in sessions) {
      for (final person in session.people) {
        if (seenNames.contains(person.name)) {
          continue;
        }
        if (!_matchesAny(keyword, [person.name, ...person.aliases])) {
          continue;
        }
        seenNames.add(person.name);
        results.add(
          GlobalSearchResult(
            kind: SearchKind.person,
            title: person.name,
            subtitle:
                '${person.role.label} · 关联 ${person.relatedTaskCount} 项事项',
            target: person,
          ),
        );
      }
    }
    return results;
  }

  static List<GlobalSearchResult> _searchSessions(
    String keyword,
    List<SessionRecord> sessions,
  ) {
    final results = <GlobalSearchResult>[];
    for (final session in sessions) {
      if (!_matchesAny(keyword, [session.title, session.preview.summary])) {
        continue;
      }
      results.add(
        GlobalSearchResult(
          kind: SearchKind.session,
          title: session.title,
          subtitle:
              '${session.input.sourceType.label} · '
              '${_formatDate(session.confirmedAt)}',
          target: session,
        ),
      );
    }
    return results;
  }

  static List<GlobalSearchResult> _searchPlaces(
    String keyword,
    List<CampusPlace> places,
  ) {
    final results = <GlobalSearchResult>[];
    for (final place in places) {
      if (!_matchesAny(keyword, [
        place.name,
        place.note,
        place.category.label,
      ])) {
        continue;
      }
      results.add(
        GlobalSearchResult(
          kind: SearchKind.place,
          title: place.name,
          subtitle: '${place.category.label} · ${place.note}',
          target: place,
        ),
      );
    }
    return results;
  }

  static bool _matchesAny(String keyword, List<String> fields) {
    for (final field in fields) {
      if (field.trim().toLowerCase().contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  static String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }
}
