import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/pet/pet_companion_service.dart';
import '../../services/utility/privacy_screen.dart';
import '../../shared/widgets/frosted_glass.dart';
import '../../state/research_life_controller.dart';
import '../../shared/widgets/section_card.dart';
import 'widgets/local_backup_panel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _settingsSearchController;
  late final TextEditingController _calendarInputController;
  late final TextEditingController _weatherApiKeyController;
  late final TextEditingController _weatherApiHostController;
  bool _weatherApiKeyVisible = false;
  String? _syncedCalendarEditSessionId;
  String _settingsQuery = '';
  _SettingsCategory _selectedCategory = _SettingsCategory.all;
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    _settingsSearchController = TextEditingController();
    _calendarInputController = TextEditingController();
    _weatherApiKeyController = TextEditingController();
    _weatherApiHostController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ResearchLifeScope.of(context);
      unawaited(controller.ensureHomeGalleryReady());
      unawaited(controller.ensurePetCompanionLoaded());
      unawaited(_loadWeatherSettings(controller));
    });
  }

  Future<void> _loadWeatherSettings(ResearchLifeController controller) async {
    await controller.ensureWeatherApiLoaded();
    if (!mounted) return;
    _weatherApiKeyController.text = controller.weatherApiKey;
    _weatherApiHostController.text = controller.weatherApiHost;
    setState(() {});
  }

  @override
  void dispose() {
    _settingsSearchController.dispose();
    _calendarInputController.dispose();
    _weatherApiKeyController.dispose();
    _weatherApiHostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final importedCount = controller.institutionCalendarEvents.length;
        final editingCalendarSessionId =
            controller.editingInstitutionCalendarSessionId;
        final isEditingCalendar = editingCalendarSessionId != null;
        if (_syncedCalendarEditSessionId != editingCalendarSessionId) {
          _syncedCalendarEditSessionId = editingCalendarSessionId;
          final editingText = controller.editingInstitutionCalendarText;
          if (editingCalendarSessionId != null && editingText != null) {
            _calendarInputController.text = editingText;
          }
        }
        final calendarSubtitle = isEditingCalendar
            ? '正在编辑${controller.editingInstitutionCalendarTitle == null ? '' : ' · ${controller.editingInstitutionCalendarTitle}'}，保存后会覆盖这条历史记录。'
            : importedCount == 0
            ? '把外部识别后的校历文本贴到下方，导入后会直接标注到主页日历。'
            : '当前已导入$importedCount 条校历事件${controller.institutionCalendarTitle == null ? '' : ' · ${controller.institutionCalendarTitle}'}';

        final sections = <_SettingsSectionSpec>[
          _SettingsSectionSpec(
            id: 'home.weather',
            category: _SettingsCategory.general,
            icon: Icons.cloud_outlined,
            title: '主页天气',
            subtitle: '配置天气服务，仅在本机保存。',
            keywords: const ['天气', 'API Key', 'API Host', '和风天气'],
            childBuilder: (_) => _WeatherSettingsPanel(
              apiKeyController: _weatherApiKeyController,
              apiHostController: _weatherApiHostController,
              apiKeyVisible: _weatherApiKeyVisible,
              onApiKeyVisibilityChanged: (visible) =>
                  setState(() => _weatherApiKeyVisible = visible),
              onSave: () => _runAsyncAction(
                context,
                () => controller.saveWeatherApiSettings(
                  apiKey: _weatherApiKeyController.text,
                  apiHost: _weatherApiHostController.text,
                ),
              ),
            ),
          ),
          _SettingsSectionSpec(
            id: 'storage.local_backup',
            category: _SettingsCategory.storage,
            icon: Icons.backup_rounded,
            title: '备份与恢复',
            subtitle: '本地备份数据库、资料清单和工作区文件。',
            keywords: const ['备份', '恢复', '本地', '数据', '目录'],
            childBuilder: (_) => const LocalBackupPanel(showHeading: false),
          ),
          _SettingsSectionSpec(
            id: 'appearance.theme',
            category: _SettingsCategory.appearance,
            icon: Icons.palette_rounded,
            title: '颜色主题',
            subtitle: '选择软件整体配色，设置会自动保存。',
            keywords: const ['配色', '外观', '主题', '颜色', 'green', 'pink', 'blue'],
            childBuilder: (_) => _ColorThemeGrid(
              selectedTheme: controller.colorTheme,
              onSelected: (theme) => _runAsyncAction(
                context,
                () => controller.setColorTheme(theme),
              ),
            ),
          ),
          _SettingsSectionSpec(
            id: 'appearance.frosted_glass',
            category: _SettingsCategory.appearance,
            icon: Icons.blur_on_rounded,
            title: '毛玻璃效果',
            subtitle: '调整首页待办提示、校园地图等所有毛玻璃面板的模糊、白度与质感。',
            keywords: const [
              '毛玻璃',
              '玻璃',
              '模糊',
              '透明',
              '材质',
              'frosted',
              'glass',
              'blur',
            ],
            trailingBuilder: (_) => TextButton.icon(
              onPressed: () => _runAsyncAction(context, () async {
                await controller.saveGlassSettings(const GlassSettings());
                return '已恢复默认毛玻璃效果。';
              }),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('恢复默认'),
            ),
            childBuilder: (_) => _GlassSettingsPanel(
              settings: controller.glassSettings,
              onChanged: (settings) => controller.saveGlassSettings(settings),
            ),
          ),
          _SettingsSectionSpec(
            id: 'companion.pet',
            category: _SettingsCategory.companion,
            icon: Icons.smart_toy_rounded,
            title: '桌宠',
            subtitle: '使用 Hatch Pet 图集资源，启动研究生活时直接显示并提醒当天任务。',
            keywords: const ['宠物', '桌宠', 'Hatch Pet', '自动启动', '提醒', '说话'],
            childBuilder: (_) => _PetCompanionPanel(
              activePet: controller.activePet,
              pets: controller.availablePets,
              autoStart: controller.petAutoStart,
              closeWithApp: controller.petCloseWithApp,
              running: controller.petRunning,
              busy: controller.petCompanionBusy,
              onImportPet: () =>
                  _runAsyncAction(context, controller.importPetPackage),
              onPetSelected: (petId) =>
                  _runAsyncAction(context, () => controller.selectPet(petId)),
              onStart: () =>
                  _runAsyncAction(context, controller.startPetCompanion),
              onStop: () =>
                  _runAsyncAction(context, controller.stopPetCompanion),
              onTestMessage: () =>
                  _runAsyncAction(context, controller.sendPetTestMessage),
              onAutoStartChanged: (value) => _runAsyncAction(
                context,
                () => controller.setPetAutoStart(value),
              ),
              onCloseWithAppChanged: (value) => _runAsyncAction(
                context,
                () => controller.setPetCloseWithApp(value),
              ),
            ),
          ),
          _SettingsSectionSpec(
            id: 'storage.paths',
            category: _SettingsCategory.storage,
            icon: Icons.folder_open_rounded,
            title: '文件位置',
            subtitle: '打开本地数据、数据库、导出目录和主页图片目录。',
            keywords: const [
              '文件',
              '路径',
              '目录',
              'SQLite',
              '数据库',
              '备份',
              '咨询包',
              '导出',
            ],
            childBuilder: (_) => Column(
              children: [
                _PathRow(
                  title: '应用数据目录',
                  path: controller.storageDirectoryPath,
                  buttonLabel: '打开应用数据目录',
                  busy: controller.galleryBusy,
                  onOpen: () =>
                      _runAsyncAction(context, controller.openStorageFolder),
                ),
                const SizedBox(height: 14),
                _PathRow(
                  title: 'SQLite 数据库文件',
                  path: controller.databaseFilePath,
                  buttonLabel: '打开数据库目录',
                  busy: controller.galleryBusy,
                  onOpen: () =>
                      _runAsyncAction(context, controller.openDatabaseFolder),
                ),
                const SizedBox(height: 14),
                _PathRow(
                  title: '咨询包导出',
                  path: controller.storageDirectoryPath == null
                      ? null
                      : '${controller.storageDirectoryPath}'
                            '${Platform.pathSeparator}consulting_packages',
                  buttonLabel: '导出咨询包',
                  busy: controller.galleryBusy,
                  onOpen: () => _runAsyncAction(
                    context,
                    controller.exportConsultingPackage,
                  ),
                ),
                const SizedBox(height: 14),
                _PathRow(
                  title: '主页图片文件夹',
                  path: controller.homeImageFolderPath,
                  buttonLabel: '打开图片文件夹',
                  busy: controller.galleryBusy,
                  onOpen: () =>
                      _runAsyncAction(context, controller.openHomeImageFolder),
                ),
              ],
            ),
          ),
          _SettingsSectionSpec(
            id: 'home.images',
            category: _SettingsCategory.storage,
            icon: Icons.image_rounded,
            title: '主页图片',
            subtitle: '管理主页右侧两张展示图片。',
            keywords: const ['图片', '主页', '照片', '展示图', '刷新'],
            trailingBuilder: (_) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.galleryBusy
                      ? null
                      : () => _runAsyncAction(
                          context,
                          controller.openHomeImageFolder,
                        ),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('打开目录'),
                ),
                FilledButton.tonalIcon(
                  onPressed: controller.galleryBusy
                      ? null
                      : () => _runAsyncAction(
                          context,
                          controller.refreshHomeImages,
                        ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新图片'),
                ),
              ],
            ),
            childBuilder: (_) => Column(
              children: [
                _ImageManageRow(
                  title: '照片 1',
                  caption: '上方图片位。',
                  imagePath: controller.researchWallImagePath,
                  busy: controller.galleryBusy,
                  onReplace: () => _runAsyncAction(
                    context,
                    () =>
                        controller.replaceHomeImage(HomeImageSlot.researchWall),
                  ),
                ),
                const SizedBox(height: 14),
                _ImageManageRow(
                  title: '照片 2',
                  caption: '下方图片位。',
                  imagePath: controller.lifeWallImagePath,
                  busy: controller.galleryBusy,
                  onReplace: () => _runAsyncAction(
                    context,
                    () => controller.replaceHomeImage(HomeImageSlot.lifeWall),
                  ),
                ),
              ],
            ),
          ),
          _SettingsSectionSpec(
            id: 'general.closeToTray',
            category: _SettingsCategory.general,
            icon: Icons.system_update_alt_rounded,
            title: '后台挂起（系统托盘）',
            subtitle: '关闭窗口时最小化到系统托盘继续后台运行，点击托盘图标可随时唤回；关闭后点 ✕ 直接退出。',
            keywords: const ['托盘', '挂起', '后台', '最小化', '关闭', 'tray'],
            childBuilder: (_) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                '关闭窗口后程序继续在系统托盘运行，日历提醒与本地任务照常工作；'
                '单击托盘图标唤回窗口，右键托盘图标可选择「退出」彻底结束程序。',
                style: TextStyle(
                  color: context.tokens.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            trailingBuilder: (_) => Switch(
              value: controller.closeToTray,
              onChanged: (value) => controller.setCloseToTray(value),
            ),
          ),
          _SettingsSectionSpec(
            id: 'general.privacyScreen',
            category: _SettingsCategory.general,
            icon: Icons.visibility_off_rounded,
            title: '远程隐私屏',
            subtitle: '一键切换「仅虚拟显示器」：本地物理屏彻底无信号，远程画面照常。',
            keywords: const ['隐私屏', '虚拟显示器', 'IDD', '仅第二屏幕', '黑屏', 'privacy'],
            childBuilder: (_) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '需要先安装虚拟显示器驱动（IddSampleDriver）。'
                    '开启后本地屏幕完全关闭，'
                    '远程软件仍可看到完整画面。',
                    style: TextStyle(
                      color: context.tokens.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PrivacyScreenStatusTile(),
                ],
              ),
            ),
            trailingBuilder: (_) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _togglePrivacyScreen(context, enable: true),
                  icon: const Icon(
                    Icons.desktop_access_disabled_rounded,
                    size: 18,
                  ),
                  label: const Text('进入隐私屏'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _togglePrivacyScreen(context, enable: false),
                  icon: const Icon(Icons.monitor_rounded, size: 18),
                  label: const Text('恢复屏幕'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _matchVirtualResolution(context),
                  icon: const Icon(Icons.aspect_ratio_rounded, size: 18),
                  label: const Text('虚拟屏=本机分辨率'),
                ),
              ],
            ),
          ),
          _SettingsSectionSpec(
            id: 'calendar.import',
            category: _SettingsCategory.calendar,
            icon: Icons.calendar_month_rounded,
            title: '校历导入',
            subtitle: calendarSubtitle,
            keywords: const [
              '校历',
              '日历',
              '导入',
              '模板',
              '提示词',
              '外部识别',
              'CALENDAR_IMPORT_V1',
            ],
            trailingBuilder: (_) => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(
                    () => _calendarInputController.text =
                        controller.institutionCalendarTemplate,
                  ),
                  icon: const Icon(Icons.article_rounded),
                  label: const Text('填入模板'),
                ),
                if (isEditingCalendar)
                  OutlinedButton.icon(
                    onPressed: () => _runSyncAction(context, () {
                      final message = controller
                          .cancelInstitutionCalendarEditing();
                      _syncedCalendarEditSessionId = null;
                      return message ?? '';
                    }),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('取消编辑'),
                  ),
                if (importedCount > 0)
                  OutlinedButton.icon(
                    onPressed: () => _runSyncAction(context, () {
                      final message = controller.clearInstitutionCalendar();
                      _syncedCalendarEditSessionId = null;
                      _calendarInputController.clear();
                      return message;
                    }),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('清空校历'),
                  ),
                FilledButton.icon(
                  onPressed: () => _runSyncAction(
                    context,
                    () => controller.importInstitutionCalendar(
                      _calendarInputController.text,
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(isEditingCalendar ? '保存校历' : '导入校历'),
                ),
              ],
            ),
            childBuilder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoBanner(
                  title: '支持的文本格式',
                  body:
                      '每行一个事件，固定写成“开始日期| 结束日期 | 事件标题 | 分类 | 类型”。分类只支持 study/work/life/health/social/other，类型只支持 plan/record。',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _calendarInputController,
                  minLines: 10,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    hintText:
                        '例如：\nCALENDAR_IMPORT_V1\nTITLE: XX大学 2026 学年校历\n2026-02-23 | 2026-03-01 | 寒假 | life | plan',
                  ),
                ),
                const SizedBox(height: 16),
                _CopyableBlock(
                  title: '给外部识别软件的提示词',
                  text: controller.institutionCalendarPrompt,
                ),
                const SizedBox(height: 14),
                _CopyableBlock(
                  title: '标准输出模板',
                  text: controller.institutionCalendarTemplate,
                ),
              ],
            ),
          ),
          _SettingsSectionSpec(
            id: 'calendar.reminders',
            category: _SettingsCategory.calendar,
            icon: Icons.alarm_rounded,
            title: '日历提醒',
            subtitle: '当天有计划事件时，在应用右下角弹出毛玻璃提醒卡片。',
            keywords: const ['提醒', '日历', '通知', 'alarm', 'reminder', '计划', '到点'],
            childBuilder: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingsSwitchRow(
                  title: '启用日历事件提醒',
                  subtitle: '周分析与手动添加的「计划」事件到点后提醒。',
                  value: controller.calendarRemindersEnabled,
                  onChanged: (value) =>
                      controller.setCalendarRemindersEnabled(value),
                ),
                const SizedBox(height: 12),
                Text(
                  '提醒时机：当天有「计划」事件时提醒一次（应用启动后及每小时检查）；'
                  '提醒卡片展示 15 秒，可手动关闭。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _SettingsSectionSpec(
            id: 'security.pin_lock',
            category: _SettingsCategory.security,
            icon: Icons.lock_rounded,
            title: '锁屏密码',
            subtitle: '可调整无人操作后的自动锁定时间，重新启动仍需 PIN。',
            keywords: const ['锁屏', '密码', 'PIN', '安全', '锁定', 'unlock'],
            childBuilder: (_) => _PinLockPanel(controller: controller),
          ),
        ];
        final normalizedQuery = _settingsQuery.trim();
        final visibleSections = sections
            .where(
              (section) =>
                  section.isVisible(_selectedCategory, normalizedQuery),
            )
            .toList(growable: false);
        final categoryCounts = _categoryCounts(sections, normalizedQuery);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
              child: _SettingsLocatorBar(
                searchController: _settingsSearchController,
                query: _settingsQuery,
                selectedCategory: _selectedCategory,
                categoryCounts: categoryCounts,
                visibleCount: visibleSections.length,
                totalCount: sections.length,
                onQueryChanged: (value) =>
                    setState(() => _settingsQuery = value),
                onClearQuery: _clearSettingsSearch,
                onCategoryChanged: (category) =>
                    setState(() => _selectedCategory = category),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                child: visibleSections.isEmpty
                    ? _SettingsNoResults(onReset: _resetSettingsFilters)
                    : _SettingsContentLayout(
                        sections: visibleSections,
                        sectionBuilder: (section) =>
                            _buildSettingsSectionCard(context, section),
                        onSectionSelected: (section) =>
                            _scrollToSettingsSection(section.id),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsSectionCard(
    BuildContext context,
    _SettingsSectionSpec section,
  ) {
    return SectionCard(
      key: _sectionKeyFor(section.id),
      title: section.title,
      subtitle: section.subtitle,
      trailing: section.trailingBuilder?.call(context),
      child: section.childBuilder(context),
    );
  }

  GlobalKey _sectionKeyFor(String id) {
    return _sectionKeys.putIfAbsent(
      id,
      () => GlobalKey(debugLabel: 'settings-section-$id'),
    );
  }

  Future<void> _scrollToSettingsSection(String id) async {
    final sectionContext = _sectionKeys[id]?.currentContext;
    if (sectionContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Map<_SettingsCategory, int> _categoryCounts(
    List<_SettingsSectionSpec> sections,
    String query,
  ) {
    return {
      for (final category in _SettingsCategory.values)
        category: sections
            .where((section) => section.isVisible(category, query))
            .length,
    };
  }

  void _clearSettingsSearch() {
    _settingsSearchController.clear();
    if (_settingsQuery.isEmpty) {
      return;
    }
    setState(() => _settingsQuery = '');
  }

  void _resetSettingsFilters() {
    _settingsSearchController.clear();
    setState(() {
      _settingsQuery = '';
      _selectedCategory = _SettingsCategory.all;
    });
  }

  Future<void> _runAsyncAction(
    BuildContext context,
    Future<String?> Function() action,
  ) async {
    try {
      final message = await action();
      if (!context.mounted || message == null || message.isEmpty) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
    }
  }

  Future<void> _matchVirtualResolution(BuildContext context) async {
    final message = matchVirtualDisplayToPrimary();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? '虚拟屏已设置为本机分辨率，远程画面应恢复原始大小。')),
    );
  }

  Future<void> _togglePrivacyScreen(
    BuildContext context, {
    required bool enable,
  }) async {
    final message = enable
        ? enterPrivacyScreen()
        : setPrivacyScreen(enable: false);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? (enable ? '已切换至隐私屏（本地屏幕已关闭）。' : '已恢复内置屏幕。')),
      ),
    );
  }

  Future<void> _runSyncAction(
    BuildContext context,
    String Function() action,
  ) async {
    try {
      final message = action();
      if (!context.mounted || message.isEmpty) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }
}

