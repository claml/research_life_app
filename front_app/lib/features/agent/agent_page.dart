import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../app/local_services_scope.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/agent/agent_models.dart';
import '../../services/agent/ai_profile.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final controller = LocalServicesScope.of(
      context,
    ).aiServices.createController();
    _controller = controller;
    unawaited(controller.bootstrap());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _showSettings() {
    final controller = _controller;
    if (controller == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => _AgentSettingsDialog(controller: controller),
    );
  }

  Future<void> _send() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.sending) {
      controller.cancelActiveRequest();
      return;
    }
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await controller.sendMessage(text);
    if (!mounted || !_scrollController.hasClients) return;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return _AgentWorkspace(
      controller: controller,
      inputController: _inputController,
      scrollController: _scrollController,
      sidebarCollapsed: _sidebarCollapsed,
      onCollapseSidebar: () => setState(() => _sidebarCollapsed = true),
      onExpandSidebar: () => setState(() => _sidebarCollapsed = false),
      onOpenSettings: _showSettings,
      onSend: _send,
    );
  }
}

class _AgentWorkspace extends StatelessWidget {
  const _AgentWorkspace({
    required this.controller,
    required this.inputController,
    required this.scrollController,
    required this.sidebarCollapsed,
    required this.onCollapseSidebar,
    required this.onExpandSidebar,
    required this.onOpenSettings,
    required this.onSend,
  });

