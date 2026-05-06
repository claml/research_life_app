import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/research_life_scope.dart';
import '../../core/models/app_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../state/research_life_controller.dart';
import '../../shared/widgets/section_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _calendarInputController;
  late final TextEditingController _ollamaBaseUrlController;
  late final TextEditingController _ollamaModelController;
  late final TextEditingController _ollamaTimeoutController;
  String? _syncedCalendarEditSessionId;
  String? _syncedLocalLlmSettingsSignature;

  @override
  void initState() {
    super.initState();
    _calendarInputController = TextEditingController();
    _ollamaBaseUrlController = TextEditingController();
    _ollamaModelController = TextEditingController();
    _ollamaTimeoutController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ResearchLifeScope.of(context);
      unawaited(controller.ensureHomeGalleryReady());
      unawaited(controller.ensureVPetCompanionLoaded());
      unawaited(controller.ensureLocalLlmAnalysisSettingsLoaded());
    });
  }

  @override
  void dispose() {
    _calendarInputController.dispose();
    _ollamaBaseUrlController.dispose();
    _ollamaModelController.dispose();
    _ollamaTimeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.of(context);
    final tokens = context.tokens;

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
        final localLlmSettings = controller.localLlmAnalysisSettings;
        final localLlmSettingsSignature = _localLlmSettingsSignature(
          localLlmSettings,
        );
        if (_syncedLocalLlmSettingsSignature != localLlmSettingsSignature) {
          _syncedLocalLlmSettingsSignature = localLlmSettingsSignature;
          _ollamaBaseUrlController.text = localLlmSettings.ollamaBaseUrl;
          _ollamaModelController.text = localLlmSettings.ollamaModel;
          _ollamaTimeoutController.text =
              '${localLlmSettings.ollamaTimeoutSeconds}';
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '管理本地文件、主页图片，以及学校/机构年度安排的导入格式。',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 24),
              SectionCard(
                title: '颜色主题',
                subtitle: '选择软件整体配色，设置会自动保存。',
                child: _ColorThemeGrid(
                  selectedTheme: controller.colorTheme,
                  onSelected: (theme) => _runAsyncAction(
                    context,
                    () => controller.setColorTheme(theme),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '本地 LLM 周分析',
                subtitle: '通过本机 Ollama 运行结构化周分析，默认模型 qwen3:8b。',
                child: _LocalLlmAnalysisPanel(
                  settings: localLlmSettings,
                  baseUrlController: _ollamaBaseUrlController,
                  modelController: _ollamaModelController,
                  timeoutController: _ollamaTimeoutController,
                  settingsBusy: controller.localLlmAnalysisSettingsBusy,
                  testBusy: controller.ollamaConnectionTestBusy,
                  onEnableChanged: (value) => _runAsyncAction(
                    context,
                    () => controller.saveLocalLlmAnalysisSettings(
                      _localLlmSettingsFromInputs(
                        localLlmSettings,
                      ).copyWith(enableLocalLlmAnalysis: value),
                    ),
                  ),
                  onFallbackChanged: (value) => _runAsyncAction(
                    context,
                    () => controller.saveLocalLlmAnalysisSettings(
                      _localLlmSettingsFromInputs(
                        localLlmSettings,
                      ).copyWith(fallbackToRules: value),
                    ),
                  ),
                  onStrictJsonSchemaChanged: (value) => _runAsyncAction(
                    context,
                    () => controller.saveLocalLlmAnalysisSettings(
                      _localLlmSettingsFromInputs(
                        localLlmSettings,
                      ).copyWith(strictJsonSchema: value),
                    ),
                  ),
                  onSave: () => _runAsyncAction(
                    context,
                    () => controller.saveLocalLlmAnalysisSettings(
                      _localLlmSettingsFromInputs(localLlmSettings),
                    ),
                  ),
                  onTestConnection: () => _runAsyncAction(context, () async {
                    await controller.saveLocalLlmAnalysisSettings(
                      _localLlmSettingsFromInputs(localLlmSettings),
                    );
                    return controller.testOllamaConnection();
                  }),
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: 'VPet 桌宠',
                subtitle: '第一阶段以独立伴随进程运行 VPet，不再使用软件内置桌宠浮层。',
                child: _VPetCompanionPanel(
                  executablePath: controller.vPetExecutablePath,
                  autoStart: controller.vPetAutoStart,
                  closeWithApp: controller.vPetCloseWithApp,
                  running: controller.vPetRunning,
                  processId: controller.vPetProcessId,
                  busy: controller.vPetCompanionBusy,
                  onChooseExecutable: () =>
                      _runAsyncAction(context, controller.chooseVPetExecutable),
                  onStart: () =>
                      _runAsyncAction(context, controller.startVPetCompanion),
                  onStop: () =>
                      _runAsyncAction(context, controller.stopVPetCompanion),
                  onTestMessage: () =>
                      _runAsyncAction(context, controller.sendVPetTestMessage),
                  onAutoStartChanged: (value) => _runAsyncAction(
                    context,
                    () => controller.setVPetAutoStart(value),
                  ),
                  onCloseWithAppChanged: (value) => _runAsyncAction(
                    context,
                    () => controller.setVPetCloseWithApp(value),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '文件位置',
                child: Column(
                  children: [
                    _PathRow(
                      title: '应用数据目录',
                      path: controller.storageDirectoryPath,
                      buttonLabel: '打开应用数据目录',
                      busy: controller.galleryBusy,
                      onOpen: () => _runAsyncAction(
                        context,
                        controller.openStorageFolder,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PathRow(
                      title: 'SQLite 数据库文件',
                      path: controller.databaseFilePath,
                      buttonLabel: '打开数据库目录',
                      secondaryButtonLabel: '备份数据库',
                      secondaryIcon: Icons.backup_rounded,
                      busy: controller.galleryBusy,
                      onOpen: () => _runAsyncAction(
                        context,
                        controller.openDatabaseFolder,
                      ),
                      onSecondary: () =>
                          _runAsyncAction(context, controller.backupDatabase),
                    ),
                    const SizedBox(height: 14),
                    _PathRow(
                      title: '主页图片文件夹',
                      path: controller.homeImageFolderPath,
                      buttonLabel: '打开图片文件夹',
                      busy: controller.galleryBusy,
                      onOpen: () => _runAsyncAction(
                        context,
                        controller.openHomeImageFolder,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '主页图片',
                subtitle: '管理主页右侧两张展示图片。',
                trailing: Wrap(
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
                child: Column(
                  children: [
                    _ImageManageRow(
                      title: '研究墙',
                      caption: '主页右侧上方图片位。',
                      imagePath: controller.researchWallImagePath,
                      busy: controller.galleryBusy,
                      onReplace: () => _runAsyncAction(
                        context,
                        () => controller.replaceHomeImage(
                          HomeImageSlot.researchWall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ImageManageRow(
                      title: '生活墙',
                      caption: '主页右侧下方图片位。',
                      imagePath: controller.lifeWallImagePath,
                      busy: controller.galleryBusy,
                      onReplace: () => _runAsyncAction(
                        context,
                        () =>
                            controller.replaceHomeImage(HomeImageSlot.lifeWall),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionCard(
                title: '校历导入',
                subtitle: isEditingCalendar
                    ? '正在编辑${controller.editingInstitutionCalendarTitle == null ? '' : ' · ${controller.editingInstitutionCalendarTitle}'}，保存后会覆盖这条历史记录。'
                    : importedCount == 0
                    ? '把外部识别后的校历文本贴到下方，导入后会直接标注到主页日历。'
                    : '当前已导入 $importedCount 条校历事件${controller.institutionCalendarTitle == null ? '' : ' · ${controller.institutionCalendarTitle}'}',
                trailing: Wrap(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoBanner(
                      title: '支持的文本格式',
                      body:
                          '每行一个事件，固定写成“开始日期 | 结束日期 | 事件标题 | 分类 | 类型”。分类只支持 study/work/life/health/social/other，类型只支持 plan/record。',
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
            ],
          ),
        );
      },
    );
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

  LocalLlmAnalysisSettings _localLlmSettingsFromInputs(
    LocalLlmAnalysisSettings current,
  ) {
    return current.copyWith(
      ollamaBaseUrl: _ollamaBaseUrlController.text,
      ollamaModel: _ollamaModelController.text,
      ollamaTimeoutSeconds:
          int.tryParse(_ollamaTimeoutController.text) ??
          LocalLlmAnalysisSettings.defaultOllamaTimeoutSeconds,
    );
  }

  String _localLlmSettingsSignature(LocalLlmAnalysisSettings settings) {
    return [
      settings.enableLocalLlmAnalysis,
      settings.ollamaBaseUrl,
      settings.ollamaModel,
      settings.ollamaTimeoutSeconds,
      settings.fallbackToRules,
      settings.strictJsonSchema,
    ].join('|');
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
      width: 152,
      height: 82,
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
                Row(
                  children: [
                    _ThemeSwatch(color: optionTokens.accent),
                    const SizedBox(width: 6),
                    _ThemeSwatch(color: optionTokens.panelSubtle),
                    const SizedBox(width: 6),
                    _ThemeSwatch(color: optionTokens.sidebarSurface),
                    const Spacer(),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: tokens.accent,
                      ),
                  ],
                ),
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

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: context.tokens.borderFaint),
      ),
    );
  }
}

class _LocalLlmAnalysisPanel extends StatelessWidget {
  const _LocalLlmAnalysisPanel({
    required this.settings,
    required this.baseUrlController,
    required this.modelController,
    required this.timeoutController,
    required this.settingsBusy,
    required this.testBusy,
    required this.onEnableChanged,
    required this.onFallbackChanged,
    required this.onStrictJsonSchemaChanged,
    required this.onSave,
    required this.onTestConnection,
  });

  final LocalLlmAnalysisSettings settings;
  final TextEditingController baseUrlController;
  final TextEditingController modelController;
  final TextEditingController timeoutController;
  final bool settingsBusy;
  final bool testBusy;
  final ValueChanged<bool> onEnableChanged;
  final ValueChanged<bool> onFallbackChanged;
  final ValueChanged<bool> onStrictJsonSchemaChanged;
  final VoidCallback onSave;
  final VoidCallback onTestConnection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final busy = settingsBusy || testBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsToggleRow(
          icon: Icons.psychology_alt_rounded,
          title: '启用本地 LLM 周分析',
          subtitle: '开启后允许周分析使用本机 Ollama 配置。',
          value: settings.enableLocalLlmAnalysis,
          enabled: !busy,
          onChanged: onEnableChanged,
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 720;
            final addressField = TextField(
              controller: baseUrlController,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Ollama 地址',
                hintText: LocalLlmAnalysisSettings.defaultOllamaBaseUrl,
              ),
            );
            final modelField = TextField(
              controller: modelController,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: '模型名',
                hintText: LocalLlmAnalysisSettings.defaultOllamaModel,
              ),
            );
            final timeoutField = TextField(
              controller: timeoutController,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '超时时间（秒）',
                hintText:
                    '${LocalLlmAnalysisSettings.defaultOllamaTimeoutSeconds}',
              ),
            );

            if (stacked) {
              return Column(
                children: [
                  addressField,
                  const SizedBox(height: 12),
                  modelField,
                  const SizedBox(height: 12),
                  timeoutField,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: addressField),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: modelField),
                const SizedBox(width: 12),
                SizedBox(width: 150, child: timeoutField),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _SettingsToggleRow(
          icon: Icons.safety_check_rounded,
          title: '失败时使用规则兜底',
          subtitle: 'Ollama 不可用或输出无效时保留现有规则分析。',
          value: settings.fallbackToRules,
          enabled: !busy,
          onChanged: onFallbackChanged,
        ),
        const SizedBox(height: 10),
        _SettingsToggleRow(
          icon: Icons.data_object_rounded,
          title: '严格 JSON Schema',
          subtitle: '请求 Ollama 按结构化 JSON schema 输出。',
          value: settings.strictJsonSchema,
          enabled: !busy,
          onChanged: onStrictJsonSchemaChanged,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : onSave,
              icon: const Icon(Icons.save_rounded),
              label: const Text('保存设置'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : onTestConnection,
              icon: testBusy
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.network_check_rounded),
              label: const Text('测试连接'),
            ),
          ],
        ),
      ],
    );
  }
}

class _VPetCompanionPanel extends StatelessWidget {
  const _VPetCompanionPanel({
    required this.executablePath,
    required this.autoStart,
    required this.closeWithApp,
    required this.running,
    required this.processId,
    required this.busy,
    required this.onChooseExecutable,
    required this.onStart,
    required this.onStop,
    required this.onTestMessage,
    required this.onAutoStartChanged,
    required this.onCloseWithAppChanged,
  });

  final String? executablePath;
  final bool autoStart;
  final bool closeWithApp;
  final bool running;
  final int? processId;
  final bool busy;
  final VoidCallback onChooseExecutable;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onTestMessage;
  final ValueChanged<bool> onAutoStartChanged;
  final ValueChanged<bool> onCloseWithAppChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasExecutable =
        executablePath != null && executablePath!.trim().isNotEmpty;

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
                    running
                        ? '运行中${processId == null ? '' : ' · PID $processId'}'
                        : '未运行',
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
                    onPressed: busy ? null : onChooseExecutable,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('选择程序'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy || !hasExecutable || running
                        ? null
                        : onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('启动 VPet'),
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
        SelectableText(
          hasExecutable
              ? executablePath!
              : '尚未选择 VPet-Simulator.Windows.exe。请先构建 VPet-Simulator.Windows 的 x64 Release，再选择生成的 exe。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: hasExecutable ? tokens.textSecondary : tokens.textMuted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        _SettingsToggleRow(
          icon: Icons.power_settings_new_rounded,
          title: '启动研究生活时自动启动 VPet',
          subtitle: '需要先选择 VPet-Simulator.Windows.exe。',
          value: autoStart,
          enabled: !busy,
          onChanged: onAutoStartChanged,
        ),
        const SizedBox(height: 10),
        _SettingsToggleRow(
          icon: Icons.logout_rounded,
          title: '退出研究生活时关闭由它启动的 VPet',
          subtitle: '如果你希望桌宠继续留在桌面，请关闭这个选项。',
          value: closeWithApp,
          enabled: !busy,
          onChanged: onCloseWithAppChanged,
        ),
      ],
    );
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
    this.secondaryButtonLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  final String title;
  final String? path;
  final String buttonLabel;
  final String? secondaryButtonLabel;
  final IconData? secondaryIcon;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback? onSecondary;

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
        if (secondaryButtonLabel != null && onSecondary != null)
          OutlinedButton.icon(
            onPressed: busy ? null : onSecondary,
            icon: Icon(secondaryIcon ?? Icons.copy_rounded),
            label: Text(secondaryButtonLabel!),
          ),
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