enum _SettingsCategory {
  all,
  general,
  appearance,
  analysis,
  companion,
  storage,
  calendar,
  security,
}

extension _SettingsCategoryDetails on _SettingsCategory {
  String get label => switch (this) {
    _SettingsCategory.all => '全部',
    _SettingsCategory.general => '通用',
    _SettingsCategory.appearance => '外观',
    _SettingsCategory.analysis => '智能分析',
    _SettingsCategory.companion => '桌宠',
    _SettingsCategory.storage => '数据文件',
    _SettingsCategory.calendar => '校历',
    _SettingsCategory.security => '安全',
  };

  IconData get icon => switch (this) {
    _SettingsCategory.all => Icons.tune_rounded,
    _SettingsCategory.general => Icons.widgets_rounded,
    _SettingsCategory.appearance => Icons.palette_rounded,
    _SettingsCategory.analysis => Icons.psychology_alt_rounded,
    _SettingsCategory.companion => Icons.smart_toy_rounded,
    _SettingsCategory.storage => Icons.folder_open_rounded,
    _SettingsCategory.calendar => Icons.calendar_month_rounded,
    _SettingsCategory.security => Icons.lock_rounded,
  };
}

typedef _SettingsSectionWidgetBuilder = Widget Function(BuildContext context);
typedef _SettingsSectionCardBuilder =
    Widget Function(_SettingsSectionSpec section);

