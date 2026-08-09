import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/stats/stats_calculator.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/status_badge.dart';
import '../../state/research_life_controller.dart';

/// 分类语义色（主题无关，与 map_palette/history 同原则）。
const Map<ItemCategory, Color> _categoryColors = {
  ItemCategory.study: Color(0xFF3E63DD),
  ItemCategory.work: Color(0xFFF76B15),
  ItemCategory.life: Color(0xFF2F9E6E),
  ItemCategory.health: Color(0xFFE5484D),
  ItemCategory.social: Color(0xFF8B5CF6),
  ItemCategory.other: Color(0xFF9AA4B2),
};

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final GlobalKey _exportKey = GlobalKey();
  bool _exporting = false;
  bool _exportBusy = false;

  Future<void> _exportImage(BuildContext context) async {
    if (_exportBusy) {
      return;
    }
    setState(() {
      _exporting = true;
      _exportBusy = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _exportKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return;
      }

      final location = await getSaveLocation(
        suggestedName: '研究生活统计_${_timestamp()}.png',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PNG 图片', extensions: ['png']),
        ],
      );
      if (location == null) {
        return;
      }
      await File(location.path).writeAsBytes(byteData.buffer.asUint8List());
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('统计图已导出为 PNG。')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportBusy = false;
        });
      }
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (!_exporting)
              Positioned.fill(
                child: _StatsContent(
                  controller: controller,
                  onExport: () => _exportImage(context),
                ),
              ),
            if (_exporting)
              Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(
                  child: _StatsContent(
                    controller: controller,
                    exportKey: _exportKey,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 统计内容主体：正常模式为滚动视图，导出模式为固定宽度全高布局。
class _StatsContent extends StatelessWidget {
  const _StatsContent({
    required this.controller,
    this.onExport,
    this.exportKey,
  });

  final ResearchLifeController controller;
  final VoidCallback? onExport;
  final GlobalKey? exportKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    final events = controller.calendarEvents;
    final todos = controller.todoEvents;

    final daily = StatsCalculator.dailyStats(events, days: 84);
    final weeklyReading = StatsCalculator.weeklyReading(events, weeks: 8);
    final distribution = StatsCalculator.categoryDistribution(events);
    final todo = StatsCalculator.todoStats(todos);
    final ranking = StatsCalculator.personRanking(controller.sessionHistory);

    final todayRecords = daily.last.recordCount;
    final weekPlans = daily
        .skip(math.max(0, daily.length - 7))
        .fold(0, (sum, day) => sum + day.planCount);
    final weekReading = weeklyReading.last.readingMinutes;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            StatusBadge(label: '统计仪表盘', color: tokens.accent),
            StatusBadge(
              label: '记录 ${events.length} 条 · 待办 ${todos.length} 项',
              color: tokens.textSecondary,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的数据概览',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '阅读、记录、计划与待办的汇总视图，数据来自日历与周分析。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onExport != null) ...[
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: onExport,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('导出统计图'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 22),
        _OverviewRow(
          metrics: [
            _MetricData(
              label: '今日记录',
              value: todayRecords.toString(),
              icon: Icons.notes_rounded,
              color: const Color(0xFF3E63DD),
            ),
            _MetricData(
              label: '本周计划',
              value: weekPlans.toString(),
              icon: Icons.event_available_rounded,
              color: const Color(0xFFF76B15),
            ),
            _MetricData(
              label: '待办完成',
              value: '${(todo.completionRate * 100).round()}%',
              icon: Icons.task_alt_rounded,
              color: const Color(0xFF2F7D4F),
            ),
            _MetricData(
              label: '本周阅读',
              value: (weekReading / 60).toStringAsFixed(1),
              unit: '小时',
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF8B5CF6),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '阅读活跃热力图',
          subtitle: '近 12 周每天的活动强度（记录 + 计划 + 阅读时长），悬停查看明细',
          child: _HeatmapGrid(daily: daily),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '阅读时长趋势',
          subtitle: '近 8 周累计阅读分钟（每次阅读满 5 分钟才会计入）',
          child: _WeeklyReadingBars(weekly: weeklyReading),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '事项分类分布',
          subtitle: '全部记录与计划按类别统计',
          child: _CategoryDonut(distribution: distribution),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '人物互动排行',
          subtitle: '跨周分析会话按姓名聚合关联事项数',
          child: _PersonRankingList(ranking: ranking),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: '待办完成情况',
          subtitle: '已完成 ${todo.completed} / ${todo.total} 项',
          child: _TodoProgress(todo: todo),
        ),
      ],
    );

    if (exportKey != null) {
      // 导出模式：固定宽度全高布局，供 RepaintBoundary 完整截取。
      return RepaintBoundary(
        key: exportKey,
        child: Container(
          width: 900,
          color: theme.scaffoldBackgroundColor,
          padding: const EdgeInsets.all(28),
          child: body,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: body,
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 760
            ? 2
            : constraints.maxWidth < 1180
            ? 2
            : 4;
        final rowHeight = constraints.maxWidth < 1180 ? null : 112.0;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: (constraints.maxWidth - 12 * (columns - 1)) / columns,
                child: Container(
                  height: rowHeight,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tokens.panelSurface,
                    borderRadius: BorderRadius.circular(tokens.radiusLarge),
                    border: Border.all(color: tokens.borderFaint),
                    boxShadow: tokens.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: metric.color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              metric.icon,
                              size: 17,
                              color: metric.color,
                            ),
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              metric.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            metric.value,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (metric.unit != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              metric.unit!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 近 84 天活跃热力图（12 列 × 7 行），悬停显示当天明细。
class _HeatmapGrid extends StatelessWidget {
  const _HeatmapGrid({required this.daily});

  final List<DailyStats> daily;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(16.0, (constraints.maxWidth - 40) / 13);
        final columns = <List<DailyStats?>>[];
        for (var col = 0; col < 12; col += 1) {
          final column = <DailyStats?>[];
          for (var row = 0; row < 7; row += 1) {
            final index = col * 7 + row;
            column.add(index < daily.length ? daily[index] : null);
          }
          columns.add(column);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 18),
              child: Column(
                children: [
                  for (final label in const ['一', '', '三', '', '五', '', '日'])
                    SizedBox(
                      height: cell,
                      child: Center(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: tokens.textMuted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 18,
                      child: Row(
                        children: [
                          for (var col = 0; col < columns.length; col += 1)
                            SizedBox(
                              width: cell,
                              child: _MonthLabel(
                                date: columns[col].first?.date,
                                showLabel:
                                    col == 0 ||
                                    columns[col].first?.date.month !=
                                        columns[col - 1].first?.date.month,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final column in columns)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Column(
                              children: [
                                for (final day in column)
                                  Container(
                                    width: cell,
                                    height: cell,
                                    margin: const EdgeInsets.only(bottom: 3),
                                    child: _heatCell(day, cell, tokens),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _heatCell(DailyStats? day, double cell, AppTokens tokens) {
    final box = Container(
      decoration: BoxDecoration(
        color: _heatColor(day, tokens),
        borderRadius: BorderRadius.circular(3),
      ),
    );
    if (day == null) {
      return box;
    }
    return Tooltip(
      waitDuration: const Duration(milliseconds: 250),
      message:
          '${day.date.year}年${day.date.month}月${day.date.day}日\n'
          '记录 ${day.recordCount} 条 · 计划 ${day.planCount} 条\n'
          '阅读 ${day.readingMinutes} 分钟',
      child: box,
    );
  }

  Color _heatColor(DailyStats? day, AppTokens tokens) {
    if (day == null || day.activityScore == 0) {
      return tokens.panelSubtle;
    }
    final score = day.activityScore;
    if (score <= 2) {
      return tokens.accentSoft.withValues(alpha: 0.45);
    }
    if (score <= 5) {
      return tokens.accentSoft.withValues(alpha: 0.75);
    }
    return tokens.accent.withValues(alpha: 0.85);
  }
}

class _MonthLabel extends StatelessWidget {
  const _MonthLabel({required this.date, required this.showLabel});

  final DateTime? date;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (!showLabel || date == null) {
      return const SizedBox.shrink();
    }
    return Text(
      '${date!.month}月',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}

/// 近 8 周阅读时长条形图。
class _WeeklyReadingBars extends StatelessWidget {
  const _WeeklyReadingBars({required this.weekly});

  final List<WeeklyReadingStats> weekly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final maxMinutes = weekly.fold(
      0,
      (max, week) => math.max(max, week.readingMinutes),
    );
    final chartHeight = 150.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final week in weekly) ...[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatMinutes(week.readingMinutes),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: week.readingMinutes == 0
                        ? tokens.textMuted
                        : tokens.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: maxMinutes == 0
                      ? 4
                      : math.max(
                          4,
                          chartHeight * week.readingMinutes / maxMinutes,
                        ),
                  decoration: BoxDecoration(
                    color: week.readingMinutes == 0
                        ? tokens.panelSubtle
                        : tokens.accent.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(5),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${week.weekStart.month}/${week.weekStart.day}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (week != weekly.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) {
      return '0';
    }
    if (minutes < 60) {
      return '$minutes分';
    }
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(hours >= 10 ? 0 : 1)}h';
  }
}

/// 分类分布环形图 + 图例。
class _CategoryDonut extends StatelessWidget {
  const _CategoryDonut({required this.distribution});

  final List<CategoryDistribution> distribution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final total = distribution.fold(0, (sum, item) => sum + item.count);
    final visible = [
      for (final item in distribution)
        if (item.count > 0) item,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 560;
        final chart = SizedBox(
          width: 180,
          height: 180,
          child: CustomPaint(
            painter: _DonutChartPainter(distribution: distribution),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '事项',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final legend = Wrap(
          spacing: 14,
          runSpacing: 10,
          children: [
            for (final item in distribution)
              if (item.count > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _categoryColors[item.category],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${item.category.label} ${item.count}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
          ],
        );

        if (stacked) {
          return Column(
            children: [
              chart,
              const SizedBox(height: 16),
              if (visible.isEmpty) _EmptyHint(text: '还没有事项记录'),
              if (visible.isNotEmpty) legend,
            ],
          );
        }

        return Row(
          children: [
            chart,
            const SizedBox(width: 28),
            Expanded(
              child: visible.isEmpty ? _EmptyHint(text: '还没有事项记录') : legend,
            ),
          ],
        );
      },
    );
  }
}

/// 人物互动排行列表。
class _PersonRankingList extends StatelessWidget {
  const _PersonRankingList({required this.ranking});

  final List<PersonRanking> ranking;

  IconData _roleIcon(PersonRole role) => switch (role) {
    PersonRole.teacher => Icons.school_rounded,
    PersonRole.classmate => Icons.people_rounded,
    PersonRole.friend => Icons.emoji_people_rounded,
    PersonRole.partner => Icons.favorite_rounded,
    PersonRole.family => Icons.family_restroom_rounded,
    PersonRole.other => Icons.person_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    if (ranking.isEmpty) {
      return _EmptyHint(text: '还没有人物数据，完成周分析并确认结果后自动生成。');
    }

    final maxCount = ranking.first.taskCount;

    return Column(
      children: [
        for (final entry in ranking) ...[
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _roleIcon(entry.role),
                  size: 17,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      entry.role.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: maxCount == 0 ? 0 : entry.taskCount / maxCount,
                    minHeight: 8,
                    backgroundColor: tokens.panelSubtle,
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 56,
                child: Text(
                  '${entry.taskCount} 项',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (entry != ranking.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter({required this.distribution});

  final List<CategoryDistribution> distribution;

  @override
  void paint(Canvas canvas, Size size) {
    final total = distribution.fold(0, (sum, item) => sum + item.count);
    if (total == 0) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;
    final strokeWidth = 26.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    var startAngle = -math.pi / 2;
    for (final item in distribution) {
      if (item.count == 0) {
        continue;
      }
      final sweep = 2 * math.pi * item.count / total;
      ringPaint.color =
          _categoryColors[item.category] ?? const Color(0xFF9AA4B2);
      canvas.drawArc(rect, startAngle, sweep, false, ringPaint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.distribution != distribution;
  }
}

/// 待办完成率进度。
class _TodoProgress extends StatelessWidget {
  const _TodoProgress({required this.todo});

  final TodoStats todo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final rate = todo.completionRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '完成率',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '${(rate * 100).round()}%',
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF2F7D4F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: rate,
            minHeight: 10,
            backgroundColor: tokens.panelSubtle,
            color: const Color(0xFF2F7D4F),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          todo.total == 0
              ? '还没有待办，去「周分析」导入一周记录后会自动产生计划。'
              : '已完成 ${todo.completed} 项，还有 ${todo.total - todo.completed} 项待完成。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
  }
}
