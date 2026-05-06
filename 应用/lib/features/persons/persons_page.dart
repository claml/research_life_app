import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/empty_state.dart';

class PersonsPage extends StatefulWidget {
  const PersonsPage({super.key});

  @override
  State<PersonsPage> createState() => _PersonsPageState();
}

class _PersonsPageState extends State<PersonsPage> {
  String? _selectedPersonId;
  String? _hoveredPersonId;

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final sessions = controller.sessionHistory;
        final entries = _buildEntries(sessions);
        final selectedEntry = _entryById(entries, _selectedPersonId);

        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PeopleWorkbenchHeader(
                personCount: entries.length,
                hasSelection: selectedEntry != null,
              ),
              const SizedBox(height: 20),
              Expanded(
                child: sessions.isEmpty || entries.isEmpty
                    ? const EmptyState(
                        title: '还没有人物关系数据',
                        description: '先在首页完成一次分析并确认结果，这里就会生成可交互的人物关系图谱。',
                        icon: Icons.hub_rounded,
                      )
                    : _PeopleWorkbench(
                        entries: entries,
                        selectedPersonId: _selectedPersonId,
                        hoveredPersonId: _hoveredPersonId,
                        onSelect: _handleSelectPerson,
                        onHoverChanged: _handleHoverPerson,
                        onCanvasTap: _clearSelection,
                        onViewAllItems: _showAllItemsDialog,
                        onQuickAction: (actionLabel, entry) {
                          _handleQuickAction(actionLabel, entry);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleSelectPerson(String personId) {
    setState(() {
      _selectedPersonId = _selectedPersonId == personId ? null : personId;
    });
  }

  void _handleHoverPerson(String? personId) {
    setState(() => _hoveredPersonId = personId);
  }

  void _clearSelection() {
    if (_selectedPersonId == null) {
      return;
    }
    setState(() => _selectedPersonId = null);
  }

  void _showAllItemsDialog(_PersonGraphEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final tokens = context.tokens;

        return AlertDialog(
          title: Text('${entry.person.name} 的全部关联事项'),
          content: SizedBox(
            width: 460,
            child: entry.relatedItems.isEmpty
                ? const EmptyState(
                    title: '暂无关联事项',
                    description: '当前分析结果里还没有发现与该人物直接关联的事项。',
                    icon: Icons.event_busy_rounded,
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '共 ${entry.relatedCount} 条，按时间倒序展示。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final event in entry.relatedItems) ...[
                          _RelatedItemTile(
                            event: event,
                            compact: false,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleQuickAction(
    String actionLabel,
    _PersonGraphEntry entry,
  ) async {
    switch (actionLabel) {
      case '合并人物':
        await _showMergePersonDialog(entry);
        return;
      case '编辑称谓':
        await _showRenamePersonDialog(entry);
        return;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$actionLabel 将在后续版本开放。')),
        );
    }
  }

  Future<void> _showMergePersonDialog(_PersonGraphEntry entry) async {
    final controller = ResearchLifeScope.of(context);
    final session = _findSessionById(controller.sessionHistory, entry.sessionId);
    final people = session?.people ?? const <PersonProfile>[];
    if (people.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要两个人物才能执行合并。')),
      );
      return;
    }

    final result = await showDialog<_MergePeopleResult>(
      context: context,
      builder: (context) => _MergePeopleDialog(
        people: people,
        initialPrimaryPersonId: entry.person.id,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    final message = controller.mergePersons(
      primaryPersonId: result.primaryPersonId,
      secondaryPersonId: result.secondaryPersonId,
    );
    final nextSelection = controller.sessionHistory.any(
              (session) => session.people.any(
                (person) => person.id == result.primaryPersonId,
              ),
            ) ==
            true
        ? result.primaryPersonId
        : null;

    setState(() {
      _selectedPersonId = nextSelection;
      _hoveredPersonId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showRenamePersonDialog(_PersonGraphEntry entry) async {
    final controller = ResearchLifeScope.of(context);
    final result = await showDialog<_RenamePersonResult>(
      context: context,
      builder: (context) => _RenamePersonDialog(person: entry.person),
    );
    if (!mounted || result == null) {
      return;
    }

    final message = controller.renamePerson(
      personId: entry.person.id,
      nextName: result.nextName,
      keepOriginalNameAsAlias: result.keepOriginalNameAsAlias,
    );

    setState(() {
      _selectedPersonId = entry.person.id;
      _hoveredPersonId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<_PersonGraphEntry> _buildEntries(List<SessionRecord> sessions) {
    return sessions.expand((session) {
      return session.people.map((person) {
        final aliases = <String>{person.name, ...person.aliases};
        final relatedItems = session.events
            .where(
              (event) =>
                  event.personNames.any((personName) => aliases.contains(personName)),
            )
            .toList()
          ..sort((left, right) => right.startAt.compareTo(left.startAt));

        final previewSource = relatedItems
            .where((event) => event.type == EventType.plan)
            .toList();
        final previewItems =
            (previewSource.isNotEmpty ? previewSource : relatedItems)
                .take(3)
                .toList();

        return _PersonGraphEntry(
          sessionId: session.id,
          sessionTitle: session.title,
          sessionConfirmedAt: session.confirmedAt,
          person: person,
          relatedItems: relatedItems,
          previewItems: previewItems,
        );
      });
    }).toList();
  }

  _PersonGraphEntry? _entryById(
    List<_PersonGraphEntry> entries,
    String? personId,
  ) {
    if (personId == null) {
      return null;
    }

    for (final entry in entries) {
      if (entry.person.id == personId) {
        return entry;
      }
    }
    return null;
  }

  SessionRecord? _findSessionById(
    List<SessionRecord> sessions,
    String sessionId,
  ) {
    for (final session in sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }
}

class _PeopleWorkbenchHeader extends StatelessWidget {
  const _PeopleWorkbenchHeader({
    required this.personCount,
    required this.hasSelection,
  });

  final int personCount;
  final bool hasSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '人物关系',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '点击人物查看关联待办。主体区域即关系图谱，支持 hover、选中高亮和节点旁轻量详情卡片。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.end,
          children: [
            _HeaderPill(
              icon: Icons.people_alt_rounded,
              label: '$personCount 位人物',
            ),
            _HeaderPill(
              icon: Icons.ads_click_rounded,
              label: hasSelection ? '空白处关闭卡片' : '点击节点查看事项',
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tokens.panelSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tokens.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _PeopleWorkbench extends StatelessWidget {
  const _PeopleWorkbench({
    required this.entries,
    required this.selectedPersonId,
    required this.hoveredPersonId,
    required this.onSelect,
    required this.onHoverChanged,
    required this.onCanvasTap,
    required this.onViewAllItems,
    required this.onQuickAction,
  });

  final List<_PersonGraphEntry> entries;
  final String? selectedPersonId;
  final String? hoveredPersonId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String?> onHoverChanged;
  final VoidCallback onCanvasTap;
  final ValueChanged<_PersonGraphEntry> onViewAllItems;
  final void Function(String actionLabel, _PersonGraphEntry entry) onQuickAction;

  static const double _canvasPadding = 28;
  static const double _personCircleSize = 104;
  static const double _personNodeWidth = 104;
  static const double _personNodeHeight = 104;
  static const double _centerCircleSize = 104;
  static const double _centerNodeWidth = 104;
  static const double _centerNodeHeight = 104;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selectedEntry = _entryById(selectedPersonId);
    final emphasizedId = selectedPersonId ?? hoveredPersonId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final center = Offset(size.width / 2, size.height / 2);
        final positions = _buildPositions(size, center);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tokens.panelSurface,
                tokens.panelSubtle,
                tokens.insetSurface,
              ],
            ),
            borderRadius: BorderRadius.circular(tokens.radiusXLarge),
            border: Border.all(color: tokens.borderSoft),
            boxShadow: tokens.shadowMd,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusXLarge),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WorkbenchBackdropPainter(
                      center: center,
                      ringColor: tokens.borderFaint,
                      dotColor: tokens.borderSoft,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCanvasTap,
                    child: CustomPaint(
                      painter: _RelationLinesPainter(
                        center: center,
                        positions: positions,
                        emphasizedId: emphasizedId,
                        lineColor: tokens.borderSoft,
                        activeColor: tokens.accent,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: center.dx - _centerNodeWidth / 2,
                  top: center.dy - _centerCircleSize / 2,
                  child: const _GraphCenterNode(),
                ),
                for (final entry in entries)
                  Positioned(
                    left: positions[entry.person.id]!.dx - _personNodeWidth / 2,
                    top: positions[entry.person.id]!.dy - _personNodeHeight / 2,
                    child: _GraphPersonNode(
                      entry: entry,
                      selected: entry.person.id == selectedPersonId,
                      hovered: entry.person.id == hoveredPersonId,
                      muted: emphasizedId != null && entry.person.id != emphasizedId,
                      onTap: () => onSelect(entry.person.id),
                      onHoverChanged: (hovering) {
                        onHoverChanged(hovering ? entry.person.id : null);
                      },
                    ),
                  ),
                if (selectedEntry != null)
                  _AnchoredPersonPopover(
                    entry: selectedEntry,
                    anchor: positions[selectedEntry.person.id]!,
                    canvasSize: size,
                    onClose: onCanvasTap,
                    onViewAllItems: () => onViewAllItems(selectedEntry),
                    onQuickAction: (actionLabel) {
                      onQuickAction(actionLabel, selectedEntry);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, Offset> _buildPositions(Size size, Offset center) {
    if (entries.isEmpty) {
      return const <String, Offset>{};
    }

    final positions = <String, Offset>{};
    final availableRadius = math.min(size.width, size.height) * 0.29;
    const perRing = 6;
    const ringGap = 88.0;

    for (var index = 0; index < entries.length; index++) {
      final ring = index ~/ perRing;
      final indexInRing = index % perRing;
      final ringCount = math.min(perRing, entries.length - ring * perRing);
      final angle = (-math.pi / 2) +
          (2 * math.pi / ringCount) * indexInRing +
          ring * 0.22;
      final radius = availableRadius + ring * ringGap + (index.isOdd ? 10.0 : -8.0);
      final raw = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      final clamped = Offset(
        raw.dx
            .clamp(
              _canvasPadding + _personNodeWidth / 2,
              size.width - _canvasPadding - _personNodeWidth / 2,
            )
            .toDouble(),
        raw.dy
            .clamp(
              _canvasPadding + _personNodeHeight / 2,
              size.height - _canvasPadding - _personNodeHeight / 2,
            )
            .toDouble(),
      );

      positions[entries[index].person.id] = clamped;
    }

    return positions;
  }

  _PersonGraphEntry? _entryById(String? personId) {
    if (personId == null) {
      return null;
    }

    for (final entry in entries) {
      if (entry.person.id == personId) {
        return entry;
      }
    }
    return null;
  }
}

class _GraphCenterNode extends StatelessWidget {
  const _GraphCenterNode();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Container(
      width: _PeopleWorkbench._centerNodeWidth,
      height: _PeopleWorkbench._centerNodeHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.sidebarSurface,
            tokens.accent,
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '我',
        style: theme.textTheme.headlineSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GraphPersonNode extends StatelessWidget {
  const _GraphPersonNode({
    required this.entry,
    required this.selected,
    required this.hovered,
    required this.muted,
    required this.onTap,
    required this.onHoverChanged,
  });

  final _PersonGraphEntry entry;
  final bool selected;
  final bool hovered;
  final bool muted;
  final VoidCallback onTap;
  final ValueChanged<bool> onHoverChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final nodeLabel = _nodeLabel(entry.person.name);
    final labelLength = nodeLabel.runes.length;
    final highlightColor = selected
        ? tokens.accent
        : hovered
            ? tokens.warmAccent
            : tokens.borderSoft;
    final fontSize = labelLength >= 5
        ? 13.0
        : labelLength == 4
            ? 14.0
            : labelLength == 3
                ? 15.0
                : 17.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: muted ? 0.44 : 1,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            scale: selected ? 1.06 : hovered ? 1.02 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _PeopleWorkbench._personCircleSize,
              height: _PeopleWorkbench._personCircleSize,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: tokens.panelSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: highlightColor,
                  width: selected ? 3 : hovered ? 2 : 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (selected ? tokens.accent : tokens.warmAccent)
                        .withValues(alpha: selected || hovered ? 0.24 : 0.08),
                    blurRadius: selected ? 26 : 16,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  nodeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: fontSize,
                    height: 1,
                    color: selected ? tokens.accent : tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _nodeLabel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return '?';
    }

    final glyphs = normalized.runes.toList();
    if (glyphs.length <= 5) {
      return normalized;
    }

    return String.fromCharCodes(glyphs.take(4)) + '\u2026';
  }
}

class _AnchoredPersonPopover extends StatelessWidget {
  const _AnchoredPersonPopover({
    required this.entry,
    required this.anchor,
    required this.canvasSize,
    required this.onClose,
    required this.onViewAllItems,
    required this.onQuickAction,
  });

  final _PersonGraphEntry entry;
  final Offset anchor;
  final Size canvasSize;
  final VoidCallback onClose;
  final VoidCallback onViewAllItems;
  final ValueChanged<String> onQuickAction;

  static const double _cardWidth = 320;
  static const double _offsetFromNode = 66;
  static const double _edgePadding = 16;
  static const double _arrowSize = 14;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final maxCardHeight = math.min(
      360,
      canvasSize.height - (_edgePadding * 2),
    ).toDouble();
    final layout = _PopoverLayout.resolve(
      anchor: anchor,
      canvasSize: canvasSize,
      cardWidth: _cardWidth,
      cardHeight: maxCardHeight,
      offsetFromNode: _offsetFromNode,
      edgePadding: _edgePadding,
    );

    final arrowLeft = layout.cardOnRight
        ? layout.left - (_arrowSize / 2)
        : layout.left + _cardWidth - (_arrowSize / 2);

    return Stack(
      children: [
        Positioned(
          left: arrowLeft,
          top: layout.arrowTop,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: _arrowSize,
              height: _arrowSize,
              decoration: BoxDecoration(
                color: tokens.panelSurface,
                border: Border.all(color: tokens.borderFaint),
                boxShadow: tokens.shadowSm,
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: layout.left,
          top: layout.top,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _cardWidth,
              maxHeight: maxCardHeight,
            ),
            child: _PersonDetailCard(
              entry: entry,
              maxHeight: maxCardHeight,
              onClose: onClose,
              onViewAllItems: onViewAllItems,
              onQuickAction: onQuickAction,
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonDetailCard extends StatelessWidget {
  const _PersonDetailCard({
    required this.entry,
    required this.maxHeight,
    required this.onClose,
    required this.onViewAllItems,
    required this.onQuickAction,
  });

  final _PersonGraphEntry entry;
  final double maxHeight;
  final VoidCallback onClose;
  final VoidCallback onViewAllItems;
  final ValueChanged<String> onQuickAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        constraints: BoxConstraints(
          maxWidth: 320,
          maxHeight: maxHeight,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.panelSurface,
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          border: Border.all(color: tokens.borderFaint),
          boxShadow: tokens.shadowMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _firstChar(entry.person.name),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: tokens.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DetailTag(
                            label: entry.person.role.label,
                            foreground: tokens.accent,
                            background: tokens.accentSoft,
                          ),
                          _DetailTag(
                            label:
                                '${entry.sessionTitle} · ${entry.sessionConfirmedAt.month}/${entry.sessionConfirmedAt.day}',
                            foreground: tokens.textSecondary,
                            background: tokens.panelSubtle,
                          ),
                          _DetailTag(
                            label: '${entry.relatedCount} 条关联事项',
                            foreground: tokens.textSecondary,
                            background: tokens.panelSubtle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: onQuickAction,
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: '编辑称谓',
                      child: Text('编辑称谓'),
                    ),
                    PopupMenuItem<String>(
                      value: '合并人物',
                      child: Text('合并人物'),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '最近关联待办',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: entry.previewItems.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        '当前没有可展示的关联待办。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: false,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: entry.previewItems.length,
                        itemBuilder: (context, index) => _RelatedItemTile(
                          event: entry.previewItems[index],
                          compact: true,
                        ),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: tokens.borderFaint),
                ),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onViewAllItems,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('查看全部事项'),
                  ),
                  Text(
                    '点击空白处关闭',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _firstChar(String value) => value.isEmpty ? '?' : value.substring(0, 1);
}

class _DetailTag extends StatelessWidget {
  const _DetailTag({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _RelatedItemTile extends StatelessWidget {
  const _RelatedItemTile({
    required this.event,
    required this.compact,
  });

  final EventItem event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final icon = event.type == EventType.plan
        ? Icons.schedule_rounded
        : Icons.task_alt_rounded;
    final iconColor = event.type == EventType.plan ? tokens.warmAccent : tokens.accent;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: tokens.insetSurface,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 34 : 38,
            height: compact ? 34 : 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: compact ? 18 : 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatEventDateRange(event)} · ${event.type.label} · ${event.category.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatEventDateRange(EventItem event) {
    final end = event.endAt;
    final startLabel = '${event.startAt.month}/${event.startAt.day}';
    if (end == null ||
        (end.year == event.startAt.year &&
            end.month == event.startAt.month &&
            end.day == event.startAt.day)) {
      return startLabel;
    }
    return '$startLabel - ${end.month}/${end.day}';
  }
}

class _MergePeopleResult {
  const _MergePeopleResult({
    required this.primaryPersonId,
    required this.secondaryPersonId,
  });

  final String primaryPersonId;
  final String secondaryPersonId;
}

class _RenamePersonResult {
  const _RenamePersonResult({
    required this.nextName,
    required this.keepOriginalNameAsAlias,
  });

  final String nextName;
  final bool keepOriginalNameAsAlias;
}

class _RenamePersonDialog extends StatefulWidget {
  const _RenamePersonDialog({
    required this.person,
  });

  final PersonProfile person;

  @override
  State<_RenamePersonDialog> createState() => _RenamePersonDialogState();
}

class _RenamePersonDialogState extends State<_RenamePersonDialog> {
  late final TextEditingController _nameController;
  late bool _keepOriginalNameAsAlias;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.person.name);
    _keepOriginalNameAsAlias = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final nextName = _nameController.text.trim();

    return AlertDialog(
      title: const Text('编辑称谓'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '更新当前人物的称谓，并同步修改其在关联事项中的显示名称。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新称谓',
                hintText: '输入新的称谓',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            CheckboxListTile(
              value: _keepOriginalNameAsAlias,
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _keepOriginalNameAsAlias = value);
              },
              title: const Text('保留旧称谓为别名'),
              subtitle: const Text('保留后，旧称谓仍能命中该人物的历史关联事项。'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.panelSubtle,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(color: tokens.borderFaint),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '更新预览',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nextName.isEmpty
                        ? '请输入新的称谓。'
                        : '人物将从“${widget.person.name}”更新为“$nextName”。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '别名：${_aliasPreview(nextName)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: nextName.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(
                    _RenamePersonResult(
                      nextName: nextName,
                      keepOriginalNameAsAlias: _keepOriginalNameAsAlias,
                    ),
                  );
                },
          child: const Text('保存称谓'),
        ),
      ],
    );
  }

  String _aliasPreview(String nextName) {
    final aliases = <String>[
      ...widget.person.aliases,
      if (_keepOriginalNameAsAlias && widget.person.name != nextName)
        widget.person.name,
    ].where((alias) => alias.trim().isNotEmpty && alias != nextName).toList();

    if (aliases.isEmpty) {
      return '无';
    }
    return aliases.toSet().join('、');
  }
}

class _MergePeopleDialog extends StatefulWidget {
  const _MergePeopleDialog({
    required this.people,
    required this.initialPrimaryPersonId,
  });

  final List<PersonProfile> people;
  final String initialPrimaryPersonId;

  @override
  State<_MergePeopleDialog> createState() => _MergePeopleDialogState();
}

class _MergePeopleDialogState extends State<_MergePeopleDialog> {
  late String _primaryPersonId;
  late String _secondaryPersonId;

  @override
  void initState() {
    super.initState();
    _primaryPersonId = widget.people.any(
      (person) => person.id == widget.initialPrimaryPersonId,
    )
        ? widget.initialPrimaryPersonId
        : widget.people.first.id;
    _secondaryPersonId = _firstAvailableSecondary(_primaryPersonId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final primary = _personById(_primaryPersonId);
    final secondary = _personById(_secondaryPersonId);

    return AlertDialog(
      title: const Text('合并人物'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择保留人物和并入人物。合并后，并入人物的关联事项会统一归到保留人物名下，并入人物名称会保留为别名。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: _primaryPersonId,
              decoration: const InputDecoration(
                labelText: '保留人物',
                border: OutlineInputBorder(),
              ),
              items: widget.people
                  .map(
                    (person) => DropdownMenuItem<String>(
                      value: person.id,
                      child: Text('${person.name} · ${person.role.label}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _primaryPersonId = value;
                  if (_secondaryPersonId == value) {
                    _secondaryPersonId = _firstAvailableSecondary(value);
                  }
                });
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _secondaryPersonId,
              decoration: const InputDecoration(
                labelText: '并入人物',
                border: OutlineInputBorder(),
              ),
              items: widget.people
                  .where((person) => person.id != _primaryPersonId)
                  .map(
                    (person) => DropdownMenuItem<String>(
                      value: person.id,
                      child: Text('${person.name} · ${person.role.label}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _secondaryPersonId = value);
              },
            ),
            if (primary != null && secondary != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tokens.panelSubtle,
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                  border: Border.all(color: tokens.borderFaint),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '合并预览',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '保留 “${primary.name}”，并将 “${secondary.name}” 的关联事项合并进来。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '合并后别名示例：${_mergedAliasPreview(primary, secondary)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _primaryPersonId == _secondaryPersonId
              ? null
              : () {
                  Navigator.of(context).pop(
                    _MergePeopleResult(
                      primaryPersonId: _primaryPersonId,
                      secondaryPersonId: _secondaryPersonId,
                    ),
                  );
                },
          child: const Text('确认合并'),
        ),
      ],
    );
  }

  PersonProfile? _personById(String personId) {
    for (final person in widget.people) {
      if (person.id == personId) {
        return person;
      }
    }
    return null;
  }

  String _firstAvailableSecondary(String primaryPersonId) {
    for (final person in widget.people) {
      if (person.id != primaryPersonId) {
        return person.id;
      }
    }
    return primaryPersonId;
  }

  String _mergedAliasPreview(PersonProfile primary, PersonProfile secondary) {
    final aliases = <String>{
      ...primary.aliases,
      ...secondary.aliases,
      secondary.name,
    }.where((alias) => alias.trim().isNotEmpty && alias != primary.name).toList();

    if (aliases.isEmpty) {
      return '将不新增别名';
    }
    return aliases.join('、');
  }
}

class _WorkbenchBackdropPainter extends CustomPainter {
  const _WorkbenchBackdropPainter({
    required this.center,
    required this.ringColor,
    required this.dotColor,
  });

  final Offset center;
  final Color ringColor;
  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final ringPaint = Paint()
      ..color = ringColor.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke;

    for (var index = 0; index < 3; index++) {
      ringPaint.strokeWidth = index == 0 ? 1.6 : 1.1;
      canvas.drawCircle(
        center,
        math.min(size.width, size.height) * (0.18 + index * 0.12),
        ringPaint,
      );
    }

    final dotPaint = Paint()
      ..color = dotColor.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;

    const gap = 36.0;
    for (double x = gap; x < size.width; x += gap) {
      for (double y = gap; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WorkbenchBackdropPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.dotColor != dotColor;
  }
}

class _RelationLinesPainter extends CustomPainter {
  const _RelationLinesPainter({
    required this.center,
    required this.positions,
    required this.emphasizedId,
    required this.lineColor,
    required this.activeColor,
  });

  final Offset center;
  final Map<String, Offset> positions;
  final String? emphasizedId;
  final Color lineColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in positions.entries) {
      final isActive = emphasizedId == entry.key;
      final isMuted = emphasizedId != null && !isActive;
      final paint = Paint()
        ..color = (isActive ? activeColor : lineColor).withValues(
          alpha: isActive ? 0.9 : isMuted ? 0.22 : 0.52,
        )
        ..strokeWidth = isActive ? 3 : 1.8
        ..style = PaintingStyle.stroke;

      canvas.drawLine(center, entry.value, paint);

      if (isActive) {
        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(entry.value, 8, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RelationLinesPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.positions != positions ||
        oldDelegate.emphasizedId != emphasizedId ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.activeColor != activeColor;
  }
}

class _PopoverLayout {
  const _PopoverLayout({
    required this.left,
    required this.top,
    required this.arrowTop,
    required this.cardOnRight,
  });

  final double left;
  final double top;
  final double arrowTop;
  final bool cardOnRight;

  static _PopoverLayout resolve({
    required Offset anchor,
    required Size canvasSize,
    required double cardWidth,
    required double cardHeight,
    required double offsetFromNode,
    required double edgePadding,
  }) {
    final fitsRight = anchor.dx + offsetFromNode + cardWidth <=
        canvasSize.width - edgePadding;
    final fitsLeft = anchor.dx - offsetFromNode - cardWidth >= edgePadding;
    final cardOnRight = fitsRight || !fitsLeft;

    final desiredLeft = cardOnRight
        ? anchor.dx + offsetFromNode
        : anchor.dx - offsetFromNode - cardWidth;
    final left = desiredLeft
        .clamp(
          edgePadding,
          canvasSize.width - edgePadding - cardWidth,
        )
        .toDouble();
    final top = (anchor.dy - cardHeight / 2)
        .clamp(
          edgePadding,
          canvasSize.height - edgePadding - cardHeight,
        )
        .toDouble();
    final arrowTop = (anchor.dy - 7)
        .clamp(
          top + 18,
          top + cardHeight - 24,
        )
        .toDouble();

    return _PopoverLayout(
      left: left,
      top: top,
      arrowTop: arrowTop,
      cardOnRight: cardOnRight,
    );
  }
}

class _PersonGraphEntry {
  const _PersonGraphEntry({
    required this.sessionId,
    required this.sessionTitle,
    required this.sessionConfirmedAt,
    required this.person,
    required this.relatedItems,
    required this.previewItems,
  });

  final String sessionId;
  final String sessionTitle;
  final DateTime sessionConfirmedAt;
  final PersonProfile person;
  final List<EventItem> relatedItems;
  final List<EventItem> previewItems;

  int get relatedCount =>
      relatedItems.isNotEmpty ? relatedItems.length : person.relatedTaskCount;
}