  final AgentController controller;
  final TextEditingController inputController;
  final ScrollController scrollController;
  final bool sidebarCollapsed;
  final VoidCallback onCollapseSidebar;
  final VoidCallback onExpandSidebar;
  final VoidCallback onOpenSettings;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tokens.backdropTop, tokens.canvas],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                return Row(
                  children: [
                    _HistoryRail(
                      controller: controller,
                      collapsed: narrow || sidebarCollapsed,
                      onCollapse: onCollapseSidebar,
                      onExpand: narrow ? null : onExpandSidebar,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _AgentTopBar(
                            controller: controller,
                            narrow: narrow,
                            onOpenSettings: onOpenSettings,
                          ),
                          Expanded(
                            child: _ConversationSurface(
                              controller: controller,
                              scrollController: scrollController,
                              onOpenSettings: onOpenSettings,
                            ),
                          ),
                          if (controller.error != null || controller.canRetry)
                            _AgentErrorBanner(controller: controller),
                          _Composer(
                            controller: inputController,
                            sending: controller.sending,
                            onSend: onSend,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AgentTopBar extends StatelessWidget {
  const _AgentTopBar({
    required this.controller,
    required this.narrow,
    required this.onOpenSettings,
  });

  final AgentController controller;
  final bool narrow;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final profile = controller.profile;
    return Container(
      key: const Key('agent-top-bar'),
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 18),
      decoration: BoxDecoration(
        color: tokens.panelSurface.withValues(alpha: 0.94),
        border: Border(bottom: BorderSide(color: tokens.borderFaint)),
      ),
      child: Row(
        children: [
          if (Navigator.of(context).canPop()) ...[
            IconButton(
              tooltip: '关闭 AI 助手',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                backgroundColor: tokens.panelSubtle,
                foregroundColor: tokens.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: tokens.accent,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'AI 助手',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (profile != null)
            Flexible(
              child: Container(
                key: const Key('agent-model-chip'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: tokens.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  '${profile.displayName} · ${profile.model}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('agent-settings'),
            tooltip: '配置 AI',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            style: IconButton.styleFrom(
              fixedSize: const Size(40, 40),
              backgroundColor: tokens.panelSubtle,
              foregroundColor: tokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRail extends StatelessWidget {
  const _HistoryRail({
    required this.controller,
    required this.collapsed,
    required this.onCollapse,
    required this.onExpand,
  });

  final AgentController controller;
  final bool collapsed;
  final VoidCallback onCollapse;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: const Key('agent-history-sidebar'),
      width: collapsed ? 60 : 240,
      decoration: BoxDecoration(
        color: tokens.sidebarSurface.withValues(alpha: 0.96),
        border: Border(right: BorderSide(color: tokens.borderFaint)),
      ),
      child: collapsed
          ? Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: onExpand == null
                    ? const Icon(Icons.history_rounded, color: Colors.white70)
                    : IconButton(
                        key: const Key('agent-expand-history'),
                        tooltip: '展开历史记录',
                        onPressed: onExpand,
                        color: Colors.white70,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 6, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const Key('agent-new-session'),
                          onPressed: controller.isBusy
                              ? null
                              : () => controller.startNewSession(),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.12,
                            ),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('新对话'),
                        ),
                      ),
                      IconButton(
                        key: const Key('agent-collapse-history'),
                        tooltip: '收起历史记录',
                        onPressed: onCollapse,
                        color: Colors.white70,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          hoverColor: Colors.white.withValues(alpha: 0.12),
                          highlightColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                        ),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '本地历史',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child:
                      controller.loadingSessions && controller.sessions.isEmpty
                      ? const Center(
                          child: SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          itemCount: controller.sessions.length,
                          itemBuilder: (context, index) {
                            final session = controller.sessions[index];
                            return _HistoryTile(
                              session: session,
                              selected:
                                  controller.currentSessionId == session.id,
                              onOpen: () => controller.openSession(session.id),
                              onDelete: () =>
                                  controller.deleteSession(session.id),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.session,
    required this.selected,
    required this.onOpen,
    required this.onDelete,
  });

  final AgentChatSession session;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('agent-history-${session.id}'),
      color: selected
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(11),
        hoverColor: Colors.white.withValues(alpha: 0.06),
        highlightColor: Colors.transparent,
        splashColor: Colors.white.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 7, 2, 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('agent-delete-session-${session.id}'),
                tooltip: '删除本地会话',
                onPressed: onDelete,
                iconSize: 17,
                color: Colors.white54,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  hoverColor: Colors.white.withValues(alpha: 0.1),
                  highlightColor: Colors.transparent,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationSurface extends StatelessWidget {
  const _ConversationSurface({
    required this.controller,
    required this.scrollController,
    required this.onOpenSettings,
  });

  final AgentController controller;
  final ScrollController scrollController;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if ((controller.loadingMessages || controller.loadingSessions) &&
        controller.messages.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: context.tokens.accent),
      );
    }
    if (controller.needsConfiguration) {
      return _AiNotConfigured(onOpenSettings: onOpenSettings);
    }
    if (controller.messages.isEmpty) return const _WelcomePanel();
    return _MessageList(
      controller: controller,
      scrollController: scrollController,
    );
  }
}

class _AiNotConfigured extends StatelessWidget {
  const _AiNotConfigured({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: _GlassCard(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 38, color: tokens.accent),
              const SizedBox(height: 14),
              Text(
                '配置 AI',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '选择服务与模型后即可开始。历史只保存在本机。',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('打开配置'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 34, color: tokens.accent),
          const SizedBox(height: 14),
          Text(
            '从一个研究问题开始',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '可以整理思路、解释概念或润色文字。',
            style: TextStyle(color: tokens.textSecondary),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 10),
      itemCount: controller.messages.length + (controller.sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == controller.messages.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text('正在请求服务…', style: TextStyle(color: tokens.textMuted)),
              ],
            ),
          );
        }
        return _MessageBubble(message: controller.messages[index]);
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
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: isUser
              ? tokens.accentSoft.withValues(alpha: 0.78)
              : tokens.panelSurface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: tokens.borderFaint),
          boxShadow: isUser ? const [] : tokens.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUser)
              SelectableText(
                message.content,
                style: TextStyle(color: tokens.textPrimary, height: 1.5),
              )
            else
              MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                      p: TextStyle(color: tokens.textPrimary, height: 1.5),
                      code: TextStyle(
                        color: tokens.textPrimary,
                        backgroundColor: tokens.panelSubtle,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: tokens.panelSubtle,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AgentErrorBanner extends StatelessWidget {
  const _AgentErrorBanner({required this.controller});

  final AgentController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 4, 22, 4),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: tokens.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              controller.error ?? '请求已停止，可重试上一条消息。',
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
          ),
          if (controller.canRetry)
            TextButton.icon(
              key: const Key('agent-retry'),
              onPressed: () => controller.retryFailedMessage(),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleTextChanged);
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() => setState(() {});

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (!widget.sending && widget.controller.text.trim().isEmpty) {
      return KeyEventResult.ignored;
    }
    widget.onSend();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final canSend = widget.sending || widget.controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 20),
      child: _GlassCard(
        padding: const EdgeInsets.fromLTRB(15, 11, 10, 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const Key('agent-composer'),
                controller: widget.controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '输入研究问题…',
                  hintStyle: TextStyle(color: tokens.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: widget.sending ? '取消请求' : '发送',
              child: IconButton.filled(
                key: const Key('agent-send'),
                onPressed: canSend ? widget.onSend : null,
                style: IconButton.styleFrom(
                  backgroundColor: tokens.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: tokens.panelSubtle,
                ),
                icon: Icon(
                  widget.sending
                      ? Icons.stop_rounded
                      : Icons.arrow_upward_rounded,
                  size: 19,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radiusLarge),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tokens.panelSurface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.borderFaint),
            boxShadow: tokens.shadowSm,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AgentSettingsDialog extends StatefulWidget {
  const _AgentSettingsDialog({required this.controller});

  final AgentController controller;

  @override
  State<_AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<_AgentSettingsDialog> {
  late AiProviderPreset _preset;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _credentialController;
  bool _saving = false;
  bool _checkingCredential = false;
  bool _selectedHasCredential = false;
  int _credentialCheckGeneration = 0;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile;
    _preset = aiProviderPresets.firstWhere(
      (preset) => preset.provider == profile?.provider,
      orElse: () => aiProviderPresets.first,
    );
    _baseUrlController = TextEditingController(
      text: profile?.baseUrl ?? _preset.baseUrl,
    );
    _modelController = TextEditingController(
      text: profile?.model ?? _preset.model,
    );
    // Credentials are deliberately never read into the settings surface.
    _credentialController = TextEditingController();
    _selectedHasCredential = widget.controller.hasCredential;
    _baseUrlController.addListener(_refreshSelectedCredential);
  }

  @override
  void dispose() {
    _baseUrlController.removeListener(_refreshSelectedCredential);
    _baseUrlController.dispose();
    _modelController.dispose();
    _credentialController.dispose();
    super.dispose();
  }

  void _selectPreset(AiProviderPreset preset) {
    setState(() {
      _preset = preset;
      _baseUrlController.text = preset.baseUrl;
      _modelController.text = preset.model;
      _validationError = null;
    });
    _refreshSelectedCredential();
  }

  AiProviderProfile? get _selectedProfile {
    final active = widget.controller.profile;
    final baseUrl = _baseUrlController.text.trim();
    if (active == null || baseUrl.isEmpty) return null;
    return _preset.toProfile(
      id: active.id,
      baseUrl: baseUrl,
      model: _modelController.text.trim().isEmpty
          ? active.model
          : _modelController.text.trim(),
    );
  }

  Future<void> _refreshSelectedCredential() async {
    final generation = ++_credentialCheckGeneration;
    final selected = _selectedProfile;
    setState(() {
      _checkingCredential = selected != null;
      _selectedHasCredential = false;
    });
    final available = selected == null
        ? false
        : await widget.controller.hasCredentialFor(selected);
    if (!mounted || generation != _credentialCheckGeneration) return;
    setState(() {
      _checkingCredential = false;
      _selectedHasCredential = available;
    });
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    final credential = _credentialController.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() => _validationError = '请填写 Base URL 和模型名。');
      return;
    }
    if (_preset.requiresCredential &&
        !_selectedHasCredential &&
        credential.isEmpty) {
      setState(() => _validationError = '请输入 API Key。');
      return;
    }
    setState(() {
      _saving = true;
      _validationError = null;
    });
    await widget.controller.saveConfiguration(
      profile: _preset.toProfile(
        id: widget.controller.profile?.id ?? 'primary',
        baseUrl: baseUrl,
        model: model,
      ),
      credential: credential,
    );
    if (!mounted) return;
    if (widget.controller.error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _deleteCredential() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 AI 凭据？'),
        content: const Text('本地对话历史会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.deleteCredential();
    if (mounted && widget.controller.error == null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AlertDialog(
      title: const Text('AI 配置'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('agent-provider'),
                initialValue: _preset.provider,
                decoration: const InputDecoration(
                  labelText: '服务商',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final preset in aiProviderPresets)
                    DropdownMenuItem(
                      value: preset.provider,
                      child: Text(preset.displayName),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (provider) {
                        if (provider == null) return;
                        _selectPreset(
                          aiProviderPresets.firstWhere(
                            (preset) => preset.provider == provider,
                          ),
                        );
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('agent-base-url'),
                controller: _baseUrlController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('agent-model'),
                controller: _modelController,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: '模型名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('agent-api-key'),
                controller: _credentialController,
                enabled: !_saving,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _preset.requiresCredential
                      ? 'API Key'
                      : 'API Key（可选）',
                  hintText: _selectedHasCredential ? '留空以保留现有凭据' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '发送时，当前对话上下文会传给所选服务；本地历史与凭据分开保存。',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              if (_validationError != null || widget.controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _validationError ?? widget.controller.error!,
                    style: TextStyle(color: tokens.danger, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('agent-delete-credential'),
          onPressed: _saving || widget.controller.profile == null
              ? null
              : _deleteCredential,
          child: const Text('删除凭据'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('agent-save-settings'),
          onPressed: _saving || _checkingCredential ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }
}
