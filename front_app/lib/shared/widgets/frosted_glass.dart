import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';

/// 苹果 iOS 风格的毛玻璃容器：半透明材质、高斯模糊、顶部高光、噪点纹理。
///
/// 样式参数来自 [GlassSettings]：不传 [settings] 时读取全局配置
/// （`ResearchLifeController.glassSettings`），设置页修改后所有毛玻璃面板统一生效。
class FrostedGlass extends StatelessWidget {
  const FrostedGlass({
    required this.child,
    this.width,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 24,
    this.settings,
    super.key,
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final GlassSettings? settings;

  @override
  Widget build(BuildContext context) {
    final effective = settings ?? ResearchLifeScope.read(context).glassSettings;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effective.blurSigma,
          sigmaY: effective.blurSigma,
        ),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: effective.opacity),
                Colors.white.withValues(alpha: effective.opacity * 0.64),
              ],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: 0.5 + effective.opacity * 0.3,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (effective.noiseEnabled)
                Positioned.fill(
                  child: CustomPaint(painter: GlassNoisePainter()),
                ),
              if (effective.highlightEnabled)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(borderRadius),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.85),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃的细腻噪点纹理（固定种子，不随重绘变化）。
class GlassNoisePainter extends CustomPainter {
  const GlassNoisePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final whitePaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    final darkPaint = Paint()..color = Colors.black.withValues(alpha: 0.025);
    final random = math.Random(20260807);
    for (var index = 0; index < 280; index += 1) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = 0.4 + random.nextDouble() * 1.1;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        index.isEven ? whitePaint : darkPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