class _SettingsSectionSpec {
  const _SettingsSectionSpec({
    required this.id,
    required this.category,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.childBuilder,
    this.trailingBuilder,
  });

  final String id;
  final _SettingsCategory category;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final _SettingsSectionWidgetBuilder childBuilder;
  final _SettingsSectionWidgetBuilder? trailingBuilder;

  bool isVisible(_SettingsCategory selectedCategory, String rawQuery) {
    final categoryMatches =
        selectedCategory == _SettingsCategory.all ||
        category == selectedCategory;
    return categoryMatches && matchesQuery(rawQuery);
  }

  bool matchesQuery(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    final terms = query
        .split(RegExp(r'\s+'))
        .where((term) => term.trim().isNotEmpty);
    final target = [
      id,
      title,
      subtitle,
      category.label,
      ...keywords,
    ].join(' ').toLowerCase();
    return terms.every((term) => target.contains(term));
  }
}

class _SettingsLocatorBar extends StatelessWidget {
  const _SettingsLocatorBar({
    required this.searchController,
    required this.query,
    required this.selectedCategory,
    required this.categoryCounts,
    required this.visibleCount,
    required this.totalCount,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onCategoryChanged,
  });

  final TextEditingController searchController;
  final String query;
  final _SettingsCategory selectedCategory;
  final Map<_SettingsCategory, int> categoryCounts;
  final int visibleCount;
  final int totalCount;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<_SettingsCategory> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final searchField = TextField(
                controller: searchController,
                onChanged: onQueryChanged,
                decoration: InputDecoration(
                  hintText: '搜索设置、路径、校历、远程模型',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: onClearQuery,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              );
              final resultText = query.trim().isEmpty
                  ? '$totalCount 个设置项'
                  : '匹配 $visibleCount / $totalCount';
              final resultBadge = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tokens.insetSurface,
                  borderRadius: BorderRadius.circular(tokens.radiusMedium),
                  border: Border.all(color: tokens.borderFaint),
                ),
                child: Text(
                  resultText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );

