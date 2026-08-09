import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/research_life_scope.dart';
import '../../core/theme/app_tokens.dart';

/// PIN 锁屏门：锁定状态显示解锁页，否则显示正常内容。
class PinLockGate extends StatelessWidget {
  const PinLockGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.pinLockEnabled && controller.isLocked) {
          return const UnlockPage();
        }
        return child;
      },
    );
  }
}

/// 解锁页面：输入 PIN 进入主界面。
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final FocusNode _pinFocusNode = FocusNode();
  String _pin = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _pinFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _pinFocusNode.dispose();
    super.dispose();
  }

  /// 直接处理物理键盘按键（主键盘 + 小键盘数字、退格），
  /// 不依赖隐藏输入框的 IME 连接，因此与窗口大小/激活状态无关。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      if (_pin.isNotEmpty) {
        setState(() {
          _pin = _pin.substring(0, _pin.length - 1);
          _error = null;
        });
      }
      return KeyEventResult.handled;
    }
    final digit = _digitFromKey(key);
    if (digit != null) {
      if (_pin.length < 6) {
        final next = _pin + digit;
        setState(() {
          _pin = next;
          _error = null;
        });
        // Windows 风格：输入满 6 位自动检测。
        if (next.length == 6) {
          _autoVerify(next);
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 将主键盘/小键盘的数字键映射为数字字符，非数字键返回 null。
  static String? _digitFromKey(LogicalKeyboardKey key) {
    final id = key.keyId;
    if (id >= LogicalKeyboardKey.digit0.keyId &&
        id <= LogicalKeyboardKey.digit9.keyId) {
      return String.fromCharCode(id - LogicalKeyboardKey.digit0.keyId + 0x30);
    }
    if (id >= LogicalKeyboardKey.numpad0.keyId &&
        id <= LogicalKeyboardKey.numpad9.keyId) {
      return String.fromCharCode(id - LogicalKeyboardKey.numpad0.keyId + 0x30);
    }
    return null;
  }

  void _autoVerify(String pin) {
    final controller = ResearchLifeScope.of(context);
    if (controller.verifyPin(pin)) {
      return; // 解锁成功后 UnlockPage 会被替换移除。
    }
    setState(() {
      _error = 'PIN 不正确，请重试。';
      _pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Focus(
        focusNode: _pinFocusNode,
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          onTap: () => _pinFocusNode.requestFocus(),
          child: Center(
            child: Container(
              width: 380,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: tokens.panelSurface,
                borderRadius: BorderRadius.circular(tokens.radiusXLarge),
                border: Border.all(color: tokens.borderFaint),
                boxShadow: tokens.shadowMd,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 28,
                      color: tokens.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '研究生活已锁定',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '请输入 6 位 PIN 解锁',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 6 个 PIN 格子（Windows 风格）。
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < 6; index += 1)
                        Container(
                          width: 44,
                          height: 54,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: tokens.panelSubtle,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _error != null
                                  ? const Color(0xFFE5484D)
                                  : index < _pin.length
                                  ? tokens.accent
                                  : index == _pin.length
                                  ? tokens.accent.withValues(alpha: 0.6)
                                  : tokens.borderFaint,
                              width: index == _pin.length ? 1.5 : 1,
                            ),
                          ),
                          child: Center(
                            child: index < _pin.length
                                ? Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: tokens.accent,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 20,
                    child: Text(
                      _error ?? ' ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFE5484D),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '长时间未操作或重启后需要输入 PIN。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
