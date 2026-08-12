import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../calendar/calendar_page.dart';
import '../todos/todo_page.dart';
import 'workbench_workspace_frame.dart';

class TodayWorkspace extends StatelessWidget {
  const TodayWorkspace({
    required this.navigation,
    this.pages,
    this.onQuickCapture,
    super.key,
  });

  final WorkbenchNavigationController navigation;
  final Map<WorkbenchTab, Widget>? pages;
  final VoidCallback? onQuickCapture;

  @override
  Widget build(BuildContext context) {
    final resolvedPages =
        pages ??
        const {
          WorkbenchTab.todayOverview: _TodayOverview(),
          WorkbenchTab.todayCalendar: CalendarPage(),
          WorkbenchTab.todayTodos: TodoPage(),
        };
    return WorkbenchWorkspaceFrame(
      key: const Key('today-workspace'),
      workspace: WorkbenchWorkspace.today,
      navigation: navigation,
      title: '今天',
      pages: resolvedPages,
      primaryAction: FilledButton.icon(
        onPressed: onQuickCapture,
        icon: const Icon(Icons.add_rounded, size: 19),
        label: const Text('快速记录'),
      ),
    );
  }
}

class _TodayOverview extends StatefulWidget {
  const _TodayOverview();

  @override
  State<_TodayOverview> createState() => _TodayOverviewState();
}

class _TodayOverviewState extends State<_TodayOverview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ResearchLifeScope.of(context);
      unawaited(controller.ensureSessionHistoryLoaded());
      unawaited(controller.ensureManualEventsLoaded());
      unawaited(controller.ensureTodoStatusLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final now = DateTime.now();
        final events =
            controller.calendarEvents
                .where(
                  (event) =>
                      event.startAt.year == now.year &&
                      event.startAt.month == now.month &&
                      event.startAt.day == now.day,
                )
                .toList()
              ..sort((left, right) => left.startAt.compareTo(right.startAt));
        final todos = controller.todayTodoEvents;
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final timeline = _OverviewPanel(
              title: '今日日程',
              trailing: '${events.length} 项',
              child: events.isEmpty
                  ? const _EmptyOverview(message: '今天还没有安排')
                  : Column(
                      children: [
                        for (final event in events.take(6))
                          _TimelineItem(event: event),
                      ],
                    ),
            );
            final todoPanel = _OverviewPanel(
              title: '今日待办',
              trailing: '${todos.length} 项',
              child: todos.isEmpty
                  ? const _EmptyOverview(message: '今天的任务已清空')
                  : Column(
                      children: [
                        for (final todo in todos.take(6))
                          _TodoItem(event: todo),
                      ],
                    ),
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppLayout.pageHorizontalPadding),
              child: compact
                  ? Column(
                      children: [
                        timeline,
                        const SizedBox(height: 18),
                        todoPanel,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: timeline),
                        const SizedBox(width: 20),
                        Expanded(flex: 5, child: todoPanel),
                      ],
                    ),
            );
          },
        );
      },
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.title,
    required this.trailing,
    required this.child,
  });

  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.borderFaint),
        boxShadow: tokens.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                trailing,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final minute = event.startAt.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '${event.startAt.hour.toString().padLeft(2, '0')}:$minute',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: tokens.textSecondary),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5, right: 12),
            decoration: BoxDecoration(
              color: tokens.accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoItem extends StatelessWidget {
  const _TodoItem({required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(Icons.circle_outlined, size: 18, color: tokens.accent),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              event.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyOverview extends StatelessWidget {
  const _EmptyOverview({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Center(
        child: Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.tokens.textMuted),
        ),
      ),
    );
  }
}