              if (constraints.maxWidth < 680) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    resultBadge,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  resultBadge,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _SettingsCategoryPicker(
            selectedCategory: selectedCategory,
            categoryCounts: categoryCounts,
            onChanged: onCategoryChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsCategoryPicker extends StatelessWidget {
  const _SettingsCategoryPicker({
    required this.selectedCategory,
    required this.categoryCounts,
    required this.onChanged,
  });

  final _SettingsCategory selectedCategory;
  final Map<_SettingsCategory, int> categoryCounts;
  final ValueChanged<_SettingsCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in _SettingsCategory.values)
          ChoiceChip(
            showCheckmark: false,
            selected: selectedCategory == category,
            selectedColor: tokens.accentSoft,
            backgroundColor: tokens.insetSurface,
            side: BorderSide(
              color: selectedCategory == category
                  ? tokens.accent
                  : tokens.borderFaint,
            ),
            visualDensity: VisualDensity.compact,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  category.icon,
                  size: 16,
                  color: selectedCategory == category
                      ? tokens.accent
                      : tokens.textSecondary,
                ),
                const SizedBox(width: 6),
                Text('${category.label} ${categoryCounts[category] ?? 0}'),
              ],
            ),
            onSelected: (_) => onChanged(category),
          ),
      ],
    );
  }
}

