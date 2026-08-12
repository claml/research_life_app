import 'dart:async';
import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/models/weather_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/chinese_lunar.dart';
import '../../shared/widgets/frosted_glass.dart';
import '../../state/research_life_controller.dart';
import 'weather_palette.dart';

String weatherBackgroundAssetFor(WeatherCondition condition) {
  return switch (condition) {
    WeatherCondition.clear => 'assets/weather/clear.png',
    WeatherCondition.cloudy => 'assets/weather/cloudscape.png',
    WeatherCondition.fog => 'assets/weather/fog.png',
    WeatherCondition.dust => 'assets/weather/dust.png',
    WeatherCondition.drizzle => 'assets/weather/drizzle.png',
    WeatherCondition.rain => 'assets/weather/rain.png',
    WeatherCondition.snow => 'assets/weather/snow.png',
    WeatherCondition.thunderstorm => 'assets/weather/thunderstorm.png',
    WeatherCondition.unknown => 'assets/weather/unknown.png',
  };
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ResearchLifeScope.of(context).ensureWeatherLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final media = MediaQuery.of(context);
    final compact = media.size.width < 760;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.weatherSnapshot;
        final condition = snapshot?.condition ?? WeatherCondition.unknown;
        final isDay = snapshot?.isDay ?? true;
        final foreground = <Widget>[
          Positioned(
            left: compact ? 18 : 54,
            top: compact ? 18 : 44,
            right: compact ? 18 : null,
            width: compact ? null : 420,
            child: ConstrainedBox(
              key: const Key('weather-standby-panel'),
              constraints: BoxConstraints(
                maxHeight: compact ? media.size.height - 36 : 620,
              ),
              child: _StandbyGlassPanel(
                compact: compact,
                theme: theme,
                tokens: tokens,
                snapshot: snapshot,
                location: controller.weatherLocation,
                busy: controller.weatherBusy,
                error: controller.weatherError,
                todoEvents: controller.showHomeTodoHint
                    ? controller.todayTodoEvents
                    : const [],
                onRefresh: () => _refreshWeather(controller),
                onChooseCity: () => _openCityDialog(controller),
                onDismissTodo: () => controller.dismissHomeTodoHint(),
              ),
            ),
          ),
        ];

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              weatherBackgroundAssetFor(condition),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.09),
                    _weatherGradientColors(
                      tokens,
                      condition,
                      isDay,
                    ).last.withValues(alpha: 0.13),
                    Colors.black.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
            ...foreground,
          ],
        );
      },
    );
  }

  Future<void> _refreshWeather(ResearchLifeController controller) async {
    final message = await controller.refreshWeather();
    if (!mounted) {
      return;
    }
    _showMessage(message);
  }

  Future<void> _openCityDialog(ResearchLifeController controller) async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _WeatherCityDialog(controller: controller),
    );
    if (!mounted || message == null || message.trim().isEmpty) {
      return;
    }
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  static List<Color> _weatherGradientColors(
    AppTokens tokens,
    WeatherCondition condition,
    bool isDay,
  ) {
    final accent =
        WeatherPalette.tintFor(condition, isDay: isDay) ?? tokens.panelAccent;

    return [
      Color.lerp(tokens.panelAccent, accent, 0.72)!,
      Color.lerp(tokens.panelSurface, accent, 0.32)!,
      Color.lerp(tokens.panelSubtle, accent, 0.44)!,
    ];
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static String _formatGregorianDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日 ${_weekdayLabel(date)}';
  }

  static String _formatLunarDate(DateTime date) {
    final lunar = ChineseLunarCalendar.fromSolar(date);
    return '农历 ${_stemBranchYear(lunar.year)}年 ${lunar.fullLabel}';
  }

  static String _weekdayLabel(DateTime date) {
    const labels = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '星期${labels[date.weekday - 1]}';
  }

  static String _stemBranchYear(int year) {
    const stems = <String>['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
    const branches = <String>[
      '子',
      '丑',
      '寅',
      '卯',
      '辰',
      '巳',
      '午',
      '未',
      '申',
      '酉',
      '戌',
      '亥',
    ];
    final offset = year - 4;
    return '${stems[offset % stems.length]}${branches[offset % branches.length]}';
  }
}

class _StandbyGlassPanel extends StatelessWidget {
  const _StandbyGlassPanel({
    required this.compact,
    required this.theme,
    required this.tokens,
    required this.snapshot,
    required this.location,
    required this.busy,
    required this.error,
    required this.todoEvents,
    required this.onRefresh,
    required this.onChooseCity,
    required this.onDismissTodo,
  });

