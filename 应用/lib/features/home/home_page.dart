import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/weather_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/chinese_lunar.dart';
import '../../state/research_life_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late DateTime _now;
  late final AnimationController _weatherMotion;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _weatherMotion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = DateTime.now();
      if (!mounted) {
        return;
      }
      setState(() => _now = next);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ResearchLifeScope.of(context).ensureWeatherLoaded());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _weatherMotion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.of(context);
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final timeLabel = _formatTime(_now);
    final media = MediaQuery.of(context);
    final compact = media.size.width < 760;
    final snapshot = controller.weatherSnapshot;
    final condition = snapshot?.condition ?? WeatherCondition.unknown;
    final isDay = snapshot?.isDay ?? true;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.16),
          radius: 1.12,
          colors: _weatherGradientColors(tokens, condition, isDay),
          stops: const [0, 0.58, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: _WeatherBackdrop(
              animation: _weatherMotion,
              condition: condition,
              isDay: isDay,
              reduceMotion: media.disableAnimations,
              tokens: tokens,
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 28 : 56,
                vertical: 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Semantics(
                    label: '当前时间 $timeLabel',
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        timeLabel,
                        maxLines: 1,
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontSize: compact ? 92 : 156,
                          fontWeight: FontWeight.w700,
                          height: 0.95,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: compact ? 24 : 34),
                  Text(
                    _formatGregorianDate(_now),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontSize: compact ? 21 : 28,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _formatLunarDate(_now),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.textMuted,
                      fontSize: compact ? 18 : 23,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: compact ? 16 : 22,
            right: compact ? 16 : 24,
            left: compact ? 16 : null,
            child: Align(
              alignment: compact ? Alignment.topRight : Alignment.topRight,
              child: _WeatherStatusPill(
                snapshot: snapshot,
                location: controller.weatherLocation,
                busy: controller.weatherBusy,
                error: controller.weatherError,
                compact: compact,
                onRefresh: () => _refreshWeather(controller),
                onChooseCity: () => _openCityDialog(controller),
              ),
            ),
          ),
        ],
      ),
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
    final accent = switch (condition) {
      WeatherCondition.clear =>
        isDay ? const Color(0xFFFFF5D6) : const Color(0xFFEAF0FA),
      WeatherCondition.cloudy => const Color(0xFFE8EEF2),
      WeatherCondition.fog => const Color(0xFFE9ECE8),
      WeatherCondition.drizzle => const Color(0xFFE5EEF4),
      WeatherCondition.rain => const Color(0xFFDDEBF4),
      WeatherCondition.snow => const Color(0xFFF3F8FA),
      WeatherCondition.thunderstorm => const Color(0xFFD8E2EA),
      WeatherCondition.unknown => tokens.panelAccent,
    };

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

class _WeatherBackdrop extends StatelessWidget {
  const _WeatherBackdrop({
    required this.animation,
    required this.condition,
    required this.isDay,
    required this.reduceMotion,
    required this.tokens,
  });

  final Animation<double> animation;
  final WeatherCondition condition;
  final bool isDay;
  final bool reduceMotion;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return CustomPaint(
        painter: _WeatherPainter(
          condition: condition,
          isDay: isDay,
          progress: 0,
          tokens: tokens,
        ),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return CustomPaint(
          painter: _WeatherPainter(
            condition: condition,
            isDay: isDay,
            progress: animation.value,
            tokens: tokens,
          ),
        );
      },
    );
  }
}

class _WeatherPainter extends CustomPainter {
  const _WeatherPainter({
    required this.condition,
    required this.isDay,
    required this.progress,
    required this.tokens,
  });

  final WeatherCondition condition;
  final bool isDay;
  final double progress;
  final AppTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    _paintAmbient(canvas, size);

