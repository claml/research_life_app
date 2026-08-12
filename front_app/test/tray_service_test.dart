import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/tray/tray_service.dart';
import 'package:research_life/state/research_life_controller.dart';

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
}

class _TrayTestController extends Fake implements ResearchLifeController {
  @override
  bool get closeToTray => true;
}
