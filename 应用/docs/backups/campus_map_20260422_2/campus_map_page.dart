import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/campus_map/public_campus_map_service.dart';
import '../../state/research_life_controller.dart';

class CampusMapPage extends StatefulWidget {
  const CampusMapPage({super.key});

  @override
  State<CampusMapPage> createState() => _CampusMapPageState();
}

class _CampusMapPageState extends State<CampusMapPage> {
  static const double _minScale = 0.55;
  static const double _maxScale = 3.4;

  final PublicCampusMapService _publicMapService = PublicCampusMapService();
  final TransformationController _mapTransformController =
      TransformationController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _customLabelController = TextEditingController();

  List<PublicCampusZone> _publicZones = const [];
  PublicCampusMapScene? _publicMapScene;
  bool _publicMapBusy = true;
  String? _publicMapError;

  PlaceCategory? _selectedCategory;
  bool _showMineOnly = false;
  bool _showFavoritesOnly = false;
  bool _placingMode = false;
  bool _showFilterPanel = false;
  bool _showMarkers = true;

  String? _selectedPlaceId;
  String? _selectedBuildingId;
  String? _editingPlaceId;
  Offset? _draftPosition;

  PlaceCategory _editingCategory = PlaceCategory.study;
  String _editingIconKey = _CampusMapStyles.iconOptions.first.key;
  String _editingColorKey = _CampusMapStyles.colorOptions.first.key;
  bool _editingMine = true;
  bool _customLabelEdited = false;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _mapTransformController.addListener(_handleTransformChanged);
    _nameController.addListener(_handleNoteChanged);
    _noteController.addListener(_handleNoteChanged);
    _loadPublicMap();
  }

  @override
  void dispose() {
    _mapTransformController.removeListener(_handleTransformChanged);
    _mapTransformController.dispose();
    _searchController.dispose();
    _nameController.removeListener(_handleNoteChanged);
    _nameController.dispose();
    _noteController.removeListener(_handleNoteChanged);
    _noteController.dispose();
    _customLabelController.dispose();
    _publicMapService.dispose();
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
        final mapPlaces = _placesForScene(filteredPlaces, _publicMapScene);
        final hiddenLegacyPlaceCount = _hiddenPlaceCountForScene(
          filteredPlaces,
          _publicMapScene,
        );
        final buildingMatches =
            _publicMapScene?.searchBuildings(_searchController.text) ?? const [];
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
            final mapSize = Size(
              math.max(viewportSize.width, 960.0),
              math.max(viewportSize.height, 700.0),
            );
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
              buildingMatches: buildingMatches,
              mapSize: mapSize,
              viewportSize: viewportSize,
            );
            final activeFilterCount = _activeFilterCount();
            final categorySummary = _selectedCategory?.label ?? '全部分类';

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
                      scene: _publicMapScene,
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
                  child: _buildSearchDock(
                    context,
                    resultCount: mapPlaces.length,
                    buildingCount: _publicMapScene?.buildings.length ?? 0,
                  ),
                ),
                if (searchResults != null)
                  Positioned(
                    top: 128,
                    left: 20,
                    child: searchResults,
                  ),
                Positioned(
                  top: 20,
                  right: 20,
                  child: _buildActionDock(
                    context,
                    activeFilterCount: activeFilterCount,
                  ),
                ),
                if (_showFilterPanel)
                  Positioned(
                    top: 94,
                    right: 20,
                    child: _buildFilterPanel(context),
                  ),
                Positioned(
                  right: 20,
                  top: 212,
                  child: _buildToolRail(
                    context,
                    viewportSize: viewportSize,
                  ),
                ),
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: _buildStatusDock(
                    context,
                    visibleCount: mapPlaces.length,
                    totalCount: allPlaces.length,
                    categorySummary: categorySummary,
                    buildingCount: _publicMapScene?.buildings.length ?? 0,
                    hiddenLegacyPlaceCount: hiddenLegacyPlaceCount,
                    zoneName: _publicMapScene?.zone.name,
                  ),
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
    required PublicCampusMapScene? scene,
  }) {
    final highlightedBuildingIds = scene == null
        ? const <String>{}
        : scene
              .searchBuildings(_searchController.text)
              .take(18)
              .map((building) => building.id)
              .toSet();
    PublicCampusBuilding? selectedBuilding;
    if (scene != null && _selectedBuildingId != null) {
      for (final building in scene.buildings) {
        if (building.id == _selectedBuildingId) {
          selectedBuilding = building;
          break;
        }
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _mapTransformController,
            minScale: _minScale,
            maxScale: _maxScale,
            boundaryMargin: const EdgeInsets.all(140),
            constrained: false,
            trackpadScrollCausesScale: true,
            child: SizedBox(
              width: mapSize.width,
              height: mapSize.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        _handleCanvasTap(details.localPosition, mapSize);
                      },
                      child: CustomPaint(
                        painter: _CampusPlanPainter(
                          tokens: context.tokens,
                          scene: scene,
                          selectedBuildingId: _selectedBuildingId,
                          highlightedBuildingIds: highlightedBuildingIds,
                        ),
                      ),
                    ),
                  ),
                  if (selectedBuilding != null && selectedBuilding.hasDisplayName)
                    Positioned(
                      left: mapSize.width * selectedBuilding.center.dx,
                      top: math.max(
                        20,
                        mapSize.height * selectedBuilding.center.dy - 34,
                      ),
                      child: _AreaLabelChip(label: selectedBuilding.name),
                    )
                  else if (scene == null)
                    for (final area in _CampusMapStyles.areaAnchors)
                      Positioned(
                        left: mapSize.width * area.dx,
                        top: mapSize.height * area.dy,
                        child: _AreaLabelChip(label: area.label),
                      ),
                  for (final place in places)
                    Positioned(
                      left: mapSize.width * place.normalizedDx - _MapMarker.size / 2,
                      top: mapSize.height * place.normalizedDy - _MapMarker.size / 2,
                      child: _MapMarker(
                        place: place,
                        selected: place.id == _selectedPlaceId,
                        onTap: () => _selectPlace(place.id),
                      ),
                    ),
                  if (_draftPosition != null)
                    Positioned(
                      left: mapSize.width * _draftPosition!.dx -
                          _DraftMarker.size / 2,
                      top: mapSize.height * _draftPosition!.dy -
                          _DraftMarker.size / 2,
                      child: const _DraftMarker(),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 88,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: math.min(520, viewportSize.width - 80),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: Text(
                  _placingMode
                      ? (_draftPosition == null
                          ? '点击空白位置为新标记设置落点。'
                          : '落点已确认，请在右上角卡片中补充地点信息。')
                      : scene == null
                      ? '滚轮缩放、拖拽平移；当前正在尝试接入公开校园地图。'
                      : '当前底图来自公开校园地图数据；你的自定义标记仍可正常编辑。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ),
        if (_publicMapBusy || _publicMapError != null)
          Positioned(
            left: 20,
            bottom: 148,
            child: _MapFetchStatusChip(
              busy: _publicMapBusy,
              errorText: _publicMapError,
              onRetry: _publicMapBusy ? null : _loadPublicMap,
            ),
          ),
      ],
    );
  }

  Widget _buildSearchDock(
    BuildContext context, {
    required int resultCount,
    required int buildingCount,
  }) {
    return _GlassPanel(
      width: 360,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '校园地图',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.tokens.textPrimary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '自定义标记继续保留，公开校园底图单独接入。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.tokens.textSecondary,
                ),
          ),
          if (_publicZones.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey(_publicMapScene?.zone.id ?? _publicZones.first.id),
              initialValue: _publicMapScene?.zone.id ?? _publicZones.first.id,
              items: [
                for (final zone in _publicZones)
                  DropdownMenuItem<int>(
                    value: zone.id,
                    child: Text(zone.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _loadPublicMap(zoneId: value);
                }
              },
              icon: const Icon(Icons.expand_more_rounded),
              decoration: InputDecoration(
                labelText: '公开校区',
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
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索自定义地点或公开建筑',
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
          const SizedBox(height: 10),
          Row(
            children: [
              _MapInfoBadge(
                icon: Icons.place_rounded,
                label: '$resultCount 个可见地点',
              ),
              const SizedBox(width: 8),
              _MapInfoBadge(
                icon: Icons.domain_rounded,
                label: '$buildingCount 栋公开建筑',
              ),
              const SizedBox(width: 8),
              _MapInfoBadge(
                icon: Icons.zoom_in_map_rounded,
                label: '${_zoom.toStringAsFixed(2)}x',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _buildSearchResults(
    List<CampusPlace> filteredPlaces, {
    required List<PublicCampusBuilding> buildingMatches,
    required Size mapSize,
    required Size viewportSize,
  }) {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return null;
    }

    final limitedBuildings = buildingMatches.take(5).toList();
    final limitedPlaces = filteredPlaces.take(5).toList();
    final hasResults = limitedBuildings.isNotEmpty || limitedPlaces.isNotEmpty;

    return _GlassPanel(
      width: 360,
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: !hasResults
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '没有找到匹配地点或公开建筑',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.tokens.textSecondary,
                      ),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  if (limitedBuildings.isNotEmpty) ...[
                    const _SearchSectionLabel(
                      icon: Icons.domain_rounded,
                      label: '公开建筑',
                    ),
                    const SizedBox(height: 8),
                    for (final building in limitedBuildings) ...[
                      _BuildingSearchResultTile(
                        building: building,
                        onTap: () {
                          _searchController.clear();
                          _focusOnPoint(
                            building.center,
                            mapSize: mapSize,
                            viewportSize: viewportSize,
                            targetScale: 1.22,
                          );
                          setState(() {
                            _selectedBuildingId = building.id;
                            _selectedPlaceId = null;
                            _editingPlaceId = null;
                            _draftPosition = null;
                            _placingMode = false;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
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

  Widget _buildActionDock(
    BuildContext context, {
    required int activeFilterCount,
  }) {
    return _GlassPanel(
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
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
                      decoration: const BoxDecoration(
                        color: Color(0xFF2F6B4B),
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
            selected: _showMineOnly,
            label: const Text('只看我的'),
            onSelected: (value) {
              setState(() => _showMineOnly = value);
            },
          ),
          FilterChip(
            selected: _showFavoritesOnly,
            label: const Text('只看收藏'),
            onSelected: (value) {
              setState(() => _showFavoritesOnly = value);
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
              _placingMode
                  ? Icons.close_rounded
                  : Icons.add_location_alt_rounded,
            ),
            label: Text(_placingMode ? '退出放置' : '新增标记'),
          ),
        ],
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
            decoration: const InputDecoration(
              labelText: '分类',
              filled: true,
            ),
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
          SwitchListTile(
            value: _showMineOnly,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('只看我的标记'),
            onChanged: (value) {
              setState(() => _showMineOnly = value);
            },
          ),
          SwitchListTile(
            value: _showFavoritesOnly,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('只看收藏地点'),
            onChanged: (value) {
              setState(() => _showFavoritesOnly = value);
            },
          ),
          const SizedBox(height: 8),
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
                      _selectedCategory =
                          _selectedCategory == category ? null : category;
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

  Widget _buildToolRail(
    BuildContext context, {
    required Size viewportSize,
  }) {
    return _GlassPanel(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolIconButton(
            tooltip: '放大',
            icon: Icons.add_rounded,
            onPressed: () => _zoomBy(1.18, viewportSize),
          ),
          const SizedBox(height: 8),
          _ToolIconButton(
            tooltip: '缩小',
            icon: Icons.remove_rounded,
            onPressed: () => _zoomBy(0.86, viewportSize),
          ),
          const SizedBox(height: 8),
          _ToolIconButton(
            tooltip: '回到默认视角',
            icon: Icons.home_work_rounded,
            onPressed: _resetViewport,
          ),
          const SizedBox(height: 8),
          _ToolIconButton(
            tooltip: _showMarkers ? '隐藏标记' : '显示标记',
            icon: _showMarkers
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            onPressed: () => setState(() => _showMarkers = !_showMarkers),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDock(
    BuildContext context, {
    required int visibleCount,
    required int totalCount,
    required String categorySummary,
    required int buildingCount,
    required int hiddenLegacyPlaceCount,
    required String? zoneName,
  }) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MapInfoBadge(
            icon: Icons.place_rounded,
            label: '$visibleCount / $totalCount 地点',
          ),
          _MapInfoBadge(
            icon: Icons.category_rounded,
            label: categorySummary,
          ),
          if (zoneName != null)
            _MapInfoBadge(
              icon: Icons.public_rounded,
              label: zoneName,
            ),
          if (buildingCount > 0)
            _MapInfoBadge(
              icon: Icons.apartment_rounded,
              label: '$buildingCount 栋楼',
            ),
          if (hiddenLegacyPlaceCount > 0)
            _MapInfoBadge(
              icon: Icons.push_pin_outlined,
              label: '$hiddenLegacyPlaceCount 个旧示意点已隐藏',
            ),
          if (_showFavoritesOnly)
            const _MapInfoBadge(
              icon: Icons.star_rounded,
              label: '仅收藏',
            ),
          if (_showMineOnly)
            const _MapInfoBadge(
              icon: Icons.person_pin_circle_rounded,
              label: '仅我的标记',
            ),
          if (!_showMarkers)
            const _MapInfoBadge(
              icon: Icons.visibility_off_rounded,
              label: '标记已隐藏',
            ),
          if (_publicMapScene != null)
            const _MapInfoBadge(
              icon: Icons.verified_rounded,
              label: '公开底图已接入',
            ),
        ],
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
                        iconKey: place.iconKey,
                        iconSize: 22,
                        iconColor: Colors.white,
                        textStyle:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
    final anchor = _draftPosition ??
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
            editingPlace == null
                ? '地点将在保存后正式落到地图上。'
                : '当前仅调整地点信息，保留原有地图坐标。',
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
                      iconKey: _resolvedEditingIconKey(),
                      iconSize: 20,
                      iconColor: Colors.white,
                      textStyle:
                          Theme.of(context).textTheme.labelLarge?.copyWith(
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
          if (_editingCategory == PlaceCategory.other) ...[
            TextField(
              controller: _customLabelController,
              maxLength: 3,
              decoration: const InputDecoration(
                labelText: '文字标记',
                hintText: '例如：午、静心角、办卡',
                helperText: '留空时，会回退到备注前两个字。',
              ),
              onChanged: (value) {
                setState(() {
                  _customLabelEdited = value.trim().isNotEmpty;
                });
              },
            ),
            const SizedBox(height: 12),
          ],
          Text(
            '颜色',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
                  onPressed: () => _confirmDeletePlace(controller, editingPlace),
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

  void _handleTransformChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _zoom = _mapTransformController.value.getMaxScaleOnAxis();
    });
  }

  void _handleNoteChanged() {
    if (_editingCategory != PlaceCategory.other || _customLabelEdited) {
      return;
    }
    final nextLabel = _deriveAutoMarkerText(
      _noteController.text,
      fallback: _nameController.text,
    );
    if (_customLabelController.text == nextLabel) {
      return;
    }
    _customLabelController.value = TextEditingValue(
      text: nextLabel,
      selection: TextSelection.collapsed(offset: nextLabel.length),
    );
    if (mounted) {
      setState(() {});
    }
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
        _selectedBuildingId = null;
        _editingPlaceId = null;
      });
      return;
    }

    setState(() {
      _selectedPlaceId = null;
      _selectedBuildingId = null;
      _editingPlaceId = null;
      _draftPosition = null;
      _showFilterPanel = false;
    });
  }

  void _selectPlace(String placeId) {
    setState(() {
      _selectedPlaceId = placeId;
      _selectedBuildingId = null;
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
      _selectedBuildingId = null;
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
      _selectedBuildingId = null;
      _editingCategory = place.category;
      _editingIconKey = _resolveCategoryIconKey(place.category, place.iconKey);
      _editingColorKey = place.colorKey;
      _editingMine = place.isMine;
      _customLabelEdited = customMarkerText.isNotEmpty;
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
        iconKey: _resolvedEditingIconKey(),
        colorKey: _editingColorKey,
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
      iconKey: _resolvedEditingIconKey(),
      colorKey: _editingColorKey,
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
    _customLabelEdited = false;
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
          _customLabelEdited = false;
        } else {
          _customLabelEdited = true;
        }
      }
    });
  }

  String _resolvedEditingIconKey() {
    if (_editingCategory != PlaceCategory.other) {
      return _CampusMapStyles.defaultIconKeyForCategory(_editingCategory);
    }
    final custom = _sanitizeCustomMarkerText(_customLabelController.text);
    final fallback = _deriveAutoMarkerText(
      _noteController.text,
      fallback: _nameController.text,
    );
    return 'text:${custom ?? fallback}';
  }

  String _resolveCategoryIconKey(PlaceCategory category, String currentIconKey) {
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

  Future<void> _loadPublicMap({int? zoneId}) async {
    if (mounted) {
      setState(() {
        _publicMapBusy = true;
        _publicMapError = null;
      });
    }

    try {
      final zones = _publicZones.isEmpty
          ? await _publicMapService.fetchZones()
          : _publicZones;
      if (zones.isEmpty) {
        throw Exception('未发现可公开访问的 2D 校区地图。');
      }

      PublicCampusZone zone = zones.first;
      final requestedZoneId = zoneId ?? _publicMapScene?.zone.id;
      if (requestedZoneId != null) {
        for (final item in zones) {
          if (item.id == requestedZoneId) {
            zone = item;
            break;
          }
        }
      }

      final scene = await _publicMapService.fetchScene(zone);
      if (!mounted) {
        return;
      }

      setState(() {
        _publicZones = zones;
        _publicMapScene = scene;
        _publicMapBusy = false;
        _publicMapError = null;
        _selectedBuildingId = null;
      });
      _resetViewport();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _publicMapBusy = false;
        _publicMapError = '公开地图加载失败：$error';
      });
    }
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedCategory = null;
      _showMineOnly = false;
      _showFavoritesOnly = false;
    });
  }

  void _resetViewport() {
    _mapTransformController.value = Matrix4.identity();
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
    return MatrixUtils.transformPoint(_mapTransformController.value, scenePoint);
  }

  List<CampusPlace> _filterPlaces(List<CampusPlace> places) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = places.where((place) {
      if (_selectedCategory != null && place.category != _selectedCategory) {
        return false;
      }
      if (_showMineOnly && !place.isMine) {
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
      final favoriteDiff =
          (right.isFavorite ? 1 : 0).compareTo(left.isFavorite ? 1 : 0);
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
    if (_showMineOnly) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

class _MapInfoBadge extends StatelessWidget {
  const _MapInfoBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.tokens.borderFaint),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.tokens.accent),
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
  const _MiniMeta({
    required this.icon,
    required this.label,
  });

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
          color: selected ? color.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.42) : context.tokens.borderFaint,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
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
  const _SearchResultTile({
    required this.place,
    required this.onTap,
  });

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
                    iconKey: place.iconKey,
                    iconSize: 20,
                    iconColor: Colors.white,
                    textStyle:
                        Theme.of(context).textTheme.labelMedium?.copyWith(
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

class _BuildingSearchResultTile extends StatelessWidget {
  const _BuildingSearchResultTile({
    required this.building,
    required this.onTap,
  });

  final PublicCampusBuilding building;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (building.kind.trim().isNotEmpty) building.kind,
      if (building.levels != null) '${building.levels} 层',
    ];

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
                  color: const Color(0xFF315D49),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      building.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: context.tokens.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleParts.isEmpty
                          ? '公开建筑'
                          : subtitleParts.join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.tokens.textSecondary,
                          ),
                    ),
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
  const _SearchSectionLabel({
    required this.icon,
    required this.label,
  });

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

class _MapFetchStatusChip extends StatelessWidget {
  const _MapFetchStatusChip({
    required this.busy,
    required this.errorText,
    required this.onRetry,
  });

  final bool busy;
  final String? errorText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      width: 320,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            const Icon(Icons.warning_amber_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              busy ? '正在加载公开校园底图…' : (errorText ?? '公开校园底图加载失败'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (!busy && onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _ToolIconButton extends StatelessWidget {
  const _ToolIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.68),
        foregroundColor: context.tokens.textPrimary,
        side: BorderSide(color: context.tokens.borderFaint),
        fixedSize: const Size(44, 44),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _PlaceGlyph extends StatelessWidget {
  const _PlaceGlyph({
    required this.iconKey,
    this.iconSize = 20,
    this.iconColor = Colors.white,
    this.textStyle,
  });

  final String iconKey;
  final double iconSize;
  final Color iconColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final markerText = _CampusMapStyles.textForIconKey(iconKey);
    if (markerText.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            markerText,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: textStyle ??
                Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w800,
                    ),
          ),
        ),
      );
    }
    return Icon(
      _CampusMapStyles.iconForKey(iconKey),
      size: iconSize,
      color: iconColor,
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
            border: Border.all(
              color: Colors.white,
              width: selected ? 3 : 2,
            ),
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
              iconKey: place.iconKey,
              iconSize: selected ? 22 : 18,
              iconColor: Colors.white,
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF2F6B4B),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6B4B).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(
        Icons.add_rounded,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}

class _AreaLabelChip extends StatelessWidget {
  const _AreaLabelChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.tokens.borderFaint),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
      ),
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
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
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
  const _DetailCardPointer({
    required this.color,
    required this.borderColor,
  });

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

    final fitsRight = anchor.dx + 24 + cardWidth <= viewportSize.width - edgeInset;
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

class _CampusPlanPainter extends CustomPainter {
  const _CampusPlanPainter({
    required this.tokens,
    required this.scene,
    required this.selectedBuildingId,
    required this.highlightedBuildingIds,
  });

  final AppTokens tokens;
  final PublicCampusMapScene? scene;
  final String? selectedBuildingId;
  final Set<String> highlightedBuildingIds;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    if (scene == null) {
      _paintFallbackScene(canvas, size);
      return;
    }

    for (final building in scene!.buildings) {
      final palette = _paletteForKind(building.kind);
      final isSelected = building.id == selectedBuildingId;
      final isHighlighted = highlightedBuildingIds.contains(building.id);
      final fillPaint = Paint()
        ..color = palette.fill.withValues(
          alpha: isSelected
              ? 0.92
              : isHighlighted
              ? 0.8
              : 0.62,
        )
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = palette.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.4 : 1.1;

      for (final polygon in building.polygons) {
        final path = Path();
        for (var index = 0; index < polygon.length; index++) {
          final point = Offset(
            polygon[index].dx * size.width,
            polygon[index].dy * size.height,
          );
          if (index == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        canvas.drawShadow(
          path,
          Colors.black.withValues(alpha: isSelected ? 0.18 : 0.08),
          isSelected ? 8 : 4,
          false,
        );
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
      }
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF7F8F4),
          const Color(0xFFEFF5EE),
          const Color(0xFFF8FBF8),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final dotPaint = Paint()
      ..color = tokens.borderFaint.withValues(alpha: 0.56)
      ..style = PaintingStyle.fill;
    const gap = 40.0;
    for (double x = gap; x < size.width; x += gap) {
      for (double y = gap; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1.1, dotPaint);
      }
    }
  }

  void _paintFallbackScene(Canvas canvas, Size size) {
    final greenPaint = Paint()
      ..color = const Color(0xFFDDEBDD)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.12,
          size.height * 0.12,
          size.width * 0.26,
          size.height * 0.22,
        ),
        const Radius.circular(36),
      ),
      greenPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.65,
          size.height * 0.58,
          size.width * 0.2,
          size.height * 0.17,
        ),
        const Radius.circular(36),
      ),
      greenPaint,
    );

    final lakePath = Path()
      ..moveTo(size.width * 0.54, size.height * 0.28)
      ..quadraticBezierTo(
        size.width * 0.62,
        size.height * 0.16,
        size.width * 0.73,
        size.height * 0.27,
      )
      ..quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.38,
        size.width * 0.69,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.49,
        size.width * 0.52,
        size.height * 0.38,
      )
      ..close();
    canvas.drawPath(
      lakePath,
      Paint()
        ..color = const Color(0xFFD9EAF2)
        ..style = PaintingStyle.fill,
    );
  }

  ({Color fill, Color stroke}) _paletteForKind(String kind) {
    return switch (kind) {
      'teaching' || 'library' => (
        fill: const Color(0xFFCFE5D5),
        stroke: const Color(0xFF2F6B4B),
      ),
      'student_bedroom' || 'families_house' => (
        fill: const Color(0xFFDCE6F5),
        stroke: const Color(0xFF3E6FA5),
      ),
      'hospital' || 'service_building' => (
        fill: const Color(0xFFF0DFC9),
        stroke: const Color(0xFF9C6B2F),
      ),
      'administration' || 'office' => (
        fill: const Color(0xFFE6D8EE),
        stroke: const Color(0xFF7B5DA7),
      ),
      _ => (
        fill: Colors.white,
        stroke: tokens.borderSoft,
      ),
    };
  }

  @override
  bool shouldRepaint(covariant _CampusPlanPainter oldDelegate) {
    return oldDelegate.tokens != tokens ||
        oldDelegate.scene != scene ||
        oldDelegate.selectedBuildingId != selectedBuildingId ||
        oldDelegate.highlightedBuildingIds.length !=
            highlightedBuildingIds.length ||
        !oldDelegate.highlightedBuildingIds.containsAll(
          highlightedBuildingIds,
        ) ||
        !highlightedBuildingIds.containsAll(oldDelegate.highlightedBuildingIds);
  }
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
    _IconOption(
      key: 'bed',
      label: '\u5bbf\u820d',
      icon: Icons.bed_rounded,
    ),
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

  static const List<_AreaAnchor> areaAnchors = [
    _AreaAnchor(label: '\u56fe\u4e66\u9986\u533a', dx: 0.27, dy: 0.16),
    _AreaAnchor(label: '\u6e56\u5fc3\u8349\u576a', dx: 0.61, dy: 0.2),
    _AreaAnchor(label: '\u98df\u5802\u8f74\u7ebf', dx: 0.69, dy: 0.28),
    _AreaAnchor(label: '\u5b9e\u9a8c\u697c\u7ec4\u56e2', dx: 0.47, dy: 0.45),
    _AreaAnchor(label: '\u5bbf\u820d\u533a', dx: 0.16, dy: 0.64),
    _AreaAnchor(label: '\u8fd0\u52a8\u573a', dx: 0.76, dy: 0.61),
  ];

  static IconData iconForKey(String key) {
    for (final option in iconOptions) {
      if (option.key == key) {
        return option.icon;
      }
    }
    return Icons.place_rounded;
  }

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

class _AreaAnchor {
  const _AreaAnchor({
    required this.label,
    required this.dx,
    required this.dy,
  });

  final String label;
  final double dx;
  final double dy;
}
