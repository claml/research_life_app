import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/calendar/china_holiday_service.dart';
import '../../state/research_life_controller.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/month_calendar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _displayMonth;
  DateTime? _selectedDate;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _displayMonth = DateTime(now.year, now.month);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = ResearchLifeScope.of(context);
      controller.ensureHomeGalleryReady();
      controller.ensureWeeklyPromptTemplateLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final holidayEvents = ChinaHolidayService.eventsForYear(
          _displayMonth.year,
        );
        final events = [...controller.calendarEvents, ...holidayEvents];
        final selectedDayEvents = _selectedDate == null
            ? const <EventItem>[]
            : _eventsForDay(events, _selectedDate!);
        final selectedRangeEvents = _eventsForRange(events);

        return LayoutBuilder(
          builder: (context, constraints) {
            final stackedLayout =
                constraints.maxWidth < 1080 || constraints.maxHeight < 620;
            final compactCalendar =
                constraints.maxWidth < 1320 || constraints.maxHeight < 720;
            final gap = stackedLayout ? 16.0 : 20.0;

            if (stackedLayout) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCalendarBoard(
                      events: events,
                      compact: constraints.maxWidth < 860,
                      fillHeight: false,
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: 320,
                      child: _buildGalleryBoard(
                        researchImagePath: controller.researchWallImagePath,
                        lifeImagePath: controller.lifeWallImagePath,
                      ),
                    ),
                    SizedBox(height: gap),
                    _buildRecordBoard(
                      context,
                      dayEvents: selectedDayEvents,
                      rangeEvents: selectedRangeEvents,
                      fillHeight: false,
                    ),
                  ],
                ),
              );
            }

            final preferredImageCardWidth = math.max(
              220.0,
              math.min(340.0, constraints.maxWidth * 0.26),
            );
            final minPrimaryColumnWidth = compactCalendar ? 720.0 : 780.0;
            final maxAsideWidth =
                constraints.maxWidth - minPrimaryColumnWidth - gap;
            final showGalleryAside = maxAsideWidth >= 180.0;
            final imageCardWidth = showGalleryAside
                ? math.max(
                    180.0,
                    math.min(preferredImageCardWidth, maxAsideWidth),
                  )
                : 0.0;
            final calendarFlex = compactCalendar ? 10 : 11;
            const recordFlex = 9;

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: calendarFlex,
                          child: _buildCalendarBoard(
                            events: events,
                            compact: compactCalendar,
                            fillHeight: true,
                          ),
                        ),
                        SizedBox(height: gap),
                        Expanded(
                          flex: recordFlex,
                          child: _buildRecordBoard(
                            context,
                            dayEvents: selectedDayEvents,
                            rangeEvents: selectedRangeEvents,
                            fillHeight: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showGalleryAside) ...[
                    SizedBox(width: gap),
                    SizedBox(
                      width: imageCardWidth,
                      child: _buildGalleryBoard(
                        researchImagePath: controller.researchWallImagePath,
                        lifeImagePath: controller.lifeWallImagePath,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCalendarBoard({
    required List<EventItem> events,
    required bool compact,
    required bool fillHeight,
  }) {
    final tokens = context.tokens;

    final calendarPanel = _InsetSurface(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 12 : 16,
        compact ? 12 : 16,
        compact ? 10 : 12,
      ),
      child: MonthCalendar(
        month: _displayMonth,
        highlightedDates: _buildHighlightedDates(events),
        holidayLabels: ChinaHolidayService.labelsForMonth(
          _displayMonth.year,
          _displayMonth.month,
        ),
        selectedDate: _selectedDate,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
        onDayTap: _handleDayTap,
        compact: compact,
        showWeekLabels: true,
      ),
    );

    return _BoardShell(
      color: Color.lerp(tokens.panelAccent, tokens.panelSurface, 0.22)!,
      borderColor: tokens.borderSoft,
      padding: EdgeInsets.all(compact ? 14 : 18),
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MonthNavigatorChip(
                monthLabel: _formatYearMonth(_displayMonth),
                compact: compact,
                onPrevious: _previousMonth,
                onToday: _jumpToCurrentMonth,
                onNext: _nextMonth,
              ),
              _SelectionTag(
                label: _rangeStart == null
                    ? '\u5f00\u59cb\u65e5\u671f\uff1a\u672a\u9009\u62e9'
                    : '\u5f00\u59cb\u65e5\u671f\uff1a${_formatMonthDay(_rangeStart!)}',
              ),
              _SelectionTag(
                label: _rangeEnd == null
                    ? '\u622a\u6b62\u65e5\u671f\uff1a\u672a\u9009\u62e9'
                    : '\u622a\u6b62\u65e5\u671f\uff1a${_formatMonthDay(_rangeEnd!)}',
              ),
              if (_rangeStart != null ||
                  _rangeEnd != null ||
                  _selectedDate != null)
                TextButton.icon(
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('\u6e05\u9664\u9009\u62e9'),
                ),
            ],
          ),
          SizedBox(height: compact ? 12 : 14),
          if (fillHeight) Expanded(child: calendarPanel) else calendarPanel,
        ],
      ),
    );
  }

  Widget _buildGalleryBoard({
    required String? researchImagePath,
    required String? lifeImagePath,
  }) {
    final tokens = context.tokens;

    return _BoardShell(
      color: tokens.panelSubtle,
      borderColor: tokens.borderFaint,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: _GalleryFrame(
              imagePath: researchImagePath,
              fallbackLabel: '\u56fe\u7247',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _GalleryFrame(
              imagePath: lifeImagePath,
              fallbackLabel: '\u56fe\u7247',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordBoard(
    BuildContext context, {
    required List<EventItem> dayEvents,
    required List<EventItem> rangeEvents,
    required bool fillHeight,
  }) {
    final tokens = context.tokens;
    final subtitle = _buildDetailSubtitle();
    final showClearAction =
        _rangeStart != null || _rangeEnd != null || _selectedDate != null;
    final singleDayEditingMode = _selectedDate != null && _rangeEnd == null;
    final detailContent = _buildDetailContent(
      context,
      dayEvents: dayEvents,
      rangeEvents: rangeEvents,
    );

    return _BoardShell(
      color: tokens.panelSurface,
      borderColor: tokens.borderFaint,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stackHeader = constraints.maxWidth < 760;

              final titleBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u8bb0\u5f55',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              );

              final reportAction = FilledButton.icon(
                onPressed: _rangeStart != null && _rangeEnd != null
                    ? () => _showWeeklyPromptDialog(context, rangeEvents)
                    : null,
                icon: const Icon(Icons.description_rounded),
                label: const Text('\u751f\u6210\u5468\u62a5'),
              );
              final addAction = FilledButton.icon(
                onPressed: !singleDayEditingMode
                    ? null
                    : () =>
                          _showEventEditorDialog(context, date: _selectedDate!),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加记录'),
              );
              final topAction = singleDayEditingMode ? addAction : reportAction;
              final actionSlot = ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 140),
                child: Align(alignment: Alignment.topRight, child: topAction),
              );

              if (stackHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: actionSlot),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 16),
                  actionSlot,
                ],
              );
            },
          ),
          if (showClearAction) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _clearSelection,
              icon: Icon(
                Icons.clear_rounded,
                size: 18,
                color: tokens.textSecondary,
              ),
              label: Text(
                '\u6e05\u9664\u9009\u62e9',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (fillHeight)
            Expanded(child: SingleChildScrollView(child: detailContent))
          else
            detailContent,
        ],
      ),
    );
  }

  void _previousMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1);
    });
  }

  void _jumpToCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _displayMonth = DateTime(now.year, now.month);
    });
  }

  void _handleDayTap(DateTime date) {
    final tapped = DateUtils.dateOnly(date);

    if (_rangeStart != null &&
        _rangeEnd == null &&
        _sameDay(_rangeStart!, tapped)) {
      _clearSelection();
      return;
    }

    setState(() {
      _selectedDate = tapped;

      if (_rangeStart == null || _rangeEnd != null) {
        _rangeStart = tapped;
        _rangeEnd = null;
        return;
      }

      if (tapped.isBefore(_rangeStart!)) {
        _rangeEnd = _rangeStart;
        _rangeStart = tapped;
      } else {
        _rangeEnd = tapped;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedDate = null;
      _rangeStart = null;
      _rangeEnd = null;
    });
  }

  Widget _buildDetailContent(
    BuildContext context, {
    required List<EventItem> dayEvents,
    required List<EventItem> rangeEvents,
  }) {
    final singleDayEditingMode = _selectedDate != null && _rangeEnd == null;

    if (_rangeStart != null && _rangeEnd != null) {
      if (rangeEvents.isEmpty) {
        return const EmptyState(
          title: '\u8fd9\u6bb5\u65f6\u95f4\u6ca1\u6709\u8bb0\u5f55',
          description:
              '\u6362\u4e00\u4e2a\u65e5\u671f\u8303\u56f4\u8bd5\u8bd5\u3002',
          icon: Icons.date_range_rounded,
        );
      }

      final peopleCount = rangeEvents
          .expand((event) => event.personNames)
          .toSet()
          .length;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryBar(
            label:
                '\u5171 ${rangeEvents.length} \u6761\u4e8b\u9879\uff0c\u6d89\u53ca $peopleCount \u4f4d\u4eba\u7269',
          ),
          const SizedBox(height: 12),
          for (final event in rangeEvents) ...[
            _EventTile(
              title: event.title,
              subtitle: _buildEventSubtitle(event, includeDate: true),
              leadingIcon: event.type == EventType.plan
                  ? Icons.schedule_rounded
                  : Icons.task_alt_rounded,
              iconColor: event.type == EventType.plan
                  ? context.tokens.warmAccent
                  : context.tokens.accent,
              trailing: _buildEventTrailing(context, event, editable: false),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    if (_selectedDate == null) {
      return const EmptyState(
        title: '\u8fd8\u6ca1\u6709\u9009\u4e2d\u65e5\u671f',
        description:
            '\u70b9\u51fb\u65e5\u5386\u4e2d\u7684\u4efb\u610f\u4e00\u5929\u5f00\u59cb\u67e5\u770b\u8bb0\u5f55\u3002',
        icon: Icons.today_rounded,
      );
    }

    if (dayEvents.isEmpty) {
      return EmptyState(
        title: '\u8fd9\u4e00\u5929\u6ca1\u6709\u8bb0\u5f55',
        description: _formatMonthDay(_selectedDate!),
        icon: Icons.event_busy_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBar(
          label: '\u5f53\u5929\u5171 ${dayEvents.length} \u6761\u4e8b\u9879',
        ),
        const SizedBox(height: 12),
        for (final event in dayEvents) ...[
          _EventTile(
            title: event.title,
            subtitle: _buildEventSubtitle(event),
            leadingIcon: event.type == EventType.plan
                ? Icons.schedule_rounded
                : Icons.task_alt_rounded,
            iconColor: event.type == EventType.plan
                ? context.tokens.warmAccent
                : context.tokens.accent,
            trailing: _buildEventTrailing(
              context,
              event,
              editable: singleDayEditingMode && event.isEditable,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget? _buildEventTrailing(
    BuildContext context,
    EventItem event, {
    required bool editable,
  }) {
    if (editable) {
      return IconButton(
        tooltip: '编辑记录',
        onPressed: () => _showEventEditorDialog(
          context,
          date: _selectedDate ?? event.startAt,
          existingEvent: event,
        ),
        icon: const Icon(Icons.edit_outlined, size: 18),
      );
    }

    if (!event.isEditable) {
      return Tooltip(
        message: '节假日和校历内容不允许修改',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: context.tokens.panelSubtle,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: context.tokens.borderFaint),
          ),
          child: Text(
            '锁定',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return null;
  }

  String _buildDetailSubtitle() {
    if (_rangeStart != null && _rangeEnd != null) {
      return '${_formatMonthDay(_rangeStart!)} - ${_formatMonthDay(_rangeEnd!)}';
    }
    if (_selectedDate != null) {
      return _formatMonthDay(_selectedDate!);
    }
    return '\u6309\u5929\u67e5\u770b\u8bb0\u5f55\uff0c\u6216\u901a\u8fc7\u533a\u95f4\u751f\u6210\u5468\u62a5\u3002';
  }

  List<DateTime> _buildHighlightedDates(List<EventItem> events) {
    final dates = <DateTime>[];
    for (final event in events) {
      final start = DateUtils.dateOnly(event.startAt);
      final end = DateUtils.dateOnly(event.endAt ?? event.startAt);
      var cursor = start;
      while (!cursor.isAfter(end)) {
        dates.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return dates;
  }

  List<EventItem> _eventsForDay(List<EventItem> events, DateTime day) {
    final dayOnly = DateUtils.dateOnly(day);
    return events.where((event) {
      final start = DateUtils.dateOnly(event.startAt);
      final end = DateUtils.dateOnly(event.endAt ?? event.startAt);
      return !dayOnly.isBefore(start) && !dayOnly.isAfter(end);
    }).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  List<EventItem> _eventsForRange(List<EventItem> events) {
    if (_rangeStart == null || _rangeEnd == null) {
      return const [];
    }

    final start = DateUtils.dateOnly(_rangeStart!);
    final end = DateUtils.dateOnly(_rangeEnd!);

    return events.where((event) {
      final eventStart = DateUtils.dateOnly(event.startAt);
      final eventEnd = DateUtils.dateOnly(event.endAt ?? event.startAt);
      return !eventEnd.isBefore(start) && !eventStart.isAfter(end);
    }).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  bool _sameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatYearMonth(DateTime date) {
    return '${date.year}\u5e74${date.month}\u6708';
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

  String _typeLabel(EventType type) {
    return switch (type) {
      EventType.record => '\u8bb0\u5f55',
      EventType.plan => '\u8ba1\u5212',
    };
  }

  String _categoryLabel(ItemCategory category) {
    return switch (category) {
      ItemCategory.study => '\u5b66\u4e60',
      ItemCategory.work => '\u5de5\u4f5c',
      ItemCategory.life => '\u751f\u6d3b',
      ItemCategory.health => '\u5065\u5eb7',
      ItemCategory.social => '\u793e\u4ea4\u5173\u7cfb',
      ItemCategory.other => '\u5176\u4ed6',
    };
  }

  String _formatPersonSuffix(List<String> personNames) {
    if (personNames.isEmpty) {
      return '';
    }
    return ' \u00b7 ${personNames.join('\u3001')}';
  }

  String _buildEventSubtitle(EventItem event, {bool includeDate = false}) {
    final parts = <String>[
      if (includeDate) _formatEventDateRange(event),
      _typeLabel(event.type),
      _categoryLabel(event.category),
      if (event.sourceLabel != null && event.sourceLabel!.isNotEmpty)
        event.sourceLabel!,
    ];

    final base = parts.join(' \u00b7 ');
    return '$base${_formatPersonSuffix(event.personNames)}';
  }

  Future<void> _showWeeklyPromptDialog(
    BuildContext context,
    List<EventItem> rangeEvents,
  ) async {
    if (_rangeStart == null || _rangeEnd == null) {
      return;
    }

    final controller = ResearchLifeScope.of(context);
    await controller.ensureWeeklyPromptTemplateLoaded();
    if (!context.mounted) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _WeeklyPromptDialog(
        controller: controller,
        rangeStart: _rangeStart!,
        rangeEnd: _rangeEnd!,
        rangeLabel:
            '${_formatMonthDay(_rangeStart!)} - ${_formatMonthDay(_rangeEnd!)}',
        rangeEvents: rangeEvents,
      ),
    );
  }

  Future<void> _showEventEditorDialog(
    BuildContext context, {
    required DateTime date,
    EventItem? existingEvent,
  }) async {
    final result = await showDialog<_EventEditorResult>(
      context: context,
      builder: (context) => _EventEditorDialog(
        initialDate: date,
        initialTitle: existingEvent?.title ?? '',
        initialCategory: existingEvent?.category ?? ItemCategory.study,
        initialType: existingEvent?.type ?? EventType.record,
        isEditing: existingEvent != null,
      ),
    );

    if (!context.mounted || result == null) {
      return;
    }

    final controller = ResearchLifeScope.of(context);
    final message = existingEvent == null
        ? controller.addManualEvent(
            date: date,
            title: result.title,
            category: result.category,
            type: result.type,
          )
        : controller.updateEditableEvent(
            eventId: existingEvent.id,
            title: result.title,
            category: result.category,
            type: result.type,
          );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WeeklyPromptDialog extends StatefulWidget {
  const _WeeklyPromptDialog({
    required this.controller,
    required this.rangeStart,
    required this.rangeEnd,
    required this.rangeLabel,
    required this.rangeEvents,
  });

  final ResearchLifeController controller;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String rangeLabel;
  final List<EventItem> rangeEvents;

  @override
  State<_WeeklyPromptDialog> createState() => _WeeklyPromptDialogState();
}

class _WeeklyPromptDialogState extends State<_WeeklyPromptDialog> {
  static const _placeholders = <String>[
    '{{date_range}}',
    '{{record_count}}',
    '{{plan_count}}',
    '{{people_count}}',
    '{{completed_items}}',
    '{{planned_items}}',
    '{{people}}',
    '{{all_events}}',
  ];

  late final TextEditingController _promptController;
  late final TextEditingController _templateController;
  bool _savingTemplate = false;
  bool _resettingTemplate = false;

  @override
  void initState() {
    super.initState();
    final initialTemplate = widget.controller.weeklyPromptTemplate;
    _templateController = TextEditingController(text: initialTemplate);
    _promptController = TextEditingController(
      text: widget.controller.buildWeeklyReportPrompt(
        start: widget.rangeStart,
        end: widget.rangeEnd,
        rangeEvents: widget.rangeEvents,
        templateOverride: initialTemplate,
      ),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return AlertDialog(
      title: const Text('周报提示词'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '已根据 ${widget.rangeLabel} 的记录生成一段可直接发给其他 AI 的提示词。'
                '你可以临时修改本次提示词，也可以在下方调整常用模板。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '本次提示词',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _promptController,
                minLines: 10,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: '这里会显示生成后的提示词',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _regeneratePrompt,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('按模板重生成'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _copyPrompt,
                    icon: const Icon(Icons.content_copy_rounded),
                    label: const Text('复制提示词'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '常用模板',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '支持变量：${_placeholders.join('、')}。修改模板后点击“设为常用”，之后每次生成都会默认使用它。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final placeholder in _placeholders)
                    ActionChip(
                      label: Text(placeholder),
                      onPressed: () => _insertPlaceholder(placeholder),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _templateController,
                minLines: 12,
                maxLines: 16,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: '编辑常用提示词模板',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _resettingTemplate
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: _resettingTemplate ? null : _resetTemplate,
          child: Text(_resettingTemplate ? '恢复中...' : '恢复默认'),
        ),
        FilledButton(
          onPressed: _savingTemplate ? null : _saveTemplate,
          child: Text(_savingTemplate ? '保存中...' : '设为常用'),
        ),
      ],
    );
  }

  void _regeneratePrompt() {
    final nextPrompt = widget.controller.buildWeeklyReportPrompt(
      start: widget.rangeStart,
      end: widget.rangeEnd,
      rangeEvents: widget.rangeEvents,
      templateOverride: _templateController.text,
    );
    _promptController.text = nextPrompt;
  }

  Future<void> _copyPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showMessage('提示词为空，无法复制。');
      return;
    }

    await Clipboard.setData(ClipboardData(text: prompt));
    if (!mounted) {
      return;
    }
    _showMessage('提示词已复制，可直接粘贴到其他 AI。');
  }

  Future<void> _saveTemplate() async {
    final template = _templateController.text.trim();
    if (template.isEmpty) {
      _showMessage('常用提示词模板不能为空。');
      return;
    }

    setState(() => _savingTemplate = true);
    try {
      final message = await widget.controller.saveWeeklyPromptTemplate(
        template,
      );
      if (!mounted) {
        return;
      }
      _regeneratePrompt();
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _savingTemplate = false);
      }
    }
  }

  Future<void> _resetTemplate() async {
    setState(() => _resettingTemplate = true);
    try {
      final message = await widget.controller.resetWeeklyPromptTemplate();
      if (!mounted) {
        return;
      }
      _templateController.text =
          ResearchLifeController.defaultWeeklyPromptTemplate;
      _regeneratePrompt();
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _resettingTemplate = false);
      }
    }
  }

  void _insertPlaceholder(String placeholder) {
    final selection = _templateController.selection;
    final currentText = _templateController.text;
    final start = selection.isValid ? selection.start : currentText.length;
    final end = selection.isValid ? selection.end : currentText.length;
    final safeStart = start < 0 ? currentText.length : start;
    final safeEnd = end < 0 ? currentText.length : end;
    final nextText = currentText.replaceRange(safeStart, safeEnd, placeholder);

    _templateController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(
        offset: safeStart + placeholder.length,
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BoardShell extends StatelessWidget {
  const _BoardShell({
    required this.child,
    required this.color,
    required this.borderColor,
    required this.padding,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(tokens.radiusXLarge),
        border: Border.all(color: borderColor),
        boxShadow: tokens.shadowSm,
      ),
      padding: padding,
      child: child,
    );
  }
}

class _InsetSurface extends StatelessWidget {
  const _InsetSurface({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.insetSurface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.borderFaint),
      ),
      padding: padding,
      child: child,
    );
  }
}

class _MonthNavigatorChip extends StatelessWidget {
  const _MonthNavigatorChip({
    required this.monthLabel,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
    required this.compact,
  });

  final String monthLabel;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderFaint),
        boxShadow: tokens.shadowSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MonthActionButton(
            tooltip: '\u4e0a\u4e2a\u6708',
            icon: Icons.chevron_left_rounded,
            onPressed: onPrevious,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              monthLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _MonthActionButton(
            tooltip: '\u4e0b\u4e2a\u6708',
            icon: Icons.chevron_right_rounded,
            onPressed: onNext,
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onToday,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('\u672c\u6708'),
          ),
        ],
      ),
    );
  }
}

class _MonthActionButton extends StatelessWidget {
  const _MonthActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        backgroundColor: tokens.panelSubtle,
        side: BorderSide(color: tokens.borderFaint),
        fixedSize: const Size(32, 32),
        padding: EdgeInsets.zero,
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class _SelectionTag extends StatelessWidget {
  const _SelectionTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.insetSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.iconColor,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final Color iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.insetSurface,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(leadingIcon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _EventEditorResult {
  const _EventEditorResult({
    required this.title,
    required this.category,
    required this.type,
  });

  final String title;
  final ItemCategory category;
  final EventType type;
}

class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({
    required this.initialDate,
    required this.initialTitle,
    required this.initialCategory,
    required this.initialType,
    required this.isEditing,
  });

  final DateTime initialDate;
  final String initialTitle;
  final ItemCategory initialCategory;
  final EventType initialType;
  final bool isEditing;

  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  late final TextEditingController _titleController;
  late ItemCategory _category;
  late EventType _type;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _category = widget.initialCategory;
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? '编辑记录' : '添加记录'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '日期：${widget.initialDate.year}-${widget.initialDate.month.toString().padLeft(2, '0')}-${widget.initialDate.day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '输入这一天的记录或计划',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ItemCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: '分类'),
              items: ItemCategory.values
                  .map(
                    (category) => DropdownMenuItem<ItemCategory>(
                      value: category,
                      child: Text(_categoryLabel(category)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<EventType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: '类型'),
              items: EventType.values
                  .map(
                    (type) => DropdownMenuItem<EventType>(
                      value: type,
                      child: Text(_typeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _type = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _EventEditorResult(
                title: _titleController.text.trim(),
                category: _category,
                type: _type,
              ),
            );
          },
          child: Text(widget.isEditing ? '保存修改' : '添加'),
        ),
      ],
    );
  }

  static String _categoryLabel(ItemCategory category) {
    return switch (category) {
      ItemCategory.study => '学习',
      ItemCategory.work => '工作',
      ItemCategory.life => '生活',
      ItemCategory.health => '健康',
      ItemCategory.social => '社交关系',
      ItemCategory.other => '其他',
    };
  }

  static String _typeLabel(EventType type) {
    return switch (type) {
      EventType.record => '记录',
      EventType.plan => '计划',
    };
  }
}

class _GalleryFrame extends StatelessWidget {
  const _GalleryFrame({required this.imagePath, required this.fallbackLabel});

  final String? imagePath;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;
    final tokens = context.tokens;

    return _InsetSurface(
      padding: EdgeInsets.zero,
      child: hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(tokens.radiusLarge - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(imagePath!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.04),
                          Colors.black.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Center(
              child: Text(
                fallbackLabel,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tokens.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
  }
}
