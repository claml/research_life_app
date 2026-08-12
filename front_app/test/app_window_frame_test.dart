import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/app_window_frame.dart';
import 'package:research_life/core/theme/app_theme.dart';

void main() {
  testWidgets('desktop frame supplies branded drag area and window controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AppWindowFrame(
          forceEnabled: true,
          child: ColoredBox(color: Colors.white),
        ),
      ),
    );

    expect(find.byKey(const Key('app-window-titlebar')), findsOneWidget);
    expect(find.text('研LIFE'), findsOneWidget);
    expect(find.byTooltip('最小化'), findsOneWidget);
    expect(find.byTooltip('最大化或还原'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });
}