class _SettingsContentLayout extends StatelessWidget {
  const _SettingsContentLayout({
    required this.sections,
    required this.sectionBuilder,
    required this.onSectionSelected,
  });

  final List<_SettingsSectionSpec> sections;
  final _SettingsSectionCardBuilder sectionBuilder;
  final ValueChanged<_SettingsSectionSpec> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final index = _SettingsIndexPanel(
      sections: sections,
      onSectionSelected: onSectionSelected,
    );
    final sectionScroll = SingleChildScrollView(
      child: _SettingsSectionColumn(
        sections: sections,
        sectionBuilder: sectionBuilder,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: index,
              ),
              const SizedBox(height: 18),
              Expanded(child: sectionScroll),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 286, child: index),
            const SizedBox(width: 18),
            Expanded(child: sectionScroll),
          ],
        );
      },
    );
  }
}

class _SettingsSectionColumn extends StatelessWidget {
  const _SettingsSectionColumn({
    required this.sections,
    required this.sectionBuilder,
  });

  final List<_SettingsSectionSpec> sections;
  final _SettingsSectionCardBuilder sectionBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          sectionBuilder(sections[index]),
          if (index != sections.length - 1) const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _SettingsIndexPanel extends StatelessWidget {
  const _SettingsIndexPanel({
    required this.sections,
    required this.onSectionSelected,
  });

  final List<_SettingsSectionSpec> sections;
  final ValueChanged<_SettingsSectionSpec> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_alt_rounded, color: tokens.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '设置目录',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${sections.length} 项',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in sections) ...[
                    _SettingsIndexTile(
                      section: section,
                      onTap: () => onSectionSelected(section),
                    ),
                    if (section != sections.last) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsIndexTile extends StatelessWidget {
  const _SettingsIndexTile({required this.section, required this.onTap});

  final _SettingsSectionSpec section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tokens.insetSurface,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(color: tokens.borderFaint),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accentSoft.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                ),
                child: Icon(section.icon, size: 18, color: tokens.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      section.category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: tokens.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsNoResults extends StatelessWidget {
  const _SettingsNoResults({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusLarge),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: tokens.textMuted, size: 34),
          const SizedBox(height: 10),
          Text(
            '没有匹配的设置',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '换一个关键词，或回到全部分类。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重置筛选'),
          ),
        ],
      ),
    );
  }
}

class _ColorThemeGrid extends StatelessWidget {
  const _ColorThemeGrid({
    required this.selectedTheme,
    required this.onSelected,
  });

  final AppColorTheme selectedTheme;
  final ValueChanged<AppColorTheme> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final theme in AppColorTheme.values)
          _ColorThemeOption(
            theme: theme,
            selected: selectedTheme == theme,
            onTap: () => onSelected(theme),
          ),
      ],
    );
  }
}

