import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/app_tokens.dart';

/// Product-owned desktop chrome used when the native Windows title bar is hidden.
class AppWindowFrame extends StatelessWidget {
  const AppWindowFrame({
    required this.child,
    this.forceEnabled = false,
    super.key,
  });

  final Widget child;
  final bool forceEnabled;

  @override
  Widget build(BuildContext context) {
    if (!forceEnabled && !Platform.isWindows) {
      return child;
    }
    final tokens = context.tokens;
    return ColoredBox(
      color: tokens.shellSurface,
      child: Column(
        children: [
          SizedBox(
            key: const Key('app-window-titlebar'),
            height: 38,
            child: Material(
              color: tokens.shellSurface,
              shape: Border(bottom: BorderSide(color: tokens.borderFaint)),
              child: Row(
                children: [
                  Expanded(
                    child: DragToMoveArea(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 16,
                              color: tokens.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '研LIFE',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _WindowControlButton(
                    tooltip: '最小化',
                    icon: Icons.remove_rounded,
                    onPressed: windowManager.minimize,
                  ),
                  _WindowControlButton(
                    tooltip: '最大化或还原',
                    icon: Icons.crop_square_rounded,
                    onPressed: () async {
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                  _WindowControlButton(
                    tooltip: '关闭',
                    icon: Icons.close_rounded,
                    danger: true,
                    onPressed: windowManager.close,
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WindowControlButton extends StatelessWidget {
  const _WindowControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        hoverColor: danger
            ? tokens.danger.withValues(alpha: 0.14)
            : tokens.accent.withValues(alpha: 0.08),
        child: SizedBox(
          width: 46,
          height: 38,
          child: Icon(
            icon,
            size: 18,
            color: danger ? tokens.danger : tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}
