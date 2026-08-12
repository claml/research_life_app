import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../state/research_life_controller.dart';
import '../utility/privacy_screen.dart';

/// 系统托盘常驻：关闭窗口时最小化到托盘，后台任务继续运行。
class TrayService extends TrayListener {
  TrayService({
    required ResearchLifeController controller,
    required Future<void> Function() requestExit,
    Future<void> Function()? showContextMenu,
    Future<bool> Function()? isWindowMinimized,
    Future<void> Function()? showWindow,
    Future<void> Function()? restoreWindow,
    Future<void> Function()? focusWindow,
  }) : _controller = controller,
       _requestExit = requestExit,
       _showContextMenu = showContextMenu ?? trayManager.popUpContextMenu,
       _isWindowMinimized = isWindowMinimized ?? _defaultIsWindowMinimized,
       _showWindow = showWindow ?? _defaultShowWindow,
       _restoreWindow = restoreWindow ?? _defaultRestoreWindow,
       _focusWindow = focusWindow ?? _defaultFocusWindow;

  final ResearchLifeController _controller;
  final Future<void> Function() _requestExit;
  final Future<void> Function() _showContextMenu;
  final Future<bool> Function() _isWindowMinimized;
  final Future<void> Function() _showWindow;
  final Future<void> Function() _restoreWindow;
  final Future<void> Function() _focusWindow;
  Future<void>? _exitFuture;
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
    trayManager.addListener(this);

    await windowManager.ensureInitialized();

    _ready = true;
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    _ready = false;
  }

  Future<void> showMainWindow() async {
    final wasMinimized = await _isWindowMinimized();
    await _showWindow();
    if (wasMinimized) {
      await _restoreWindow();
    }
    await _focusWindow();
    _controller.notifyUserActivity();
  }

  Future<void> quit() {
    return _exitFuture ??= _requestExit();
  }

  Future<void> showContextMenu() => _showContextMenu();

  Future<void> handleWindowClose() async {
    if (await handleWindowCloseRequest()) {
      return;
    }
    await quit();
  }

  /// Returns true when the request was handled by hiding the window.
  Future<bool> handleWindowCloseRequest() async {
    if (!closeToTray) {
      return false;
    }
    await windowManager.hide();
    return true;
  }

  bool get closeToTray => _controller.closeToTray;

  @override
  void onTrayIconMouseDown() {
    // 单击托盘图标：显示主窗口。
    unawaited(showMainWindow());
  }

  @override
  void onTrayIconMouseUp() {
    unawaited(showMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(showContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(showMainWindow());
      case 'today_todo':
        unawaited(_showTodayTodo());
      case 'privacy_on':
        // 隐私屏模式：先匹配分辨率，再仅虚拟显示器输出。
        enterPrivacyScreen();
      case 'privacy_off':
        // 恢复内置屏幕。
        setPrivacyScreen(enable: false);
      case 'quit':
        unawaited(quit());
    }
  }

  Future<void> _showTodayTodo() async {
    await showMainWindow();
    _controller.requestTodayTodoDialog();
  }
}

Future<bool> _defaultIsWindowMinimized() => windowManager.isMinimized();

Future<void> _defaultShowWindow() => windowManager.show();

Future<void> _defaultRestoreWindow() => windowManager.restore();

Future<void> _defaultFocusWindow() => windowManager.focus();