class _ColorThemeOption extends StatelessWidget {
  const _ColorThemeOption({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final AppColorTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final optionTokens = theme.tokens;

    return SizedBox(
      width: 188,
      height: 118,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? tokens.accentSoft.withValues(alpha: 0.42)
                  : tokens.insetSurface,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
              border: Border.all(
                color: selected ? tokens.accent : tokens.borderFaint,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ThemePreview(tokens: optionTokens, selected: selected),
                Text(
                  theme.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.tokens, required this.selected});

  final AppTokens tokens;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final currentTokens = context.tokens;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.backdropTop,
            tokens.backdropMiddle,
            tokens.backdropBottom,
          ],
        ),
        borderRadius: BorderRadius.circular(currentTokens.radiusSmall),
        border: Border.all(color: currentTokens.borderFaint),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tokens.sidebarSurface, tokens.sidebarSurfaceStrong],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 7,
                          decoration: BoxDecoration(
                            color: tokens.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: currentTokens.accent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _ThemePreviewPanel(
                            color: tokens.panelSurface,
                            borderColor: tokens.borderFaint,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _ThemePreviewPanel(
                            color: tokens.panelAccent,
                            borderColor: tokens.borderSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePreviewPanel extends StatelessWidget {
  const _ThemePreviewPanel({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
    );
  }
}

class _WeatherSettingsPanel extends StatelessWidget {
  const _WeatherSettingsPanel({
    required this.apiKeyController,
    required this.apiHostController,
    required this.apiKeyVisible,
    required this.onApiKeyVisibilityChanged,
    required this.onSave,
  });

  final TextEditingController apiKeyController;
  final TextEditingController apiHostController;
  final bool apiKeyVisible;
  final ValueChanged<bool> onApiKeyVisibilityChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('weather-api-key'),
          controller: apiKeyController,
          obscureText: !apiKeyVisible,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: '控制台-项目管理中创建的 API KEY 凭据',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                apiKeyVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => onApiKeyVisibilityChanged(!apiKeyVisible),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('weather-api-host'),
          controller: apiHostController,
          decoration: const InputDecoration(
            labelText: 'API Host',
            hintText: '例如 n673jraqhk.re.qweatherapi.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '免费注册地址 console.qweather.com，创建项目后添加 API KEY 凭据，并在控制台-设置中复制你的专属 API Host（公共域名已停止服务）。免费额度约 1000 次/天，本应用每 15 分钟刷新一次，个人使用足够。API Key 仅保存在本机偏好中。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const Key('weather-settings-save'),
          onPressed: onSave,
          icon: const Icon(Icons.save_rounded),
          label: const Text('保存并刷新天气'),
        ),
      ],
    );
  }
}

class _PetCompanionPanel extends StatelessWidget {
  const _PetCompanionPanel({
    required this.activePet,
    required this.pets,
    required this.autoStart,
    required this.closeWithApp,
    required this.running,
    required this.busy,
    required this.onImportPet,
    required this.onPetSelected,
    required this.onStart,
    required this.onStop,
    required this.onTestMessage,
    required this.onAutoStartChanged,
    required this.onCloseWithAppChanged,
  });

  final PetDefinition? activePet;
  final List<PetDefinition> pets;
  final bool autoStart;
  final bool closeWithApp;
  final bool running;
  final bool busy;
  final VoidCallback onImportPet;
  final ValueChanged<String> onPetSelected;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onTestMessage;
  final ValueChanged<bool> onAutoStartChanged;
  final ValueChanged<bool> onCloseWithAppChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pet = activePet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.panelSubtle,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            border: Border.all(color: tokens.borderFaint),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 720;
              final status = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    running
                        ? Icons.play_circle_fill_rounded
                        : Icons.pause_circle_rounded,
                    color: running ? tokens.accent : tokens.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    running ? '运行中' : '未运行',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: running ? tokens.accent : tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : onImportPet,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('添加桌宠'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy || pet == null || running ? null : onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('启动桌宠'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || !running ? null : onStop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('关闭'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || !running ? null : onTestMessage,
                    icon: const Icon(Icons.chat_bubble_rounded),
                    label: const Text('测试说话'),
                  ),
                ],
              );

              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    status,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: actions),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: status),
                  const SizedBox(width: 16),
                  actions,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: busy || pets.isEmpty ? null : () => _openPetPicker(context),
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: '当前桌宠',
              border: const OutlineInputBorder(),
              enabled: !busy && pets.isNotEmpty,
              suffixIcon: const Icon(Icons.expand_more_rounded),
            ),
            child: Row(
              children: [
                if (pet != null) ...[
                  _PetFramePreview(pet: pet, width: 44, height: 48),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    pet == null
                        ? '暂无可选桌宠'
                        : '${pet.displayName} · ${pet.isAsset ? '内置' : '项目'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: busy ? tokens.textMuted : tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (pet?.description.trim().isNotEmpty == true) ...[
          const SizedBox(height: 10),
          Text(
            pet!.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '导入自定义桌宠时请选择包含 pet.json 和 spritesheet.webp 的文件夹，文件会复制到项目的 assets/pets 目录。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 12),
        _SettingsToggleRow(
          icon: Icons.power_settings_new_rounded,
          title: '启动研究生活时自动显示桌宠',
          subtitle: '桌宠会在软件打开后提示今天的任务。',
          value: autoStart,
          enabled: !busy,
          onChanged: onAutoStartChanged,
        ),
        const SizedBox(height: 10),
        _SettingsToggleRow(
          icon: Icons.logout_rounded,
          title: '退出研究生活时关闭桌宠',
          subtitle: '关闭后，桌宠只在研究生活窗口内隐藏。',
          value: closeWithApp,
          enabled: !busy,
          onChanged: onCloseWithAppChanged,
        ),
      ],
    );
  }

  void _openPetPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _PetPickerDialog(
          pets: pets,
          activePetId: activePet?.id,
          onSelected: (petId) {
            Navigator.of(dialogContext).pop();
            onPetSelected(petId);
          },
        );
      },
    );
  }
}

class _PetPickerDialog extends StatelessWidget {
  const _PetPickerDialog({
    required this.pets,
    required this.activePetId,
    required this.onSelected,
  });

