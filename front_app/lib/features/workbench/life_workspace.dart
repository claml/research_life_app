import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/research_life_scope.dart';
import '../../app/workbench_destination.dart';
import '../../app/workbench_navigation_controller.dart';
import '../../core/theme/app_tokens.dart';
import '../campus_map/campus_map_page.dart';
import 'workbench_workspace_frame.dart';

class LifeWorkspace extends StatelessWidget {
  const LifeWorkspace({required this.navigation, this.pages, super.key});

  final WorkbenchNavigationController navigation;
  final Map<WorkbenchTab, Widget>? pages;

  @override
  Widget build(BuildContext context) {
    return WorkbenchWorkspaceFrame(
      key: const Key('life-workspace'),
      workspace: WorkbenchWorkspace.life,
      navigation: navigation,
      title: '生活',
      description: '校园、桌宠与个性化。',
      pages:
          pages ??
          const {
            WorkbenchTab.lifeCampus: CampusMapPage(),
            WorkbenchTab.lifePet: _PetPage(),
            WorkbenchTab.lifePersonalization: _PersonalizationPage(),
          },
    );
  }
}

class _PetPage extends StatefulWidget {
  const _PetPage();

  @override
  State<_PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<_PetPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ResearchLifeScope.of(context).ensurePetCompanionLoaded());
      }
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    final message = await action();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppLayout.pageHorizontalPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: tokens.panelSurface,
                borderRadius: BorderRadius.circular(tokens.radiusLarge),
                border: Border.all(color: tokens.borderFaint),
                boxShadow: tokens.shadowSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    controller.activePet?.displayName ?? '桌宠',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    controller.petRunning ? '正在运行' : '已停止',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: controller.petRunning
                          ? tokens.success
                          : tokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: controller.petCompanionBusy
                            ? null
                            : () => _run(
                                controller.petRunning
                                    ? controller.stopPetCompanion
                                    : controller.startPetCompanion,
                              ),
                        icon: Icon(
                          controller.petRunning
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(controller.petRunning ? '停止' : '启动'),
                      ),
                      OutlinedButton.icon(
                        onPressed: controller.petCompanionBusy
                            ? null
                            : () => _run(controller.importPetPackage),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('导入桌宠'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('随工作台启动'),
                    value: controller.petAutoStart,
                    onChanged: controller.petCompanionBusy
                        ? null
                        : (value) =>
                              _run(() => controller.setPetAutoStart(value)),
                  ),
                  if (controller.availablePets.length > 1) ...[
                    const SizedBox(height: 10),
                    Text(
                      '选择桌宠',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final pet in controller.availablePets)
                          ChoiceChip(
                            label: Text(pet.displayName),
                            selected: controller.activePet?.id == pet.id,
                            onSelected: (_) =>
                                _run(() => controller.selectPet(pet.id)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalizationPage extends StatelessWidget {
  const _PersonalizationPage();

  @override
  Widget build(BuildContext context) {
    final controller = ResearchLifeScope.read(context);
    final tokens = context.tokens;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppLayout.pageHorizontalPadding),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: tokens.panelSurface,
            borderRadius: BorderRadius.circular(tokens.radiusLarge),
            border: Border.all(color: tokens.borderFaint),
            boxShadow: tokens.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '配色',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final theme in AppColorTheme.values)
                    ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: theme.tokens.accent,
                        radius: 7,
                      ),
                      label: Text(theme.label),
                      selected: controller.colorTheme == theme,
                      onSelected: (_) =>
                          unawaited(controller.setColorTheme(theme)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