  final bool compact;
  final ThemeData theme;
  final AppTokens tokens;
  final WeatherSnapshot? snapshot;
  final WeatherLocation? location;
  final bool busy;
  final String? error;
  final List<EventItem> todoEvents;
  final VoidCallback onRefresh;
  final VoidCallback onChooseCity;
  final VoidCallback onDismissTodo;

  @override
  Widget build(BuildContext context) {
    return FrostedGlass(
      borderRadius: compact ? 24 : 28,
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 30,
        compact ? 22 : 26,
        compact ? 22 : 30,
        compact ? 22 : 26,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '研LIFE',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: tokens.accent,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '科研与生活，各留一半。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
            SizedBox(height: compact ? 22 : 28),
            _HomeClockDisplay(compact: compact, theme: theme, tokens: tokens),
            SizedBox(height: compact ? 18 : 22),
            Divider(color: tokens.borderSoft),
            const SizedBox(height: 14),
            _WeatherStatusPill(
              snapshot: snapshot,
              location: location,
              busy: busy,
              error: error,
              compact: compact,
              onRefresh: onRefresh,
              onChooseCity: onChooseCity,
            ),
            if (todoEvents.isNotEmpty) ...[
              const SizedBox(height: 14),
              _TodoGlassHint(
                events: todoEvents,
                compact: compact,
                onDismiss: onDismissTodo,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 时钟独立刷新，避免天气等控制器更新时重绘整页动画层。
class _HomeClockDisplay extends StatefulWidget {
  const _HomeClockDisplay({
    required this.compact,
    required this.theme,
    required this.tokens,
  });

  final bool compact;
  final ThemeData theme;
  final AppTokens tokens;

  @override
  State<_HomeClockDisplay> createState() => _HomeClockDisplayState();
}

class _HomeClockDisplayState extends State<_HomeClockDisplay> {
  late DateTime _now;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = _HomePageState._formatTime(_now);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '当前时间 $timeLabel',
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              timeLabel,
              maxLines: 1,
              style: widget.theme.textTheme.displayLarge?.copyWith(
                color: widget.tokens.textPrimary,
                fontSize: widget.compact ? 72 : 96,
                fontWeight: FontWeight.w500,
                height: 0.95,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        SizedBox(height: widget.compact ? 16 : 20),
        Text(
          _HomePageState._formatGregorianDate(_now),
          textAlign: TextAlign.left,
          style: widget.theme.textTheme.headlineSmall?.copyWith(
            color: widget.tokens.textSecondary,
            fontSize: widget.compact ? 18 : 22,
            fontWeight: FontWeight.w600,
            height: 1.25,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _HomePageState._formatLunarDate(_now),
          textAlign: TextAlign.left,
          style: widget.theme.textTheme.titleLarge?.copyWith(
            color: widget.tokens.textMuted,
            fontSize: widget.compact ? 15 : 17,
            fontWeight: FontWeight.w500,
            height: 1.3,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _WeatherStatusPill extends StatelessWidget {
  const _WeatherStatusPill({
    required this.snapshot,
    required this.location,
    required this.busy,
    required this.error,
    required this.compact,
    required this.onRefresh,
    required this.onChooseCity,
  });

  final WeatherSnapshot? snapshot;
  final WeatherLocation? location;
  final bool busy;
  final String? error;
  final bool compact;
  final VoidCallback onRefresh;
  final VoidCallback onChooseCity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final snapshot = this.snapshot;
    final title = snapshot == null
        ? (busy ? '定位天气' : '天气暂不可用')
        : '${snapshot.location.city} ${snapshot.temperatureLabel}';
    final detail = snapshot == null
        ? (error ?? '点击选择城市')
        : '${snapshot.condition.label} · ${_formatUpdateTime(snapshot.fetchedAt)}';

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 360 : 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.panelSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
          boxShadow: [
            BoxShadow(
              color: tokens.textPrimary.withValues(alpha: 0.06),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: busy && snapshot == null
                    ? Padding(
                        padding: const EdgeInsets.all(5),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tokens.accent,
                        ),
                      )
                    : Icon(
                        _weatherIcon(snapshot?.condition),
                        color: tokens.accent,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Tooltip(
                  message: snapshot?.detailLabel ?? error ?? '选择城市查看天气',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textMuted,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: '刷新天气',
                  child: IconButton(
                    onPressed: busy ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(30, 30),
                      foregroundColor: tokens.textMuted,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
              ],
              Tooltip(
                message: '选择城市',
                child: IconButton(
                  onPressed: onChooseCity,
                  icon: const Icon(Icons.more_horiz_rounded, size: 19),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(30, 30),
                    foregroundColor: tokens.textMuted,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _weatherIcon(WeatherCondition? condition) {
    return switch (condition) {
      WeatherCondition.clear => Icons.wb_sunny_outlined,
      WeatherCondition.cloudy => Icons.cloud_outlined,
      WeatherCondition.fog => Icons.foggy,
      WeatherCondition.dust => Icons.air_rounded,
      WeatherCondition.drizzle => Icons.grain_rounded,
      WeatherCondition.rain => Icons.water_drop_outlined,
      WeatherCondition.snow => Icons.ac_unit_rounded,
      WeatherCondition.thunderstorm => Icons.thunderstorm_outlined,
      _ => Icons.cloud_queue_rounded,
    };
  }

  static String _formatUpdateTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute 更新';
  }
}

/// 首页天气区的今日待办玻璃提示（桌宠未开启时弹出）。
/// 样式：苹果 iOS 毛玻璃 —— 半透明材质、强模糊、顶部高光、噪点纹理。
class _TodoGlassHint extends StatelessWidget {
  const _TodoGlassHint({
    required this.events,
    required this.compact,
    required this.onDismiss,
  });

  final List<EventItem> events;
  final bool compact;
  final VoidCallback onDismiss;

  static Color _priorityColor(TodoPriority priority) => switch (priority) {
    TodoPriority.high => const Color(0xFFE5484D),
    TodoPriority.medium => const Color(0xFFF76B15),
    TodoPriority.low => const Color(0xFF3E63DD),
    TodoPriority.none => const Color(0xFF9AA4B2),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = events.take(3).toList();
    final primaryColor = theme.colorScheme.onSurface;
    final mutedColor = primaryColor.withValues(alpha: 0.62);

    return FrostedGlass(
      borderRadius: 26,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 360 : 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.task_alt_rounded,
                  size: 18,
                  color: const Color(0xFF2F7D4F),
                ),
                const SizedBox(width: 8),
                Text(
                  '今日待办 ${shown.length} 项',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: mutedColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final event in shown) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _priorityColor(event.priority),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: primaryColor,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              if (event != shown.last) const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            Text(
              '更多待办请前往「待办」页查看',
              style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherCityDialog extends StatefulWidget {
  const _WeatherCityDialog({required this.controller});

  final ResearchLifeController controller;

  @override
  State<_WeatherCityDialog> createState() => _WeatherCityDialogState();
}

class _WeatherCityDialogState extends State<_WeatherCityDialog> {
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  List<WeatherLocation> _results = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('选择天气城市'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: '搜索城市，例如 北京、上海、杭州',
              ),
              onSubmitted: _search,
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _busy
                  ? LinearProgressIndicator(color: tokens.accent)
                  : const SizedBox(height: 4),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _buildResultList(context, theme, tokens),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _busy ? null : _useAutomaticLocation,
          icon: const Icon(Icons.my_location_rounded),
          label: const Text('当前位置'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildResultList(
    BuildContext context,
    ThemeData theme,
    AppTokens tokens,
  ) {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    if (_results.isEmpty) {
      final hint = _queryController.text.trim().length < 2
          ? '输入至少 2 个字搜索城市'
          : '没有找到匹配城市';
      return Center(
        child: Text(
          hint,
          style: theme.textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (context, index) => Divider(color: tokens.borderFaint),
      itemBuilder: (context, index) {
        final location = _results[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(location.city),
          subtitle: Text(location.displayName),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _busy ? null : () => _selectLocation(location),
        );
      },
    );
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    final query = _queryController.text.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 420), () => _search(query));
  }

  Future<void> _search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final results = await widget.controller.searchWeatherLocations(
      normalizedQuery,
    );

    if (!mounted || normalizedQuery != _queryController.text.trim()) {
      return;
    }
    setState(() {
      _results = results;
      _error = widget.controller.weatherError;
      _busy = false;
    });
  }

  Future<void> _selectLocation(WeatherLocation location) async {
    setState(() => _busy = true);
    final message = await widget.controller.useWeatherLocation(location);
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(message);
  }

  Future<void> _useAutomaticLocation() async {
    setState(() => _busy = true);
    final message = await widget.controller.useAutomaticWeatherLocation();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(message);
  }
}