  final List<PetDefinition> pets;
  final String? activePetId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择桌宠',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pets.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final pet = pets[index];
                    final selected = pet.id == activePetId;
                    return _PetPickerTile(
                      pet: pet,
                      selected: selected,
                      onTap: () => onSelected(pet.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '列表来自项目 assets/pets 目录。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PetPickerTile extends StatelessWidget {
  const _PetPickerTile({
    required this.pet,
    required this.selected,
    required this.onTap,
  });

  final PetDefinition pet;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(tokens.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? tokens.panelSubtle : tokens.panelSurface,
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          border: Border.all(
            color: selected ? tokens.accent : tokens.borderFaint,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _PetFramePreview(pet: pet, width: 72, height: 78),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pet.displayName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        pet.isAsset ? '内置' : '项目',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (pet.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      pet.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? tokens.accent : tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _PetFramePreview extends StatelessWidget {
  const _PetFramePreview({
    required this.pet,
    required this.width,
    required this.height,
  });

  final PetDefinition pet;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final image = pet.isAsset
        ? Image.asset(
            pet.spritesheetPath,
            width: width * 8,
            height: height * 9,
            fit: BoxFit.fill,
            errorBuilder: _buildError,
          )
        : Image.file(
            File(pet.spritesheetPath),
            width: width * 8,
            height: height * 9,
            fit: BoxFit.fill,
            errorBuilder: _buildError,
          );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.borderFaint),
      ),
      clipBehavior: Clip.antiAlias,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: 1 / 8,
          heightFactor: 1 / 9,
          child: image,
        ),
      ),
    );
  }

  Widget _buildError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) {
    return const Center(child: Icon(Icons.broken_image_rounded, size: 22));
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.insetSurface,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Row(
        children: [
          Icon(icon, color: tokens.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({
    required this.title,
    required this.path,
    required this.buttonLabel,
    required this.busy,
    required this.onOpen,
  });

  final String title;
  final String? path;
  final String buttonLabel;
  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final titleText = Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.tonalIcon(
          onPressed: busy ? null : onOpen,
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(buttonLabel),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 620;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stacked) ...[
                titleText,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: actions),
              ] else
                Row(
                  children: [
                    Expanded(child: titleText),
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
              const SizedBox(height: 12),
              SelectableText(
                path ?? '准备中…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlassSettingsPanel extends StatefulWidget {
  const _GlassSettingsPanel({required this.settings, required this.onChanged});

  final GlassSettings settings;
  final ValueChanged<GlassSettings> onChanged;

  @override
  State<_GlassSettingsPanel> createState() => _GlassSettingsPanelState();
}

class _GlassSettingsPanelState extends State<_GlassSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final settings = widget.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassPreviewCard(settings: settings),
        const SizedBox(height: 18),
        _SettingsSliderRow(
          title: '模糊强度',
          value: settings.blurSigma,
          min: GlassSettings.minBlurSigma,
          max: GlassSettings.maxBlurSigma,
          divisions: 30,
          valueLabel: '${settings.blurSigma.round()}',
          onChanged: (value) =>
              widget.onChanged(settings.copyWith(blurSigma: value)),
        ),
        const SizedBox(height: 14),
        _SettingsSliderRow(
          title: '白色不透明度',
          value: settings.opacity,
          min: GlassSettings.minOpacity,
          max: GlassSettings.maxOpacity,
          divisions: 13,
          valueLabel: '${(settings.opacity * 100).round()}%',
          onChanged: (value) =>
              widget.onChanged(settings.copyWith(opacity: value)),
        ),
        const SizedBox(height: 14),
        _SettingsSwitchRow(
          title: '噪点纹理',
          subtitle: '细腻颗粒质感，让毛玻璃更有层次。',
          value: settings.noiseEnabled,
          onChanged: (value) =>
              widget.onChanged(settings.copyWith(noiseEnabled: value)),
        ),
        const SizedBox(height: 14),
        _SettingsSwitchRow(
          title: '顶部高光',
          subtitle: '毛玻璃上沿的受光亮线。',
          value: settings.highlightEnabled,
          onChanged: (value) =>
              widget.onChanged(settings.copyWith(highlightEnabled: value)),
        ),
        const SizedBox(height: 12),
        Text(
          '调整会实时应用到全应用的毛玻璃面板（首页待办提示、校园地图等），并自动保存。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 毛玻璃实时预览：彩色渐变背景上浮着一块真实玻璃。
class _GlassPreviewCard extends StatelessWidget {
  const _GlassPreviewCard({required this.settings});

  final GlassSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C6BD6), Color(0xFF4F8FE8), Color(0xFF4BC4B4)],
        ),
      ),
      child: Stack(
        children: [
          // 背景装饰元素，让模糊效果可见。
          Positioned(
            top: 30,
            left: 36,
            child: _PreviewOrb(color: const Color(0xFFFFD166)),
          ),
          Positioned(
            bottom: 40,
            right: 44,
            child: _PreviewOrb(color: const Color(0xFFFF8FA3), size: 64),
          ),
          Positioned(
            bottom: 18,
            left: 110,
            child: _PreviewOrb(
              color: Colors.white.withValues(alpha: 0.35),
              size: 30,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: FrostedGlass(
                settings: settings,
                width: double.infinity,
                borderRadius: 20,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.blur_on_rounded,
                          size: 18,
                          color: Color(0xFF2F7D4F),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '毛玻璃预览',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '拖动下方滑块实时查看效果',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewOrb extends StatelessWidget {
  const _PreviewOrb({required this.color, this.size = 46});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 18,
            spreadRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _SettingsSliderRow extends StatelessWidget {
  const _SettingsSliderRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    this.divisions,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final ValueChanged<double> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              valueLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                color: tokens.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _PinLockPanel extends StatelessWidget {
  const _PinLockPanel({required this.controller});

  final ResearchLifeController controller;

  Future<void> _openDialog(BuildContext context, _PinDialogMode mode) async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _PinSetupDialog(controller: controller, mode: mode),
    );
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;

    if (!controller.pinLockEnabled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '开启后，无人操作达到设定时间或重新启动软件，都需要输入 PIN 解锁。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _IdleLockTimeoutPicker(controller: controller),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _openDialog(context, _PinDialogMode.setup),
            icon: const Icon(Icons.lock_rounded, size: 18),
            label: const Text('设置锁屏密码'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已启用。PIN 仅在本机存储（哈希），不会上传云端；'
          '请牢记 PIN，忘记后只能清除本地数据恢复。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        _IdleLockTimeoutPicker(controller: controller),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openDialog(context, _PinDialogMode.modify),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('修改密码'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openDialog(context, _PinDialogMode.disable),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('关闭密码'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => controller.lock(),
              icon: const Icon(Icons.lock_rounded, size: 18),
              label: const Text('立即锁定'),
            ),
          ],
        ),
      ],
    );
  }
}

class _IdleLockTimeoutPicker extends StatelessWidget {
  const _IdleLockTimeoutPicker({required this.controller});

  static const _options = <Duration>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 6),
    Duration(hours: 12),
  ];

  final ResearchLifeController controller;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DropdownButtonFormField<Duration>(
        key: const Key('idle-lock-timeout'),
        initialValue: controller.idleLockTimeout,
        decoration: const InputDecoration(
          labelText: '无人操作后自动锁定',
          prefixIcon: Icon(Icons.timer_outlined),
        ),
        items: [
          for (final duration in _options)
            DropdownMenuItem(value: duration, child: Text(_labelFor(duration))),
        ],
        onChanged: (duration) {
          if (duration != null) {
            controller.setIdleLockTimeout(duration);
          }
        },
      ),
    );
  }

  static String _labelFor(Duration duration) {
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} 分钟';
    }
    return '${duration.inHours} 小时';
  }
}

