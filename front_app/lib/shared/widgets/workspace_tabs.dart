import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_tokens.dart';

class WorkspaceTabItem<T> {
  const WorkspaceTabItem({required this.value, required this.label});

  final T value;
  final String label;
}

class WorkspaceTabs<T> extends StatefulWidget {
  const WorkspaceTabs({
    required this.items,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<WorkspaceTabItem<T>> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  State<WorkspaceTabs<T>> createState() => _WorkspaceTabsState<T>();
}

class _WorkspaceTabsState<T> extends State<WorkspaceTabs<T>> {
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _focusNodes = _buildFocusNodes();
  }

  @override
  void didUpdateWidget(covariant WorkspaceTabs<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameItems =
        oldWidget.items.length == widget.items.length &&
        List.generate(
          widget.items.length,
          (index) => oldWidget.items[index].value == widget.items[index].value,
        ).every((same) => same);
    if (!sameItems) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = _buildFocusNodes();
    }
  }

  List<FocusNode> _buildFocusNodes() => [
    for (final item in widget.items)
      FocusNode(debugLabel: 'workspace-tab-${item.label}'),
  ];

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || widget.items.isEmpty) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (direction == 0) {
      return KeyEventResult.ignored;
    }
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    final selectedIndex = widget.items.indexWhere(
      (item) => item.value == widget.selected,
    );
    final current = focusedIndex == -1 ? selectedIndex : focusedIndex;
    if (current == -1) {
      return KeyEventResult.ignored;
    }
    final next = (current + direction).clamp(0, widget.items.length - 1);
    if (next == current) {
      return KeyEventResult.handled;
    }
    _focusNodes[next].requestFocus();
    widget.onSelected(widget.items[next].value);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: SizedBox(
        height: AppLayout.workspaceTabHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < widget.items.length; index++) ...[
                if (index > 0) const SizedBox(width: 28),
                _WorkspaceTabButton<T>(
                  tabKey: ValueKey(widget.items[index].value),
                  item: widget.items[index],
                  selected: widget.items[index].value == widget.selected,
                  focusNode: _focusNodes[index],
                  onPressed: () => widget.onSelected(widget.items[index].value),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTabButton<T> extends StatelessWidget {
  const _WorkspaceTabButton({
    required this.tabKey,
    required this.item,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
  });

  final Key tabKey;
  final WorkspaceTabItem<T> item;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Focus(
      key: tabKey,
      focusNode: focusNode,
      child: AnimatedBuilder(
        animation: focusNode,
        builder: (context, _) => Semantics(
          container: true,
          selected: selected,
          button: true,
          label: item.label,
          child: ExcludeSemantics(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(tokens.radiusSmall),
                child: AnimatedContainer(
                  duration: AppLayout.quickMotion,
                  height: AppLayout.workspaceTabHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: focusNode.hasFocus
                        ? Border.all(color: tokens.accent, width: 1)
                        : null,
                    borderRadius: BorderRadius.circular(tokens.radiusSmall),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            item.label,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: selected
                                      ? tokens.textPrimary
                                      : tokens.textSecondary,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: AppLayout.quickMotion,
                        width: selected ? 38 : 0,
                        height: 2,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
