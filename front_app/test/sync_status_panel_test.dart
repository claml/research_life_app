import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/features/settings/widgets/sync_status_panel.dart';
import 'package:research_life/services/sync/sync_models.dart';

void main() {
  testWidgets('shows local mode when cloud sync is disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SyncStatusPanel(
            enabled: false,
            status: CloudSyncStatus.empty(),
            statusBusy: false,
            syncBusy: false,
            syncMessageIsError: false,
          ),
        ),
      ),
    );

    expect(find.text('本地模式'), findsOneWidget);
    expect(find.textContaining('登录后可以同步文献文件'), findsOneWidget);
  });

  testWidgets('renders pending upload and retry counts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusPanel(
            enabled: true,
            status: CloudSyncStatus(
              pendingOutboxCount: 3,
              retryingOutboxCount: 1,
              pendingUploadCount: 2,
              cursorValue: 42,
              lastSyncedAt: DateTime(2026, 5, 17, 9, 30),
            ),
            statusBusy: false,
            syncBusy: false,
            syncMessage: '同步完成',
            syncMessageIsError: false,
          ),
        ),
      ),
    );

    expect(find.text('待上传文件'), findsOneWidget);
    expect(find.text('待推送变更'), findsOneWidget);
    expect(find.text('重试项'), findsOneWidget);
    expect(find.text('上次同步'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
    expect(find.text('同步结果'), findsOneWidget);
  });
}
