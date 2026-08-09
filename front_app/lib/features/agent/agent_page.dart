import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/auth_scope.dart';
import '../../app/research_life_scope.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_api.dart';
import '../../services/agent/agent_models.dart';
import '../../state/auth_controller.dart';
import 'state/agent_controller.dart';

class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  AgentController? _controller;
  bool _sidebarCollapsed = false;
  bool _agentSettingsRequested = false;

  void _collapseSidebar() => setState(() => _sidebarCollapsed = true);

  void _expandSidebar() => setState(() => _sidebarCollapsed = false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 避免在 build 期间触发 controller 通知（setState during build）。
    if (!_agentSettingsRequested) {
      _agentSettingsRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(ResearchLifeScope.of(context).ensureAgentLlmSettingsLoaded());
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.read(context);
    final life = ResearchLifeScope.read(context);

    _controller ??= AgentController(
      api: AgentApi(
        ApiClient(
          accessTokenReader: () => AuthController.accessToken,
          onUnauthorized: auth.refreshSessionAfterUnauthorized,
        ),
      ),
    )..bootstrap();

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) {
        final controller = _controller!;
        return ColoredBox(
          color: context.tokens.canvas,
          child: Row(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _sidebarCollapsed
                    ? _SidebarCollapsedStrip(onExpand: _expandSidebar)
                    : _HistorySidebar(
                        controller: controller,
                        onNewChat: () => controller.startNewSession(),
                        onOpen: controller.openSession,
                        onDelete: controller.deleteSession,
                        onCollapse: _collapseSidebar,
                      ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child:
                          controller.loadingMessages &&
                              controller.messages.isEmpty
                          ? Center(
                              child: CircularProgressIndicator(
                                color: context.tokens.accent,
                              ),
                            )
                          : controller.messages.isEmpty
                          ? _WelcomePanel(
                              mode: controller.mode,
                              deepThinking: controller.deepThinking,
                              onModeChanged: controller.setMode,
                              onDeepThinkingChanged: controller.setDeepThinking,
                            )
                          : _MessageList(
                              controller: controller,
                              scrollController: _scrollController,
                            ),
                    ),
                    if (controller.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          controller.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    _Composer(
                      controller: _inputController,
                      sending: controller.sending,
                      mode: controller.mode,
                      deepThinking: controller.deepThinking,
                      onModeChanged: controller.setMode,
                      onDeepThinkingChanged: controller.setDeepThinking,
                      onSend: () async {
                        final text = _inputController.text;
                        _inputController.clear();
                        await controller.sendMessage(
                          text,
                          llmSettings: life.agentLlmSettings,
                        );
                        if (_scrollController.hasClients) {
                          await Future<void>.delayed(
                            const Duration(milliseconds: 80),
                          );
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistorySidebar extends StatelessWidget {
  const _HistorySidebar({
    required this.controller,
    required this.onNewChat,
    required this.onOpen,
    required this.onDelete,
    required this.onCollapse,
  });

  final AgentController controller;
  final VoidCallback onNewChat;
  final Future<void> Function(int sessionId) onOpen;
  final Future<void> Function(int sessionId) onDelete;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: tokens.sidebarSurface,
        border: Border(right: BorderSide(color: tokens.borderFaint)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.isBusy ? null : onNewChat,
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('新对话'),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '收起历史记录',
                  onPressed: onCollapse,
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '历史记录',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: controller.loadingSessions && controller.sessions.isEmpty
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.accent,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: controller.sessions.length,
                    itemBuilder: (context, index) {
                      final session = controller.sessions[index];
                      final selected =
                          controller.currentSessionId == session.id;
                      return _HistoryTile(
                        title: session.title,
                        selected: selected,
                        onTap: () => onOpen(session.id),
                        onDelete: () => onDelete(session.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SidebarCollapsedStrip extends StatelessWidget {
  const _SidebarCollapsedStrip({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: double.infinity,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: IconButton(
            tooltip: '展开历史记录',
            onPressed: onExpand,
            icon: Icon(
              Icons.chevron_right_rounded,
              color: tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.title,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: selected ? tokens.sidebarSelected : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({
    required this.mode,
    required this.deepThinking,
    required this.onModeChanged,
    required this.onDeepThinkingChanged,
  });

  final AgentChatMode mode;
  final bool deepThinking;
  final ValueChanged<AgentChatMode> onModeChanged;
  final ValueChanged<bool> onDeepThinkingChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 40,
              color: tokens.accent.withValues(alpha: 0.9),
            ),
            const SizedBox(height: 16),
            Text(
              '使用快速模式开始对话',
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            _ModeSwitcher(mode: mode, onChanged: onModeChanged),
            const SizedBox(height: 16),
            _ToggleChip(
              label: '深度思考',
              icon: Icons.hub_outlined,
              selected: deepThinking,
              onTap: () => onDeepThinkingChanged(!deepThinking),
            ),
            const SizedBox(height: 12),
            Text(
              '我是研LIFE助手，可解答文献阅读、笔记、文件与日历等相关问题。',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.scrollController,
  });

  final AgentController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
      itemCount: controller.messages.length + (controller.sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= controller.messages.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text('思考中…', style: TextStyle(color: tokens.textMuted)),
              ],
            ),
          );
        }
        final message = controller.messages[index];
        return _MessageBubble(message: message);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AgentChatMessage message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final isUser = message.isUser;
    final reasoning = message.reasoningContent;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUser ? tokens.accentSoft : tokens.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderFaint),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reasoning != null && reasoning.isNotEmpty) ...[
              Text(
                '推理过程',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                reasoning,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Divider(color: tokens.borderFaint, height: 1),
              const SizedBox(height: 10),
            ],
            SelectableText(
              message.content,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.mode,
    required this.deepThinking,
    required this.onModeChanged,
    required this.onDeepThinkingChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final AgentChatMode mode;
  final bool deepThinking;
  final ValueChanged<AgentChatMode> onModeChanged;
  final ValueChanged<bool> onDeepThinkingChanged;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _send() {
    if (widget.sending || widget.controller.text.trim().isEmpty) {
      return;
    }
    widget.onSend();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.sending) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          _ModeSwitcher(mode: widget.mode, onChanged: widget.onModeChanged),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: tokens.panelSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _focused
                    ? tokens.accent.withValues(alpha: 0.85)
                    : tokens.borderFaint,
                width: _focused ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  minLines: 2,
                  maxLines: 6,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  cursorColor: tokens.accent,
                  decoration: InputDecoration(
                    hintText: '给研LIFE 助手发送消息（回车发送，Shift+回车换行）',
                    hintStyle: TextStyle(color: tokens.textMuted),
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ToggleChip(
                      label: '深度思考',
                      icon: Icons.hub_outlined,
                      selected: widget.deepThinking,
                      onTap: () =>
                          widget.onDeepThinkingChanged(!widget.deepThinking),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: widget.sending ? null : _send,
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 44),
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      child: widget.sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.mode, required this.onChanged});

  final AgentChatMode mode;
  final ValueChanged<AgentChatMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            label: '快速模式',
            icon: Icons.bolt_rounded,
            selected: mode == AgentChatMode.fast,
            onTap: () => onChanged(AgentChatMode.fast),
          ),
          _ModeChip(
            label: '专家模式',
            icon: Icons.diamond_outlined,
            selected: mode == AgentChatMode.expert,
            onTap: () => onChanged(AgentChatMode.expert),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: selected ? Border.all(color: tokens.accent) : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? tokens.accent : tokens.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? tokens.textPrimary : tokens.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? tokens.accentSoft : tokens.panelSubtle,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? tokens.accent : tokens.borderFaint,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? tokens.accent : tokens.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? tokens.textPrimary : tokens.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