    switch (condition) {
      case WeatherCondition.clear:
        _paintClear(canvas, size);
      case WeatherCondition.cloudy:
        _paintClouds(canvas, size, opacity: 0.42);
      case WeatherCondition.fog:
        _paintFog(canvas, size);
      case WeatherCondition.drizzle:
        _paintClouds(canvas, size, opacity: 0.35);
        _paintRain(canvas, size, count: 74, intensity: 0.54);
      case WeatherCondition.rain:
        _paintClouds(canvas, size, opacity: 0.46);
        _paintRain(canvas, size, count: 156, intensity: 0.9);
      case WeatherCondition.snow:
        _paintClouds(canvas, size, opacity: 0.28);
        _paintSnow(canvas, size);
      case WeatherCondition.thunderstorm:
        _paintClouds(canvas, size, opacity: 0.54);
        _paintRain(canvas, size, count: 184, intensity: 1);
        _paintLightning(canvas, size);
      case WeatherCondition.unknown:
        _paintClouds(canvas, size, opacity: 0.18);
    }
  }

  void _paintAmbient(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isDay ? 0.16 : 0.05),
          tokens.panelSurface.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _paintClear(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.78, size.height * 0.24);
    final radius = math.min(size.shortestSide * 0.18, 112.0);
    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD36D).withValues(alpha: isDay ? 0.34 : 0.12),
          const Color(0xFFFFF3C4).withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 2.4));
    canvas.drawCircle(center, radius * (2.05 + pulse * 0.08), glowPaint);

    final sunPaint = Paint()
      ..color = (isDay ? const Color(0xFFFFD36D) : const Color(0xFFE7EDF8))
          .withValues(alpha: isDay ? 0.28 : 0.18);
    canvas.drawCircle(center, radius * 0.52, sunPaint);
  }

  void _paintClouds(Canvas canvas, Size size, {required double opacity}) {
    final cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final shadowPaint = Paint()
      ..color = const Color(0xFF7C8A94).withValues(alpha: opacity * 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    for (var i = 0; i < 5; i++) {
      final width = size.width * (0.28 + i * 0.025);
      final height = 52.0 + i * 11;
      final baseX =
          ((i * 0.23 + progress * (0.015 + i * 0.004)) % 1.32 - 0.16) *
          size.width;
      final y = size.height * (0.1 + i * 0.08);
      _drawCloud(canvas, Offset(baseX, y), Size(width, height), shadowPaint);
      _drawCloud(
        canvas,
        Offset(baseX - size.width * 0.015, y - 4),
        Size(width, height),
        cloudPaint,
      );
    }
  }

  void _drawCloud(Canvas canvas, Offset origin, Size size, Paint paint) {
    final rect = Rect.fromLTWH(
      origin.dx,
      origin.dy + size.height * 0.36,
      size.width,
      size.height * 0.42,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height)),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: origin + Offset(size.width * 0.28, size.height * 0.38),
        width: size.width * 0.42,
        height: size.height * 0.72,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: origin + Offset(size.width * 0.56, size.height * 0.3),
        width: size.width * 0.5,
        height: size.height * 0.86,
      ),
      paint,
    );
  }

  void _paintRain(
    Canvas canvas,
    Size size, {
    required int count,
    required double intensity,
  }) {
    final random = math.Random(23);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.srcOver;

    for (var i = 0; i < count; i++) {
      final layer = random.nextDouble();
      final speed = 0.52 + layer * 0.78;
      final startX = random.nextDouble() * (size.width + 180) - 90;
      final drift = progress * (60 + layer * 80);
      final x = (startX + drift) % (size.width + 160) - 80;
      final y =
          ((random.nextDouble() + progress * speed) % 1) * (size.height + 170) -
          92;
      final length = 17 + layer * 30 * intensity;
      final slant = 9 + layer * 16;

      paint
        ..strokeWidth = 0.65 + layer * 1.25
        ..color = const Color(
          0xFF5D7F98,
        ).withValues(alpha: (0.18 + layer * 0.24) * intensity);
      canvas.drawLine(Offset(x, y), Offset(x - slant, y + length), paint);
    }

    final splashPaint = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF6E8FA6).withValues(alpha: 0.12 * intensity);
    for (var i = 0; i < 26; i++) {
      final seed = i * 37.7;
      final x = ((seed * 11 + progress * 70) % size.width);
      final y = size.height * (0.84 + 0.12 * math.sin(seed));
      canvas.drawLine(Offset(x - 5, y), Offset(x + 5, y - 1.5), splashPaint);
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final random = math.Random(61);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.72);

    for (var i = 0; i < 94; i++) {
      final layer = random.nextDouble();
      final radius = 1.2 + layer * 2.6;
      final speed = 0.12 + layer * 0.28;
      final y =
          ((random.nextDouble() + progress * speed) % 1) * (size.height + 70) -
          35;
      final baseX = random.nextDouble() * size.width;
      final drift = math.sin((progress * math.pi * 2) + i) * (10 + layer * 18);
      paint.color = Colors.white.withValues(alpha: 0.26 + layer * 0.5);
      canvas.drawCircle(Offset(baseX + drift, y), radius, paint);
    }
  }

  void _paintFog(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.23);
    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.16 + i * 0.085);
      final offset = math.sin(progress * math.pi * 2 + i) * 28;
      final rect = Rect.fromLTWH(
        -size.width * 0.12 + offset,
        y,
        size.width * 1.24,
        24 + i * 1.4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(999)),
        paint,
      );
    }
  }

  void _paintLightning(Canvas canvas, Size size) {
    final phase = (progress * 3) % 1;
    if (phase < 0.84) {
      return;
    }

    final opacity = (1 - ((phase - 0.84) / 0.16)).clamp(0.0, 1.0);
    final flashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16 * opacity);
    canvas.drawRect(Offset.zero & size, flashPaint);

    final boltPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFF6B8).withValues(alpha: 0.5 * opacity);
    final start = Offset(size.width * 0.68, size.height * 0.1);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(start.dx - 24, start.dy + 54)
      ..lineTo(start.dx + 4, start.dy + 44)
      ..lineTo(start.dx - 28, start.dy + 118);
    canvas.drawPath(path, boltPaint);
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter oldDelegate) {
    return oldDelegate.condition != condition ||
        oldDelegate.isDay != isDay ||
        oldDelegate.progress != progress ||
        oldDelegate.tokens != tokens;
  }
}
