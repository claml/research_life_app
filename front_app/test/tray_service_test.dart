import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/tray/tray_service.dart';
import 'package:research_life/state/research_life_controller.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  test('right click opens the tray context menu', () async {
    var contextMenuRequests = 0;
    final tray = TrayService(
      controller: _TrayTestController(),
      requestExit: () async {},
      showContextMenu: () async => contextMenuRequests += 1,
    );

    tray.onTrayIconRightMouseDown();
    await Future<void>.delayed(Duration.zero);

    expect(contextMenuRequests, 1);
  });

  test('tray exit delegates to graceful shutdown exactly once', () async {
    var exitRequests = 0;
    final tray = TrayService(
      controller: _TrayTestController(),
      requestExit: () async => exitRequests += 1,
      showContextMenu: () async {},
    );

    await Future.wait([tray.quit(), tray.quit()]);

    expect(exitRequests, 1);
  });

  test('showing a hidden fullscreen window does not restore it', () async {
    final events = <String>[];
    final tray = TrayService(
      controller: _TrayTestController(),
      requestExit: () async {},
      showContextMenu: () async {},
      isWindowMinimized: () async => false,
      showWindow: () async => events.add('show'),
      restoreWindow: () async => events.add('restore'),
      focusWindow: () async => events.add('focus'),
    );

    await tray.showMainWindow();

    expect(events, ['show', 'focus']);
  });

  test('showing a minimized window restores it before focus', () async {
    final events = <String>[];
    final tray = TrayService(
      controller: _TrayTestController(),
      requestExit: () async {},
      showContextMenu: () async {},
      isWindowMinimized: () async => true,
      showWindow: () async => events.add('show'),
      restoreWindow: () async => events.add('restore'),
      focusWindow: () async => events.add('focus'),
    );

    await tray.showMainWindow();

    expect(events, ['show', 'restore', 'focus']);
  });

  test(
    'today todo waits for the window before requesting its dialog',
    () async {
      final events = <String>[];
      final controller = _TrayTestController(events: events);
      final tray = TrayService(
        controller: controller,
        requestExit: () async {},
        showContextMenu: () async {},
        isWindowMinimized: () async => false,
        showWindow: () async => events.add('show'),
        restoreWindow: () async => events.add('restore'),
        focusWindow: () async => events.add('focus'),
      );

      tray.onTrayMenuItemClick(_MenuItemStub('today_todo'));
      await Future<void>.delayed(Duration.zero);

      expect(events, ['show', 'focus', 'todo']);
    },
  );
}

class _TrayTestController extends Fake implements ResearchLifeController {
  _TrayTestController({this.events});

  final List<String>? events;

  @override
  bool get closeToTray => true;

  @override
  void notifyUserActivity() {}

  @override
  void requestTodayTodoDialog() => events?.add('todo');
}

class _MenuItemStub extends Fake implements MenuItem {
  _MenuItemStub(this._key);

  final String _key;

  @override
  String? get key => _key;
}