enum _PinDialogMode { setup, modify, disable }

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({required this.controller, required this.mode});

  final ResearchLifeController controller;
  final _PinDialogMode mode;

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final TextEditingController _oldPinController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _saving = false;

  String get _title => switch (widget.mode) {
    _PinDialogMode.setup => '设置锁屏密码',
    _PinDialogMode.modify => '修改锁屏密码',
    _PinDialogMode.disable => '关闭锁屏密码',
  };

  @override
  void dispose() {
    _oldPinController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }
    final pin = _pinController.text.trim();
    if (widget.mode != _PinDialogMode.disable &&
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PIN 需为 6 位数字。')));
      return;
    }
    if (widget.mode != _PinDialogMode.disable &&
        pin != _confirmController.text.trim()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('两次输入的 PIN 不一致。')));
      return;
    }

    setState(() => _saving = true);
    String message;
    switch (widget.mode) {
      case _PinDialogMode.setup:
        message = await widget.controller.enablePinLock(pin);
      case _PinDialogMode.modify:
        message = await widget.controller.enablePinLock(
          pin,
          oldPin: _oldPinController.text.trim(),
        );
      case _PinDialogMode.disable:
        message = await widget.controller.disablePinLock(
          _oldPinController.text.trim(),
        );
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.mode != _PinDialogMode.setup) ...[
              TextField(
                controller: _oldPinController,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '当前 PIN',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (widget.mode != _PinDialogMode.disable) ...[
              TextField(
                controller: _pinController,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '新 PIN（6 位数字）',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmController,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '确认 PIN',
                  counterText: '',
                ),
              ),
            ],
            if (widget.mode == _PinDialogMode.disable)
              Text(
                '关闭后不再需要 PIN，确定请输入当前 PIN。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? '处理中…' : '确定'),
        ),
      ],
    );
  }
}

class _ImageManageRow extends StatelessWidget {
  const _ImageManageRow({
    required this.title,
    required this.caption,
    required this.imagePath,
    required this.busy,
    required this.onReplace,
  });

  final String title;
  final String caption;
  final String? imagePath;
  final bool busy;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panelSubtle,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 720;

          final preview = Container(
            width: stacked ? double.infinity : 220,
            height: 150,
            decoration: BoxDecoration(
              color: tokens.insetSurface,
              borderRadius: BorderRadius.circular(tokens.radiusMedium),
              border: Border.all(color: tokens.borderFaint),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? Image.file(File(imagePath!), fit: BoxFit.cover)
                : Center(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: tokens.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          );

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 12),
              SelectableText(
                imagePath ?? '当前还没有设置图片。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: busy ? null : onReplace,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('更换图片'),
              ),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [preview, const SizedBox(height: 14), content],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              preview,
              const SizedBox(width: 16),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.accentSoft.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CopyableBlock extends StatelessWidget {
  const _CopyableBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.insetSurface,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.borderFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyText(context, text),
                icon: const Icon(Icons.content_copy_rounded),
                label: const Text('复制'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyText(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板。')));
  }
}

/// 虚拟显示器驱动安装状态提示。
class _PrivacyScreenStatusTile extends StatefulWidget {
  @override
  State<_PrivacyScreenStatusTile> createState() =>
      _PrivacyScreenStatusTileState();
}

class _PrivacyScreenStatusTileState extends State<_PrivacyScreenStatusTile> {
  bool? _installed;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final installed = await Future(() => isIddVirtualDisplayInstalled());
    if (mounted) {
      setState(() => _installed = installed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final installed = _installed;
    final (icon, color, text) = switch (installed) {
      null => (Icons.hourglass_top_rounded, tokens.textMuted, '正在检测驱动…'),
      true => (
        Icons.check_circle_rounded,
        const Color(0xFF2E7D32),
        '虚拟显示器驱动已安装（当前可切换）',
      ),
      false => (
        Icons.error_rounded,
        const Color(0xFFE5484D),
        '未检测到虚拟显示器驱动，请先安装 IddSampleDriver',
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}
