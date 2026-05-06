import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/research_life_controller.dart';

class CampusMapPage extends StatefulWidget {
  const CampusMapPage({super.key});

  @override
  State<CampusMapPage> createState() => _CampusMapPageState();
}

class _CampusMapPageState extends State<CampusMapPage> {
  static const double _minScale = 0.55;
  static const double _maxScale = 3.4;
  static const String _futureCityZoneName = '未来城校区';
  static const String _nanwangshanZoneName = '南望山校区';
  static const _CampusRasterBackgroundSpec _futureCityRasterBackground =
      _CampusRasterBackgroundSpec(
        assetPath: 'assets/campus_map/future_city_map.png',
        imageSize: Size(1516, 896),
        backgroundOffset: Offset.zero,
      );
  static const _CampusRasterBackgroundSpec _nanwangshanRasterBackground =
      _CampusRasterBackgroundSpec(
        assetPath: 'assets/campus_map/nanwangshan_map.png',
        imageSize: Size(1680, 928),
        backgroundScale: 1.14,
        backgroundOffset: Offset.zero,
      );
  static const List<_CampusMapScene> _campusScenes = [
    _CampusMapScene(
      id: 3,
      name: _futureCityZoneName,
      rasterBackground: _futureCityRasterBackground,
    ),
    _CampusMapScene(
      id: 2,
      name: _nanwangshanZoneName,
      rasterBackground: _nanwangshanRasterBackground,
    ),
  ];

  final TransformationController _mapTransformController =
      TransformationController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _customLabelController = TextEditingController();

  _CampusMapScene _currentScene = _campusScenes.first;

  PlaceCategory? _selectedCategory;
  bool _showFavoritesOnly = false;
  bool _placingMode = false;
  bool _showFilterPanel = false;
  bool _showMarkers = true;

  String? _selectedPlaceId;
  String? _editingPlaceId;
  Offset? _draftPosition;

