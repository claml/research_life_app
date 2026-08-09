import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/research_life_scope.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/pet/pet_companion_service.dart';

class PetOverlay extends StatefulWidget {
  const PetOverlay({super.key});

  @override
  State<PetOverlay> createState() => _PetOverlayState();
}

class _PetOverlayState extends State<PetOverlay> {
  static const _petSize = Size(128, 139);

  Offset? _position;
  Offset? _dragStartPointer;
  Offset? _dragStartPosition;

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final tokens = context.tokens;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final pet = controller.activePet;
          if (!controller.petRunning || pet == null) {
            return const SizedBox.shrink();
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final position =
                  _position ?? _defaultPosition(constraints.biggest);
              final clamped = _clampPosition(position, constraints.biggest);
              if (clamped != position) {
                _position = clamped;
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: clamped.dx,
                    top: clamped.dy,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => unawaited(controller.sendPetTestMessage()),
                      onPanStart: (details) {
                        _dragStartPointer = details.globalPosition;
                        _dragStartPosition = clamped;
                      },
                      onPanUpdate: (details) {
                        final dragStartPointer = _dragStartPointer;
                        final dragStartPosition = _dragStartPosition;
                        if (dragStartPointer == null ||
                            dragStartPosition == null) {
                          return;
                        }
                        final dragDelta =
                            details.globalPosition - dragStartPointer;
                        setState(() {
                          _position = _clampPosition(
                            dragStartPosition + dragDelta,
                            constraints.biggest,
                          );
                        });
                      },
                      onPanEnd: (_) {
                        _dragStartPointer = null;
                        _dragStartPosition = null;
                      },
                      onPanCancel: () {
                        _dragStartPointer = null;
                        _dragStartPosition = null;
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (controller.petBubbleText != null) ...[
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: tokens.panelSurface.withValues(
                                    alpha: 0.96,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusMedium,
                                  ),
                                  border: Border.all(color: tokens.borderFaint),
                                  boxShadow: tokens.shadowSm,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    controller.petBubbleText!,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: tokens.textPrimary,
                                          height: 1.45,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: SizedBox(
                              width: _petSize.width,
                              height: _petSize.height,
                              child: _PetSprite(
                                pet: pet,
                                animationState: controller.petAnimationState,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Offset _defaultPosition(Size bounds) {
    final minimumX = math.min(16.0, bounds.width);
    final minimumY = math.min(16.0, bounds.height);
    return Offset(
      (bounds.width - _petSize.width - 40)
          .clamp(minimumX, bounds.width)
          .toDouble(),
      (bounds.height - _petSize.height - 40)
          .clamp(minimumY, bounds.height)
          .toDouble(),
    );
  }

  Offset _clampPosition(Offset position, Size bounds) {
    final maxX = (bounds.width - _petSize.width).clamp(0, bounds.width);
    final maxY = (bounds.height - _petSize.height).clamp(0, bounds.height);
    return Offset(
      position.dx.clamp(0, maxX).toDouble(),
      position.dy.clamp(0, maxY).toDouble(),
    );
  }
}

class _PetSprite extends StatefulWidget {
  const _PetSprite({required this.pet, required this.animationState});

  final PetDefinition pet;
  final String animationState;

  @override
  State<_PetSprite> createState() => _PetSpriteState();
}

class _PetSpriteState extends State<_PetSprite> {
  static const _frameDuration = Duration(milliseconds: 150);

  Timer? _timer;
  ui.Image? _image;
  int _frame = 0;
  String? _loadedPath;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadImage();
    _timer = Timer.periodic(_frameDuration, (_) {
      if (mounted) {
        setState(() => _frame += 1);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PetSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pet.spritesheetPath != widget.pet.spritesheetPath ||
        oldWidget.pet.source != widget.pet.source) {
      _frame = 0;
      _loadImage();
    }
    if (oldWidget.animationState != widget.animationState) {
      _frame = 0;
    }
  }

  Future<void> _loadImage() async {
    final path = widget.pet.spritesheetPath;
    try {
      final bytes = widget.pet.isAsset
          ? (await rootBundle.load(path)).buffer.asUint8List()
          : await File(path).readAsBytes();
      final image = await _decodeImage(bytes);
      if (!mounted || path != widget.pet.spritesheetPath) {
        image.dispose();
        return;
      }
      _image?.dispose();
      setState(() {
        _image = image;
        _loadedPath = path;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _image = null;
        _loadedPath = path;
        _loadError = error;
      });
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return Center(
        child: Icon(
          _loadError == null ? Icons.pets_rounded : Icons.broken_image_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    return CustomPaint(
      painter: _PetSpritePainter(
        image: image,
        loadedPath: _loadedPath,
        state: widget.animationState,
        frame: _frame,
      ),
      size: const Size(192, 208),
    );
  }
}

class _PetSpritePainter extends CustomPainter {
  const _PetSpritePainter({
    required this.image,
    required this.loadedPath,
    required this.state,
    required this.frame,
  });

  static const cellWidth = 192.0;
  static const cellHeight = 208.0;
  static const stateSpecs = <String, ({int row, int frames})>{
    'idle': (row: 0, frames: 6),
    'running-right': (row: 1, frames: 8),
    'running-left': (row: 2, frames: 8),
    'waving': (row: 3, frames: 4),
    'jumping': (row: 4, frames: 5),
    'failed': (row: 5, frames: 8),
    'waiting': (row: 6, frames: 6),
    'running': (row: 7, frames: 6),
    'review': (row: 8, frames: 6),
  };

  final ui.Image image;
  final String? loadedPath;
  final String state;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) {
    final spec = stateSpecs[state] ?? stateSpecs['idle']!;
    final column = frame % spec.frames;
    final source = Rect.fromLTWH(
      column * cellWidth,
      spec.row * cellHeight,
      cellWidth,
      cellHeight,
    );
    final destination = _fitRect(Size(cellWidth, cellHeight), size);
    canvas.drawImageRect(image, source, destination, Paint());
  }

  Rect _fitRect(Size source, Size bounds) {
    final scale = (bounds.width / source.width)
        .clamp(0, bounds.height / source.height)
        .toDouble();
    final width = source.width * scale;
    final height = source.height * scale;
    return Rect.fromLTWH(
      (bounds.width - width) / 2,
      (bounds.height - height) / 2,
      width,
      height,
    );
  }

  @override
  bool shouldRepaint(covariant _PetSpritePainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.state != state ||
        oldDelegate.image != image ||
        oldDelegate.loadedPath != loadedPath;
  }
}
