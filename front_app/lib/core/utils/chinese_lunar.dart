class ChineseLunarDate {
  const ChineseLunarDate({
    required this.year,
    required this.month,
    required this.day,
    required this.isLeapMonth,
  });

  final int year;
  final int month;
  final int day;
  final bool isLeapMonth;

  static const List<String> _monthNames = <String>[
    '正月',
    '二月',
    '三月',
    '四月',
    '五月',
    '六月',
    '七月',
    '八月',
    '九月',
    '十月',
    '冬月',
    '腊月',
  ];

  static const List<String> _dayPrefixes = <String>['初', '十', '廿', '三'];

  static const List<String> _dayNumbers = <String>[
    '',
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '七',
    '八',
    '九',
    '十',
  ];

  String get monthLabel {
    final baseLabel = _monthNames[month - 1];
    return isLeapMonth ? '闰$baseLabel' : baseLabel;
  }

  String get dayLabel => _formatDay(day);

  String get fullLabel => '$monthLabel$dayLabel';

  String get label => day == 1 ? monthLabel : dayLabel;

  static String _formatDay(int day) {
    if (day == 10) {
      return '初十';
    }
    if (day == 20) {
      return '二十';
    }
    if (day == 30) {
      return '三十';
    }

    final prefix = _dayPrefixes[(day - 1) ~/ 10];
    final suffix = _dayNumbers[day % 10];
    return '$prefix$suffix';
  }
}

class ChineseLunarCalendar {
  ChineseLunarCalendar._();

  static const int _startYear = 1900;
  static const int _endYear = 2050;
  static final DateTime _baseDate = DateTime(1900, 1, 31);

  static const List<int> _lunarInfo = <int>[
    0x04BD8,
    0x04AE0,
    0x0A570,
    0x054D5,
    0x0D260,
    0x0D950,
    0x16554,
    0x056A0,
    0x09AD0,
    0x055D2,
    0x04AE0,
    0x0A5B6,
    0x0A4D0,
    0x0D250,
    0x1D255,
    0x0B540,
    0x0D6A0,
    0x0ADA2,
    0x095B0,
    0x14977,
    0x04970,
    0x0A4B0,
    0x0B4B5,
    0x06A50,
    0x06D40,
    0x1AB54,
    0x02B60,
    0x09570,
    0x052F2,
    0x04970,
    0x06566,
    0x0D4A0,
    0x0EA50,
    0x06E95,
    0x05AD0,
    0x02B60,
    0x186E3,
    0x092E0,
    0x1C8D7,
    0x0C950,
    0x0D4A0,
    0x1D8A6,
    0x0B550,
    0x056A0,
    0x1A5B4,
    0x025D0,
    0x092D0,
    0x0D2B2,
    0x0A950,
    0x0B557,
    0x06CA0,
    0x0B550,
    0x15355,
    0x04DA0,
    0x0A5D0,
    0x14573,
    0x052D0,
    0x0A9A8,
    0x0E950,
    0x06AA0,
    0x0AEA6,
    0x0AB50,
    0x04B60,
    0x0AAE4,
    0x0A570,
    0x05260,
    0x0F263,
    0x0D950,
    0x05B57,
    0x056A0,
    0x096D0,
    0x04DD5,
    0x04AD0,
    0x0A4D0,
    0x0D4D4,
    0x0D250,
    0x0D558,
    0x0B540,
    0x0B5A0,
    0x195A6,
    0x095B0,
    0x049B0,
    0x0A974,
    0x0A4B0,
    0x0B27A,
    0x06A50,
    0x06D40,
    0x0AF46,
    0x0AB60,
    0x09570,
    0x04AF5,
    0x04970,
    0x064B0,
    0x074A3,
    0x0EA50,
    0x06B58,
    0x05AC0,
    0x0AB60,
    0x096D5,
    0x092E0,
    0x0C960,
    0x0D954,
    0x0D4A0,
    0x0DA50,
    0x07552,
    0x056A0,
    0x0ABB7,
    0x025D0,
    0x092D0,
    0x0CAB5,
    0x0A950,
    0x0B4A0,
    0x0BAA4,
    0x0AD50,
    0x055D9,
    0x04BA0,
    0x0A5B0,
    0x15176,
    0x052B0,
    0x0A930,
    0x07954,
    0x06AA0,
    0x0AD50,
    0x05B52,
    0x04B60,
    0x0A6E6,
    0x0A4E0,
    0x0D260,
    0x0EA65,
    0x0D530,
    0x05AA0,
    0x076A3,
    0x096D0,
    0x04BD7,
    0x04AD0,
    0x0A4D0,
    0x1D0B6,
    0x0D250,
    0x0D520,
    0x0DD45,
    0x0B5A0,
    0x056D0,
    0x055B2,
    0x049B0,
    0x0A577,
    0x0A4B0,
    0x0AA50,
    0x1B255,
    0x06D20,
    0x0ADA0,
  ];

  static ChineseLunarDate fromSolar(DateTime date) {
    final solarDate = DateTime(date.year, date.month, date.day);
    if (solarDate.isBefore(_baseDate) || solarDate.year > _endYear) {
      return const ChineseLunarDate(
        year: 1900,
        month: 1,
        day: 1,
        isLeapMonth: false,
      );
    }

    var offset = solarDate.difference(_baseDate).inDays;
    var lunarYear = _startYear;

    while (lunarYear <= _endYear && offset >= _yearDays(lunarYear)) {
      offset -= _yearDays(lunarYear);
      lunarYear++;
    }

    final leapMonth = _leapMonth(lunarYear);
    var lunarMonth = 1;
    var isLeapMonth = false;

    while (lunarMonth <= 12) {
      final daysInMonth = isLeapMonth
          ? _leapDays(lunarYear)
          : _monthDays(lunarYear, lunarMonth);

      if (offset < daysInMonth) {
        break;
      }

      offset -= daysInMonth;

      if (leapMonth == lunarMonth && !isLeapMonth) {
        isLeapMonth = true;
      } else {
        if (isLeapMonth) {
          isLeapMonth = false;
        }
        lunarMonth++;
      }
    }

    return ChineseLunarDate(
      year: lunarYear,
      month: lunarMonth,
      day: offset + 1,
      isLeapMonth: isLeapMonth,
    );
  }

  static int _yearDays(int year) {
    var sum = 348;
    final info = _lunarInfo[year - _startYear];
    for (var mask = 0x8000; mask > 0x8; mask >>= 1) {
      if ((info & mask) != 0) {
        sum += 1;
      }
    }
    return sum + _leapDays(year);
  }

  static int _leapDays(int year) {
    if (_leapMonth(year) == 0) {
      return 0;
    }
    return (_lunarInfo[year - _startYear] & 0x10000) != 0 ? 30 : 29;
  }

  static int _leapMonth(int year) {
    return _lunarInfo[year - _startYear] & 0xF;
  }

  static int _monthDays(int year, int month) {
    return (_lunarInfo[year - _startYear] & (0x10000 >> month)) != 0 ? 30 : 29;
  }
}