  PlaceCategory _editingCategory = PlaceCategory.study;
  String _editingIconKey = _CampusMapStyles.iconOptions.first.key;
  String _editingColorKey = _CampusMapStyles.colorOptions.first.key;
  bool _editingMine = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _resetViewport();
      }
    });
  }

  @override
  void dispose() {
    _mapTransformController.dispose();
    _searchController.dispose();
    _nameController.dispose();
    _noteController.dispose();
    _customLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final allPlaces = controller.campusPlaces;
        final filteredPlaces = _filterPlaces(allPlaces);
        final mapPlaces = _placesForScene(filteredPlaces, _currentScene);
        CampusPlace? selectedPlace;
        if (_selectedPlaceId != null) {
          for (final place in mapPlaces) {
            if (place.id == _selectedPlaceId) {
              selectedPlace = place;
              break;
            }
          }
        }
        final editingPlace = _editingPlaceId == null
            ? null
            : controller.campusPlaceById(_editingPlaceId!);

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = constraints.biggest;
            final mapSize = _resolveMapSize(viewportSize, _currentScene);
            final selectedAnchor = selectedPlace == null
                ? null
                : _viewportPointForPlace(selectedPlace, mapSize);
            final detailLayout = selectedPlace == null
                ? null
                : _OverlayCardLayout.resolve(
                    anchor: selectedAnchor,
                    viewportSize: viewportSize,
                    cardWidth: math.min(360.0, viewportSize.width - 48),
                    cardHeight: 298,
                    topInset: 124,
                  );
            final editorWidth = math.min(380.0, viewportSize.width - 48);
            final searchResults = _buildSearchResults(
              mapPlaces,
              mapSize: mapSize,
              viewportSize: viewportSize,
            );
            final activeFilterCount = _activeFilterCount();
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          context.tokens.insetSurface,
                          const Color(0xFFF2F6F1),
                          const Color(0xFFE9F0EA),
                        ],
                      ),
                    ),
                    child: _buildMapCanvas(
                      context,
                      mapSize: mapSize,
                      viewportSize: viewportSize,
                      places: _showMarkers ? mapPlaces : const <CampusPlace>[],
                      scene: _currentScene,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.08),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.04),
                          ],
                          stops: const [0, 0.28, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(
                        context,
                        viewportSize: viewportSize,
                        activeFilterCount: activeFilterCount,
                      ),
                      if (searchResults != null) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.only(
                            left: _searchResultsLeftInset(viewportSize),
                          ),
                          child: searchResults,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_showFilterPanel)
                  Positioned(
                    top: 112,
                    right: 20,
                    child: _buildFilterPanel(context),
                  ),
                if (_placingMode)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: _buildPlacementHint(context),
                  ),
                if (_draftPosition != null || _editingPlaceId != null)
                  Positioned(
                    top: 108,
                    right: 20,
                    child: _buildEditorCard(
                      context,
                      controller: controller,
                      editingPlace: editingPlace,
                      width: editorWidth,
                    ),
                  ),
                if (selectedPlace != null &&
                    _draftPosition == null &&
                    _editingPlaceId == null &&
                    detailLayout != null)
                  Positioned(
                    left: detailLayout.left,
                    top: detailLayout.top,
                    child: _buildPlaceDetailCard(
                      context,
                      controller: controller,
                      place: selectedPlace,
                      layout: detailLayout,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMapCanvas(
    BuildContext context, {
    required Size mapSize,
    required Size viewportSize,
    required List<CampusPlace> places,
    required _CampusMapScene scene,
  }) {
    final rasterBackground = scene.rasterBackground;
    final boundaryMargin = _resolveBoundaryMargin(viewportSize, mapSize);

    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _mapTransformController,
            minScale: _minScale,
            maxScale: _maxScale,
            boundaryMargin: boundaryMargin,
            constrained: false,
            trackpadScrollCausesScale: true,
            child: SizedBox(
              width: mapSize.width,
              height: mapSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRect(
                        child: Transform.translate(
                          offset: Offset(
                            mapSize.width *
                                rasterBackground.backgroundOffset.dx,
                            mapSize.height *
                                rasterBackground.backgroundOffset.dy,
                          ),
                          child: Transform.scale(
                            scale: rasterBackground.backgroundScale,
                            child: Image.asset(
                              rasterBackground.assetPath,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                              errorBuilder: (context, error, stackTrace) {
                                return _MissingCampusRasterNotice(
                                  assetPath: rasterBackground.assetPath,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        _handleCanvasTap(details.localPosition, mapSize);
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                  for (final place in places)
                    Positioned(
                      left:
                          mapSize.width * place.normalizedDx -
                          _MapMarker.size / 2,
                      top:
                          mapSize.height * place.normalizedDy -
                          _MapMarker.size / 2,
                      child: _MapMarker(
                        place: place,
                        selected: place.id == _selectedPlaceId,
                        onTap: () => _selectPlace(place.id),
                      ),
                    ),
                  if (_draftPosition != null)
                    Positioned(
                      left:
                          mapSize.width * _draftPosition!.dx -
                          _DraftMarker.size / 2,
                      top:
                          mapSize.height * _draftPosition!.dy -
                          _DraftMarker.size / 2,
                      child: const _DraftMarker(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(
    BuildContext context, {
    required Size viewportSize,
    required int activeFilterCount,
  }) {
    final tokens = context.tokens;
    final zoneControl = SizedBox(
      width: _zoneSelectorWidth(viewportSize),
      child: DropdownButtonFormField<int>(
        key: ValueKey(_currentScene.id),
        initialValue: _currentScene.id,
        items: [
          for (final scene in _campusScenes)
            DropdownMenuItem<int>(value: scene.id, child: Text(scene.name)),
        ],
        onChanged: (value) {
          if (value != null) {
            _switchCampusScene(value);
          }
        },
        icon: const Icon(Icons.expand_more_rounded),
        decoration: InputDecoration(
          labelText: '校区',
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.74),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );

    final searchControl = SizedBox(
      width: _searchFieldWidth(viewportSize),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '搜索自定义地点',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: '清空搜索',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.74),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );

    final actionControls = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () {
            setState(() => _showFilterPanel = !_showFilterPanel);
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.tune_rounded),
              if (activeFilterCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$activeFilterCount',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          label: const Text('筛选'),
        ),
        FilterChip(
          selected: _showFavoritesOnly,
          label: const Text('只看收藏'),
          onSelected: (value) {
            setState(() => _showFavoritesOnly = value);
          },
        ),
        _compactActionButton(
          context,
          tooltip: '放大',
          icon: Icons.add_rounded,
          onPressed: () => _zoomBy(1.18, viewportSize),
        ),
        _compactActionButton(
          context,
          tooltip: '缩小',
          icon: Icons.remove_rounded,
          onPressed: () => _zoomBy(0.86, viewportSize),
        ),
        _compactActionButton(
          context,
          tooltip: _showMarkers ? '隐藏标记' : '显示标记',
          icon: _showMarkers
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          onPressed: () {
            setState(() => _showMarkers = !_showMarkers);
          },
        ),
        OutlinedButton.icon(
          onPressed: () => _resetViewport(),
          icon: const Icon(Icons.center_focus_strong_rounded),
          label: const Text('重置视图'),
        ),
        FilledButton.icon(
          onPressed: _placingMode ? _exitPlacementMode : _enterPlacementMode,
          icon: Icon(
            _placingMode ? Icons.close_rounded : Icons.add_location_alt_rounded,
          ),
          label: Text(_placingMode ? '退出放置' : '新增标记'),
        ),
      ],
    );

    return _GlassPanel(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      child: viewportSize.width < 1260
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    zoneControl,
                    const SizedBox(width: 12),
                    Expanded(child: searchControl),
                  ],
                ),
                const SizedBox(height: 12),
                actionControls,
              ],
            )
          : Row(
              children: [
                zoneControl,
                const SizedBox(width: 12),
                searchControl,
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: actionControls,
                  ),
                ),
              ],
            ),
    );
  }

  Widget? _buildSearchResults(
    List<CampusPlace> filteredPlaces, {
    required Size mapSize,
    required Size viewportSize,
  }) {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return null;
    }

    final limitedPlaces = filteredPlaces.take(5).toList();
    final hasResults = limitedPlaces.isNotEmpty;

    return _GlassPanel(
      width: 360,
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: !hasResults
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '没有找到匹配地点',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.tokens.textSecondary,
                  ),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  if (limitedPlaces.isNotEmpty) ...[
                    const _SearchSectionLabel(
                      icon: Icons.place_rounded,
                      label: '自定义地点',
                    ),
                    const SizedBox(height: 8),
                    for (final place in limitedPlaces) ...[
                      _SearchResultTile(
                        place: place,
                        onTap: () {
                          _searchController.clear();
                          _focusOnPlace(
                            place,
                            mapSize: mapSize,
                            viewportSize: viewportSize,
                          );
                          _selectPlace(place.id);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    return _GlassPanel(
      width: 296,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '地图筛选',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                tooltip: '关闭筛选',
                onPressed: () => setState(() => _showFilterPanel = false),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<PlaceCategory?>(
            initialValue: _selectedCategory,
            decoration: const InputDecoration(labelText: '分类', filled: true),
            items: [
              const DropdownMenuItem<PlaceCategory?>(
                value: null,
                child: Text('全部分类'),
              ),
              ...PlaceCategory.values.map(
                (category) => DropdownMenuItem<PlaceCategory?>(
                  value: category,
                  child: Text(category.label),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() => _selectedCategory = value);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in PlaceCategory.values)
                _CategoryPill(
                  category: category,
                  selected: _selectedCategory == category,
                  countLabel: category.label,
                  onTap: () {
                    setState(() {
                      _selectedCategory = _selectedCategory == category
                          ? null
                          : category;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('清除全部筛选'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactActionButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.68),
          foregroundColor: context.tokens.textPrimary,
          side: BorderSide(color: context.tokens.borderFaint),
          fixedSize: const Size(44, 44),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _buildPlacementHint(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _GlassPanel(
          width: 520,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            _draftPosition == null
                ? '新增标记模式已开启，请直接点击地图设置地点落点。'
                : '落点已就位，请在右上角卡片中填写地点名称、分类和备注。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.tokens.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceDetailCard(
    BuildContext context, {
    required ResearchLifeController controller,
    required CampusPlace place,
    required _OverlayCardLayout layout,
  }) {
    final markerColor = _CampusMapStyles.colorForKey(place.colorKey);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: layout.arrowTop,
          left: layout.cardOnRight ? -8 : null,
          right: layout.cardOnRight ? null : -8,
          child: _DetailCardPointer(
            color: Colors.white.withValues(alpha: 0.74),
            borderColor: Colors.white.withValues(alpha: 0.92),
          ),
        ),
        _GlassPanel(
          width: layout.width,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: markerColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: _PlaceGlyph(
                        label: _CampusMapStyles.markerTextFromName(place.name),
                        textStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: context.tokens.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _MiniTag(label: place.category.label),
                            if (place.isMine) const _MiniTag(label: '我的标记'),
                            if (place.isFavorite) const _MiniTag(label: '已收藏'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭详情',
                    onPressed: () => setState(() => _selectedPlaceId = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                place.note.trim().isEmpty ? '这个地点还没有备注。' : place.note,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.tokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MiniMeta(
                    icon: Icons.access_time_rounded,
                    label: _formatDateTime(place.lastVisitedAt),
                  ),
                  _MiniMeta(
                    icon: Icons.local_fire_department_rounded,
                    label: '${place.heatScore} 次交互',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _beginEditPlace(place),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('编辑'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _recordVisit(controller, place.id),
                    icon: const Icon(Icons.near_me_rounded),
                    label: const Text('记录到访'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _toggleFavorite(controller, place.id),
                    icon: Icon(
                      place.isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                    ),
                    label: Text(place.isFavorite ? '取消收藏' : '加入收藏'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => _confirmDeletePlace(controller, place),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除地点'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB94F47),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditorCard(
    BuildContext context, {
    required ResearchLifeController controller,
    required CampusPlace? editingPlace,
    required double width,
  }) {
    final anchor =
        _draftPosition ??
        (editingPlace == null
            ? null
            : Offset(editingPlace.normalizedDx, editingPlace.normalizedDy));

    return _GlassPanel(
      width: width,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                editingPlace == null ? '新增地点' : '编辑地点',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                tooltip: '关闭编辑',
                onPressed: _cancelEditing,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            editingPlace == null ? '地点将在保存后正式落到地图上。' : '当前仅调整地点信息，保留原有地图坐标。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            autofocus: editingPlace == null,
            decoration: const InputDecoration(
              labelText: '地点名称',
              hintText: '例如：主图书馆、实验楼、食堂',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<PlaceCategory>(
            initialValue: _editingCategory,
            decoration: const InputDecoration(labelText: '地点分类'),
            items: PlaceCategory.values
                .map(
                  (category) => DropdownMenuItem<PlaceCategory>(
                    value: category,
                    child: Text(category.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              _handleCategoryChanged(value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '备注',
              hintText: '记录开放时间、适用场景、个人心得或提醒事项',
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _editingMine,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('标记为“我的地点”'),
            onChanged: (value) {
              setState(() => _editingMine = value);
            },
          ),
          const SizedBox(height: 8),
          Text(
            '标记预览',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.tokens.borderFaint),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _CampusMapStyles.colorForKey(_editingColorKey),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: _PlaceGlyph(
                      label: _CampusMapStyles.markerTextFromName(
                        _nameController.text,
                      ),
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editingCategory == PlaceCategory.other
                            ? '其他分类使用文字标记'
                            : '分类已自动匹配图标',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.tokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _editingCategory == PlaceCategory.other
                            ? '默认取备注前两个字，也可自定义 1-3 个字。'
                            : '切换分类时会自动更新地点图标。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.tokens.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_showCustomMarkerTextField &&
              _editingCategory == PlaceCategory.other) ...[
            TextField(
              controller: _customLabelController,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: '文字标记',
                hintText: '例如：午、静心角、办卡',
                helperText: '留空时，会回退到备注前两个字。',
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '颜色',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _CampusMapStyles.colorOptions)
                _SelectableColorChip(
                  color: option.color,
                  label: option.label,
                  selected: _editingColorKey == option.key,
                  onTap: () => setState(() => _editingColorKey = option.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (anchor != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.tokens.borderFaint),
              ),
              child: Text(
                '地图坐标：X ${(anchor.dx * 100).toStringAsFixed(0)}% · Y ${(anchor.dy * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: _cancelEditing,
                icon: const Icon(Icons.close_rounded),
                label: const Text('取消'),
              ),
              if (editingPlace != null)
                TextButton.icon(
                  onPressed: () =>
                      _confirmDeletePlace(controller, editingPlace),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB94F47),
                  ),
                ),
              FilledButton.icon(
                onPressed: () => _savePlace(
                  controller,
                  editingPlace: editingPlace,
                  anchor: anchor,
                ),
                icon: const Icon(Icons.save_rounded),
                label: Text(editingPlace == null ? '保存地点' : '保存修改'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleCanvasTap(Offset localPosition, Size mapSize) {
    if (_placingMode) {
      _resetEditorForNewPlace();
      setState(() {
        _draftPosition = Offset(
          (localPosition.dx / mapSize.width).clamp(0.0, 1.0).toDouble(),
          (localPosition.dy / mapSize.height).clamp(0.0, 1.0).toDouble(),
        );
        _selectedPlaceId = null;
        _editingPlaceId = null;
      });
      return;
    }

    setState(() {
      _selectedPlaceId = null;
      _editingPlaceId = null;
      _draftPosition = null;
      _showFilterPanel = false;
    });
  }

  void _selectPlace(String placeId) {
    setState(() {
      _selectedPlaceId = placeId;
      _editingPlaceId = null;
      _draftPosition = null;
      _placingMode = false;
      _showFilterPanel = false;
    });
  }

  void _enterPlacementMode() {
    _resetEditorForNewPlace();
    setState(() {
      _placingMode = true;
      _draftPosition = null;
      _selectedPlaceId = null;
      _editingPlaceId = null;
      _showFilterPanel = false;
    });
  }

  void _exitPlacementMode() {
    setState(() {
      _placingMode = false;
      _draftPosition = null;
    });
  }

  void _beginEditPlace(CampusPlace place) {
    _nameController.text = place.name;
    _noteController.text = place.note;
    final customMarkerText = _CampusMapStyles.textForIconKey(place.iconKey);
    setState(() {
      _editingPlaceId = place.id;
      _selectedPlaceId = place.id;
      _editingCategory = place.category;
      _editingIconKey = _resolveCategoryIconKey(place.category, place.iconKey);
      _editingColorKey = place.colorKey;
      _editingMine = place.isMine;
      _customLabelController.text = customMarkerText.isNotEmpty
          ? customMarkerText
          : _deriveAutoMarkerText(place.note, fallback: place.name);
      _draftPosition = null;
      _placingMode = false;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingPlaceId = null;
      _draftPosition = null;
      _placingMode = false;
    });
  }

  void _toggleFavorite(ResearchLifeController controller, String placeId) {
    final success = controller.toggleCampusPlaceFavorite(placeId);
    if (!success) {
      _showSnackBar('地点不存在，无法更新收藏状态。');
      return;
    }

    final place = controller.campusPlaceById(placeId);
    if (place == null) {
      return;
    }
    _showSnackBar(place.isFavorite ? '已加入收藏。' : '已取消收藏。');
  }

  void _recordVisit(ResearchLifeController controller, String placeId) {
    final success = controller.markCampusPlaceVisited(placeId);
    if (!success) {
      _showSnackBar('地点不存在，无法记录访问。');
      return;
    }
    _showSnackBar('已更新最近访问时间。');
  }

  Future<void> _confirmDeletePlace(
    ResearchLifeController controller,
    CampusPlace place,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除地点'),
          content: Text('确定要删除“${place.name}”吗？此操作会移除地图标记和备注。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final success = controller.deleteCampusPlace(place.id);
    if (!success) {
      _showSnackBar('地点不存在，无法删除。');
      return;
    }

    setState(() {
      if (_selectedPlaceId == place.id) {
        _selectedPlaceId = null;
      }
      if (_editingPlaceId == place.id) {
        _editingPlaceId = null;
      }
      _draftPosition = null;
      _placingMode = false;
    });
    _showSnackBar('已删除地点标记。');
  }

  void _savePlace(
    ResearchLifeController controller, {
    required CampusPlace? editingPlace,
    required Offset? anchor,
  }) {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('请先填写地点名称。');
      return;
    }

    if (editingPlace != null) {
      final success = controller.updateCampusPlace(
        id: editingPlace.id,
        name: name,
        category: _editingCategory,
        note: _noteController.text,
        normalizedDx: editingPlace.normalizedDx,
        normalizedDy: editingPlace.normalizedDy,
        iconKey: _CampusMapStyles.iconKeyForPlaceName(name),
        colorKey: _editingColorKey,
        zoneId: _currentScene.id,
        isMine: _editingMine,
      );
      if (!success) {
        _showSnackBar('地点不存在，无法保存修改。');
        return;
      }
      setState(() {
        _editingPlaceId = null;
        _selectedPlaceId = editingPlace.id;
      });
      _showSnackBar('已保存地点修改。');
      return;
    }

    if (anchor == null) {
      _showSnackBar('请先在地图上选择一个落点。');
      return;
    }

    final createdPlace = controller.createCampusPlace(
      name: name,
      category: _editingCategory,
      note: _noteController.text,
      normalizedDx: anchor.dx,
      normalizedDy: anchor.dy,
      iconKey: _CampusMapStyles.iconKeyForPlaceName(name),
      colorKey: _editingColorKey,
      zoneId: _currentScene.id,
      isMine: _editingMine,
    );
    setState(() {
      _selectedPlaceId = createdPlace.id;
      _draftPosition = null;
      _placingMode = false;
    });
    _showSnackBar('已新增地点标记。');
  }

  void _resetEditorForNewPlace() {
    _nameController.clear();
    _noteController.clear();
    _editingCategory = PlaceCategory.study;
    _editingIconKey = _CampusMapStyles.defaultIconKeyForCategory(
      PlaceCategory.study,
    );
    _editingColorKey = _CampusMapStyles.colorOptions.first.key;
    _editingMine = true;
    _customLabelController.clear();
  }

  void _handleCategoryChanged(PlaceCategory nextCategory) {
    final hasCustomLabel =
        _sanitizeCustomMarkerText(_customLabelController.text) != null;

    setState(() {
      _editingCategory = nextCategory;
      _editingIconKey = _resolveCategoryIconKey(nextCategory, _editingIconKey);
      if (nextCategory == PlaceCategory.other) {
        if (!hasCustomLabel) {
          _customLabelController.text = _deriveAutoMarkerText(
            _noteController.text,
            fallback: _nameController.text,
          );
        }
      }
    });
  }

  String _resolveCategoryIconKey(
    PlaceCategory category,
    String currentIconKey,
  ) {
    if (category != PlaceCategory.other) {
      return _CampusMapStyles.defaultIconKeyForCategory(category);
    }
    final customText = _CampusMapStyles.textForIconKey(currentIconKey);
    final resolvedText = customText.isNotEmpty
        ? customText
        : _deriveAutoMarkerText(
            _noteController.text,
            fallback: _nameController.text,
          );
    return 'text:$resolvedText';
  }

  String _deriveAutoMarkerText(String source, {String fallback = ''}) {
    final cleaned = source.replaceAll(RegExp(r'\s+'), '');
    final candidate = cleaned.isNotEmpty
        ? cleaned
        : fallback.replaceAll(RegExp(r'\s+'), '');
    if (candidate.isEmpty) {
      return '\u5176\u4ed6';
    }
    final chars = candidate.characters;
    if (chars.length <= 2) {
      return chars.toList().join();
    }
    return chars.take(2).toList().join();
  }

  String? _sanitizeCustomMarkerText(String source) {
    final cleaned = source.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) {
      return null;
    }
    final chars = cleaned.characters;
    return chars.take(3).toList().join();
  }

  void _switchCampusScene(int sceneId) {
    final nextScene = _campusScenes.firstWhere(
      (scene) => scene.id == sceneId,
      orElse: () => _currentScene,
    );
    if (nextScene.id == _currentScene.id) {
      return;
    }

    setState(() {
      _currentScene = nextScene;
      _searchController.clear();
      _selectedPlaceId = null;
      _editingPlaceId = null;
      _draftPosition = null;
      _placingMode = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _resetViewport();
      }
    });
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedCategory = null;
      _showFavoritesOnly = false;
    });
  }

  Size _resolveMapSize(Size viewportSize, _CampusMapScene scene) {
    final rasterBackground = scene.rasterBackground;
    final minWidth = math.max(viewportSize.width, 960.0);
    final minHeight = math.max(viewportSize.height, 700.0);
    final aspectRatio =
        rasterBackground.imageSize.width / rasterBackground.imageSize.height;

    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      return Size(minWidth, minHeight);
    }

    var width = minWidth;
    var height = width / aspectRatio;
    if (height < minHeight) {
      height = minHeight;
      width = height * aspectRatio;
    }
    return Size(width, height);
  }

  EdgeInsets _resolveBoundaryMargin(Size viewportSize, Size mapSize) {
    const baseMargin = 140.0;
    const extraSlack = 80.0;
    final minSceneWidth = viewportSize.width / _minScale;
    final minSceneHeight = viewportSize.height / _minScale;

    return EdgeInsets.symmetric(
      horizontal: math.max(
        baseMargin,
        (minSceneWidth - mapSize.width) / 2 + extraSlack,
      ),
      vertical: math.max(
        baseMargin,
        (minSceneHeight - mapSize.height) / 2 + extraSlack,
      ),
    );
  }

  bool get _showCustomMarkerTextField => false;

  double _zoneSelectorWidth(Size viewportSize) {
    if (viewportSize.width < 980) {
      return math.min(360.0, viewportSize.width - 40);
    }
    return 220;
  }

  double _searchFieldWidth(Size viewportSize) {
    if (viewportSize.width < 980) {
      return _zoneSelectorWidth(viewportSize);
    }
    return 360;
  }

  double _searchResultsLeftInset(Size viewportSize) {
    if (viewportSize.width < 980) {
      return 14;
    }
    return 14 + _zoneSelectorWidth(viewportSize) + 12;
  }

  void _resetViewport() {
    final viewportSize = context.size ?? MediaQuery.maybeSizeOf(context);
    if (viewportSize == null || viewportSize.isEmpty) {
      _mapTransformController.value = Matrix4.identity();
      return;
    }

    final mapSize = _resolveMapSize(viewportSize, _currentScene);
    const padding = 40.0;
    final availableWidth = math.max(viewportSize.width - padding * 2, 120.0);
    final availableHeight = math.max(viewportSize.height - padding * 2, 120.0);
    final scale = math
        .min(availableWidth / mapSize.width, availableHeight / mapSize.height)
        .clamp(_minScale, 1.0)
        .toDouble();

    final matrix = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        viewportSize.width / 2 - scale * mapSize.width / 2,
        viewportSize.height / 2 - scale * mapSize.height / 2,
        0,
      );
    _mapTransformController.value = matrix;
  }

  void _zoomBy(double factor, Size viewportSize) {
    final currentScale = _mapTransformController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final sceneCenter = _mapTransformController.toScene(
      viewportSize.center(Offset.zero),
    );
    final matrix = Matrix4.diagonal3Values(nextScale, nextScale, 1)
      ..setTranslationRaw(
        viewportSize.width / 2 - nextScale * sceneCenter.dx,
        viewportSize.height / 2 - nextScale * sceneCenter.dy,
        0,
      );
    _mapTransformController.value = matrix;
  }

  void _focusOnPlace(
    CampusPlace place, {
    required Size mapSize,
    required Size viewportSize,
  }) {
    _focusOnPoint(
      Offset(place.normalizedDx, place.normalizedDy),
      mapSize: mapSize,
      viewportSize: viewportSize,
    );
  }

  void _focusOnPoint(
    Offset normalizedPoint, {
    required Size mapSize,
    required Size viewportSize,
    double? targetScale,
  }) {
    final scale =
        targetScale ?? _mapTransformController.value.getMaxScaleOnAxis();
    final scenePoint = Offset(
      mapSize.width * normalizedPoint.dx,
      mapSize.height * normalizedPoint.dy,
    );
    final matrix = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        viewportSize.width / 2 - scale * scenePoint.dx,
        viewportSize.height / 2 - scale * scenePoint.dy,
        0,
      );
    _mapTransformController.value = matrix;
  }

  Offset _viewportPointForPlace(CampusPlace place, Size mapSize) {
    final scenePoint = Offset(
      mapSize.width * place.normalizedDx,
      mapSize.height * place.normalizedDy,
    );
    return MatrixUtils.transformPoint(
      _mapTransformController.value,
      scenePoint,
    );
  }

  List<CampusPlace> _placesForScene(
    List<CampusPlace> places,
    _CampusMapScene scene,
  ) {
    return [
      for (final place in places)
        if (place.zoneId == null || place.zoneId == scene.id) place,
    ];
  }

  List<CampusPlace> _filterPlaces(List<CampusPlace> places) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = places.where((place) {
      if (_selectedCategory != null && place.category != _selectedCategory) {
        return false;
      }
      if (_showFavoritesOnly && !place.isFavorite) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return place.name.toLowerCase().contains(query) ||
          place.note.toLowerCase().contains(query);
    }).toList();

    filtered.sort((left, right) {
      final favoriteDiff = (right.isFavorite ? 1 : 0).compareTo(
        left.isFavorite ? 1 : 0,
      );
      if (favoriteDiff != 0) {
        return favoriteDiff;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return filtered;
  }

  int _activeFilterCount() {
    var count = 0;
    if (_selectedCategory != null) {
      count += 1;
    }
    if (_showFavoritesOnly) {
      count += 1;
    }
    return count;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '尚未记录';
    }
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.width,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.82),
                Colors.white.withValues(alpha: 0.68),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.78)),
            boxShadow: [
              BoxShadow(
                color: const Color(0x1A13241A),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.24),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.tokens.borderFaint),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: context.tokens.textSecondary,
        ),
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.tokens.borderFaint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.tokens.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.category,
    required this.selected,
    required this.countLabel,
    required this.onTap,
  });

  final PlaceCategory category;
  final bool selected;
  final String countLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _CampusMapStyles.categoryColor(category);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.42)
                : context.tokens.borderFaint,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              countLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.place, required this.onTap});

  final CampusPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _CampusMapStyles.colorForKey(place.colorKey);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.64),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.tokens.borderFaint),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _PlaceGlyph(
                    label: _CampusMapStyles.markerTextFromName(place.name),
                    textStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${place.category.label} · ${place.isMine ? '我的标记' : '公共地点'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.tokens.textSecondary,
                      ),
                    ),
                    if (place.note.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        place.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.tokens.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchSectionLabel extends StatelessWidget {
  const _SearchSectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.tokens.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: context.tokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MissingCampusRasterNotice extends StatelessWidget {
  const _MissingCampusRasterNotice({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8EEE8),
      child: Center(
        child: _GlassPanel(
          width: 440,
          padding: const EdgeInsets.all(18),
          child: Text(
            '未找到本地校园地图：$assetPath',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceGlyph extends StatelessWidget {
  const _PlaceGlyph({required this.label, this.textStyle});

  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          textAlign: TextAlign.center,
          style:
              textStyle ??
              Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.place,
    required this.selected,
    required this.onTap,
  });

  static const double size = 42;

  final CampusPlace place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _CampusMapStyles.colorForKey(place.colorKey);

    return Tooltip(
      message: '${place.name} · ${place.category.label}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 44 : 38,
          height: selected ? 44 : 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: selected ? 3 : 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: selected ? 0.34 : 0.22),
                blurRadius: selected ? 24 : 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: _PlaceGlyph(
              label: _CampusMapStyles.markerTextFromName(place.name),
              textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftMarker extends StatelessWidget {
  const _DraftMarker();

  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: tokens.accent,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: tokens.accent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
    );
  }
}

class _SelectableColorChip extends StatelessWidget {
  const _SelectableColorChip({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.56),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : context.tokens.borderFaint,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCardPointer extends StatelessWidget {
  const _DetailCardPointer({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: const Color(0x1413241A),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayCardLayout {
  const _OverlayCardLayout({
    required this.left,
    required this.top,
    required this.width,
    required this.cardOnRight,
    required this.arrowTop,
  });

  final double left;
  final double top;
  final double width;
  final bool cardOnRight;
  final double arrowTop;

  static _OverlayCardLayout resolve({
    required Offset? anchor,
    required Size viewportSize,
    required double cardWidth,
    required double cardHeight,
    required double topInset,
  }) {
    const edgeInset = 20.0;
    final fallbackLeft = viewportSize.width - cardWidth - edgeInset;
    final fallbackTop = topInset;

    if (anchor == null ||
        anchor.dx < 0 ||
        anchor.dx > viewportSize.width ||
        anchor.dy < 0 ||
        anchor.dy > viewportSize.height) {
      return _OverlayCardLayout(
        left: fallbackLeft,
        top: fallbackTop,
        width: cardWidth,
        cardOnRight: false,
        arrowTop: 52,
      );
    }

    final fitsRight =
        anchor.dx + 24 + cardWidth <= viewportSize.width - edgeInset;
    final fitsLeft = anchor.dx - 24 - cardWidth >= edgeInset;
    final placeRight = fitsRight || !fitsLeft;
    final desiredLeft = placeRight
        ? anchor.dx + 20
        : anchor.dx - cardWidth - 20;
    final desiredTop = anchor.dy - cardHeight / 2;
    final resolvedTop = desiredTop
        .clamp(topInset, viewportSize.height - cardHeight - edgeInset)
        .toDouble();

    return _OverlayCardLayout(
      left: desiredLeft
          .clamp(edgeInset, viewportSize.width - cardWidth - edgeInset)
          .toDouble(),
      top: resolvedTop,
      width: cardWidth,
      cardOnRight: placeRight,
      arrowTop: (anchor.dy - resolvedTop - 10)
          .clamp(26.0, cardHeight - 28.0)
          .toDouble(),
    );
  }
}

class _CampusMapScene {
  const _CampusMapScene({
    required this.id,
    required this.name,
    required this.rasterBackground,
  });

  final int id;
  final String name;
  final _CampusRasterBackgroundSpec rasterBackground;
}

class _CampusRasterBackgroundSpec {
  const _CampusRasterBackgroundSpec({
    required this.assetPath,
    required this.imageSize,
    this.backgroundScale = 1,
    this.backgroundOffset = Offset.zero,
  });

  final String assetPath;
  final Size imageSize;
  final double backgroundScale;
  final Offset backgroundOffset;
}

class _CampusMapStyles {
  static const List<_IconOption> iconOptions = [
    _IconOption(
      key: 'book',
      label: '\u5b66\u4e60',
      icon: Icons.menu_book_rounded,
    ),
    _IconOption(
      key: 'food',
      label: '\u5403\u996d',
      icon: Icons.restaurant_rounded,
    ),
    _IconOption(key: 'bed', label: '\u5bbf\u820d', icon: Icons.bed_rounded),
    _IconOption(
      key: 'flask',
      label: '\u5b9e\u9a8c',
      icon: Icons.science_rounded,
    ),
    _IconOption(
      key: 'run',
      label: '\u8fd0\u52a8',
      icon: Icons.directions_run_rounded,
    ),
    _IconOption(
      key: 'people',
      label: '\u793e\u4ea4',
      icon: Icons.groups_rounded,
    ),
    _IconOption(
      key: 'office',
      label: '\u529e\u4e8b',
      icon: Icons.apartment_rounded,
    ),
  ];

  static const List<_ColorOption> colorOptions = [
    _ColorOption(
      key: 'forest',
      label: '\u677e\u67cf\u7eff',
      color: Color(0xFF2F6B4B),
    ),
    _ColorOption(
      key: 'amber',
      label: '\u7425\u73c0\u9ec4',
      color: Color(0xFFBC8A2C),
    ),
    _ColorOption(
      key: 'slate',
      label: '\u77f3\u677f\u7070',
      color: Color(0xFF5C6C74),
    ),
    _ColorOption(
      key: 'berry',
      label: '\u8393\u679c\u7ea2',
      color: Color(0xFFA24B63),
    ),
    _ColorOption(
      key: 'teal',
      label: '\u6e56\u6c34\u84dd',
      color: Color(0xFF2C7F8C),
    ),
    _ColorOption(
      key: 'blue',
      label: '\u6821\u56ed\u84dd',
      color: Color(0xFF3E6FA5),
    ),
  ];

  static String defaultIconKeyForCategory(PlaceCategory category) {
    return switch (category) {
      PlaceCategory.study => 'book',
      PlaceCategory.dining => 'food',
      PlaceCategory.dormitory => 'bed',
      PlaceCategory.lab => 'flask',
      PlaceCategory.sports => 'run',
      PlaceCategory.social => 'people',
      PlaceCategory.errands => 'office',
      PlaceCategory.other => 'text:其他',
    };
  }

  static String textForIconKey(String key) {
    if (!key.startsWith('text:')) {
      return '';
    }
    return key.substring(5).trim();
  }

  static String markerTextFromName(String name) {
    final compact = name.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) {
      return '点';
    }
    return compact.characters.first;
  }

  static String iconKeyForPlaceName(String name) {
    return 'text:${markerTextFromName(name)}';
  }

  static Color colorForKey(String key) {
    for (final option in colorOptions) {
      if (option.key == key) {
        return option.color;
      }
    }
    return const Color(0xFF2F6B4B);
  }

  static Color categoryColor(PlaceCategory category) {
    return switch (category) {
      PlaceCategory.study => const Color(0xFF2F6B4B),
      PlaceCategory.dining => const Color(0xFFBC8A2C),
      PlaceCategory.dormitory => const Color(0xFF5C6C74),
      PlaceCategory.lab => const Color(0xFFA24B63),
      PlaceCategory.sports => const Color(0xFF2C7F8C),
      PlaceCategory.social => const Color(0xFF7B5DA7),
      PlaceCategory.errands => const Color(0xFF3E6FA5),
      PlaceCategory.other => const Color(0xFF7B836F),
    };
  }
}

class _IconOption {
  const _IconOption({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final IconData icon;
}

class _ColorOption {
  const _ColorOption({
    required this.key,
    required this.label,
    required this.color,
  });

  final String key;
  final String label;
  final Color color;
}
