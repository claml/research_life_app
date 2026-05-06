import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/chinese_lunar.dart';

class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    required this.month,
    required this.highlightedDates,
    this.holidayLabels = const {},
    this.compact = false,
    this.showWeekLabels = true,
    this.selectedDate,
    this.rangeStart,
    this.rangeEnd,
    this.onDayTap,
    this.onDayDoubleTap,
    super.key,
  });

  final DateTime month;
  final List<DateTime> highlightedDates;
  final Map<DateTime, String> holidayLabels;
  final bool compact;
  final bool showWeekLabels;
  final DateTime? selectedDate;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final ValueChanged<DateTime>? onDayTap;
  final ValueChanged<DateTime>? onDayDoubleTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final displayMonth = DateTime(month.year, month.month);
    final firstDay = DateTime(displayMonth.year, displayMonth.month, 1);
    final lastDay = DateTime(displayMonth.year, displayMonth.month + 1, 0);
    final leadingEmptyDays = firstDay.weekday - 1;
    final totalCells = leadingEmptyDays + lastDay.day;
    final totalRows = (totalCells / 7).ceil();
    final lunarLabels = <int, String>{
      for (var day = 1; day <= lastDay.day; day++)
        day: ChineseLunarCalendar.fromSolar(
          DateTime(displayMonth.year, displayMonth.month, day),
        ).label,
    };
    final highlightedDays = highlightedDates
        .where((date) => date.year == displayMonth.year && date.month == displayMonth.month)
        .map((date) => date.day)
        .toSet();
    final today = DateUtils.dateOnly(DateTime.now());

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final useCompact =
            compact || constraints.maxWidth < 680 || (boundedHeight && constraints.maxHeight < 460);
        final veryCompact =
            constraints.maxWidth < 560 || (boundedHeight && constraints.maxHeight < 380);
        final mainSpacing = veryCompact ? 3.0 : (useCompact ? 5.0 : 6.0);
        final cellPadding = veryCompact ? 2.0 : (useCompact ? 4.0 : 6.0);
        final dayStyle = (veryCompact
                ? Theme.of(context).textTheme.bodySmall
                : useCompact
                    ? Theme.of(context).textTheme.bodyMedium
                    : Theme.of(context).textTheme.titleSmall)
            ?.copyWith(
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            );
        final lunarStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: veryCompact ? 8.5 : (useCompact ? 9.5 : 10.5),
              height: 1.1,
              fontWeight: FontWeight.w500,
              color: tokens.textMuted,
            );
        final defaultAspectRatio = veryCompact
            ? 1.0
            : useCompact
                ? 1.14
                : 1.28;
        final childAspectRatio = boundedHeight
            ? _aspectRatioForHeight(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                rowCount: totalRows,
                spacing: mainSpacing,
                showWeekLabels: showWeekLabels,
                compact: useCompact,
                veryCompact: veryCompact,
              )
            : defaultAspectRatio;
        final dotSize = veryCompact ? 4.0 : (useCompact ? 6.0 : 8.0);
        final cellRadius = veryCompact ? 12.0 : (useCompact ? 14.0 : 16.0);

        return Column(
          children: [
            if (showWeekLabels) ...[
              const Row(
                children: [
                  _WeekLabel('\u4e00'),
                  _WeekLabel('\u4e8c'),
                  _WeekLabel('\u4e09'),
                  _WeekLabel('\u56db'),
                  _WeekLabel('\u4e94'),
                  _WeekLabel('\u516d'),
                  _WeekLabel('\u65e5'),
                ],
              ),
              SizedBox(height: useCompact ? 10 : 12),
            ],
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: totalCells,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: mainSpacing,
                crossAxisSpacing: mainSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                if (index < leadingEmptyDays) {
                  return const SizedBox.shrink();
                }

                final day = index - leadingEmptyDays + 1;
                final date = DateTime(displayMonth.year, displayMonth.month, day);
                final isToday = _sameDay(today, date);
                final isHighlighted = highlightedDays.contains(day);
                final holidayLabel = holidayLabels[DateUtils.dateOnly(date)];
                final isSelected = _sameDay(selectedDate, date);
                final isRangeStart = _sameDay(rangeStart, date);
                final isRangeEnd = _sameDay(rangeEnd, date);
                final isInRange = _isInRange(date);

                final selected = isSelected || isRangeStart || isRangeEnd;
                final lunarLabel = lunarLabels[day] ?? '';
                final borderColor = selected
                    ? tokens.accent
                    : holidayLabel != null
                        ? tokens.warmAccent.withValues(alpha: 0.65)
                    : isInRange
                        ? tokens.accentSoft
                        : isToday
                            ? tokens.borderSoft
                            : tokens.borderFaint;
                final backgroundColor = selected
                    ? tokens.accent
                    : holidayLabel != null
                        ? tokens.warmAccent.withValues(alpha: 0.14)
                    : isInRange
                        ? tokens.accentSoft.withValues(alpha: 0.72)
                        : isHighlighted
                            ? tokens.panelAccent
                            : tokens.panelSurface;
                final textColor = selected ? Colors.white : tokens.textPrimary;
                final lunarTextColor = selected
                    ? Colors.white.withValues(alpha: 0.84)
                    : holidayLabel != null
                        ? tokens.warmAccent
                    : isHighlighted
                        ? tokens.textSecondary
                        : tokens.textMuted;

                final cell = AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(cellRadius),
                    border: Border.all(
                      color: borderColor,
                      width: selected ? 1.4 : 1,
                    ),
                    boxShadow: selected ? const [] : tokens.shadowSm,
                  ),
                  padding: EdgeInsets.all(cellPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$day',
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: dayStyle?.copyWith(color: textColor),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  holidayLabel ?? lunarLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: lunarStyle?.copyWith(color: lunarTextColor),
                                ),
                              ],
                            ),
                          ),
                          if (isToday)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: _TodayBadge(selected: selected),
                            ),
                        ],
                      ),
                      const Spacer(),
                      if (isHighlighted)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            width: dotSize,
                            height: dotSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? Colors.white : tokens.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                );

                if (onDayTap == null && onDayDoubleTap == null) {
                  return cell;
                }

                return InkWell(
                  onTap: onDayTap == null ? null : () => onDayTap!(date),
                  onDoubleTap: onDayDoubleTap == null ? null : () => onDayDoubleTap!(date),
                  borderRadius: BorderRadius.circular(cellRadius),
                  child: cell,
                );
              },
            ),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime? left, DateTime right) {
    return left != null &&
        left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool _isInRange(DateTime date) {
    if (rangeStart == null || rangeEnd == null) {
      return false;
    }

    final dayOnly = DateUtils.dateOnly(date);
    final start = DateUtils.dateOnly(rangeStart!);
    final end = DateUtils.dateOnly(rangeEnd!);
    return !dayOnly.isBefore(start) && !dayOnly.isAfter(end);
  }

  double _aspectRatioForHeight({
    required double width,
    required double height,
    required int rowCount,
    required double spacing,
    required bool showWeekLabels,
    required bool compact,
    required bool veryCompact,
  }) {
    final weekLabelsHeight = showWeekLabels
        ? (veryCompact ? 28.0 : (compact ? 32.0 : 36.0))
        : 0.0;
    final usableHeight = math.max(
      1.0,
      height - weekLabelsHeight - spacing * math.max(0, rowCount - 1),
    );
    final usableWidth = math.max(1.0, width - spacing * 6);
    final cellHeight = usableHeight / rowCount;
    final cellWidth = usableWidth / 7;
    return math.max(0.6, cellWidth / math.max(1.0, cellHeight));
  }
}

class _WeekLabel extends StatelessWidget {
  const _WeekLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: tokens.textMuted,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

class _TodayBadge extends StatelessWidget {
  const _TodayBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Colors.white : tokens.warmAccent,
        border: Border.all(
          color: selected ? Colors.white.withValues(alpha: 0.95) : Colors.white,
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.warmAccent.withValues(alpha: selected ? 0.22 : 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}
