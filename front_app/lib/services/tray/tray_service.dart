import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../state/research_life_controller.dart';
import '../utility/privacy_screen.dart';

/// 系统托盘常驻：关闭窗口时最小化到托盘，后台任务继续运行。
class TrayService {
  TrayService({required ResearchLifeController controller})
    : _controller = controller;

  final ResearchLifeController _controller;
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready || !Platform.isWindows) {
      return;
    }

    // 图标解到临时文件（tray_manager 需要文件路径）。
    final iconData = await rootBundle.load('assets/icon/app_icon.ico');
    final iconFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}research_life_tray.ico',
    );
    await iconFile.writeAsBytes(iconData.buffer.asUint8List(), flush: true);

    await trayManager.setIcon(iconFile.path);
    await trayManager.setToolTip('研究生活');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示主窗口'),
          MenuItem(key: 'today_todo', label: '今日待办'),
          MenuItem.separator(),
          MenuItem(key: 'privacy_on', label: '开启隐私屏模式（仅虚拟屏）'),
          MenuItem(key: 'privacy_off', label: '恢复内置屏幕'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: '退出'),
        ],
      ),
    );
    trayManager.addListener(_TrayEventListener(this));

    // 拦截窗口关闭：按设置决定最小化到托盘或真正退出。
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(_WindowCloseListener(this));

    _ready = true;
  }

  Future<void> showMainWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
    _controller.notifyUserActivity();
  }

  Future<void> quit() async {
    await windowManager.destroy();
  }

  bool get closeToTray => _controller.closeToTray;
}

class _TrayEventListener extends TrayListener {
  _TrayEventListener(this._service);

  final TrayService _service;

  @override
  void onTrayIconMouseDown() {
    // 单击托盘图标：显示主窗口。
    _service.showMainWindow();
  }

  @override
  void onTrayIconMouseUp() {
    _service.showMainWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _service.showMainWindow();
      case 'today_todo':
        _service.showMainWindow();
        _service._controller.requestTodayTodoDialog();
      case 'privacy_on':
        // 隐私屏模式：先匹配分辨率，再仅虚拟显示器输出。
        enterPrivacyScreen();
      case 'privacy_off':
        // 恢复内置屏幕。
        setPrivacyScreen(enable: false);
      case 'quit':
        _service.quit();
    }
  }
}

class _WindowCloseListener extends WindowListener {
  _WindowCloseListener(this._service);

  final TrayService _service;

  @override
  void onWindowClose() {
    if (_service.closeToTray) {
      // 最小化到托盘，后台继续运行。
      windowManager.hide();
    } else {
      // 设置里关闭了托盘模式：真正退出。
      windowManager.destroy();
    }
  }
}
