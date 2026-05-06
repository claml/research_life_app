import '../../core/models/app_models.dart';

class ChinaHolidayService {
  ChinaHolidayService._();

  static const String sourceLabel = '国务院办公厅 2026 节假日安排';

  static List<EventItem> eventsForYear(int year) {
    if (year != 2026) {
      return const [];
    }

    return [
      EventItem(
        id: 'holiday_2026_new_year',
        title: '元旦',
        category: ItemCategory.life,
        type: EventType.plan,
        startAt: DateTime(2026, 1, 1),
        endAt: DateTime(2026, 1, 3),
        origin: EventOrigin.holiday,
        sourceLabel: sourceLabel,
      ),
      EventItem(
        id: 'holiday_2026_spring_festival',
        title: '春节',
        category: ItemCategory.life,
        type: EventType.plan,
        startAt: DateTime(2026, 2, 15),
        endAt: DateTime(2026, 2, 23),
        origin: EventOrigin.holiday,
        sourceLabel: sourceLabel,
      ),
      EventItem(
        id: 'holiday_2026_qingming',
        title: '清明节',
        category: ItemCategory.life,
        type: EventType.plan,
        startAt: DateTime(2026, 4, 4),
        endAt: DateTime(2026, 4, 6),
        origin: EventOrigin.holiday,
        sourceLabel: sourceLabel,
      ),
      EventItem(
        id: 'holiday_2026_labor_day',
        title: '劳动节',
        category: ItemCategory.life,
        type: EventType.plan,
        startAt: DateTime(2026, 5, 1),
        endAt: DateTime(2026, 5, 5),
        origin: EventOrigin.holiday,
        sourceLabel: sourceLabel,
      ),
      EventItem(
        id: 'holiday_2026_dragon_boat',
        title: '端午节',
        category: ItemCategory.life,
        type: EventType.plan,
        startAt: DateTime(2026, 6, 19),
        endAt: DateTime(2026, 6, 21),
        origin: EventOrigin.holiday,
        sourceLabel: sourceLabel,
      ),
      EventItem(
        id: 'holiday_2026_mid_autumn',
        title: '中秋节',
        category: ItemCategory.life,
        type: EventType.plan,
        startAt: DateTime(2026, 9, 25),
        endAt: DateTime(2026, 9, 27),
        origin: EventOrigin.holiday,
        sourceLabel: sourceLabel,
      ),
      EventItem(
        id: 'holiday_2026_national_day',
        title: '国庆节',
        category: ItemCategory.life,
        type: EventType.plan,
        startAt: DateTime(2026, 10, 1),
        endAt: DateTime(2026, 10, 7),
        origin: EventOrigin.holiday,
        sourceLabel: sourceLabel,
      ),
    ];
  }

  static Map<DateTime, String> labelsForMonth(int year, int month) {
    final labels = <DateTime, String>{};
    for (final event in eventsForYear(year)) {
      var cursor = DateTime(event.startAt.year, event.startAt.month, event.startAt.day);
      final end = DateTime(
        (event.endAt ?? event.startAt).year,
        (event.endAt ?? event.startAt).month,
        (event.endAt ?? event.startAt).day,
      );
      while (!cursor.isAfter(end)) {
        if (cursor.year == year && cursor.month == month) {
          labels[cursor] = event.title;
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return labels;
  }
}
