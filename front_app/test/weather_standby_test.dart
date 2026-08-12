import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/research_life_scope.dart';
import 'package:research_life/core/models/weather_models.dart';
import 'package:research_life/core/theme/app_theme.dart';
import 'package:research_life/features/home/home_page.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  test('each weather condition has a dedicated standby background', () {
    const expected = <WeatherCondition, String>{
      WeatherCondition.clear: 'assets/weather/clear.png',
      WeatherCondition.cloudy: 'assets/weather/cloudscape.png',
      WeatherCondition.fog: 'assets/weather/fog.png',
      WeatherCondition.dust: 'assets/weather/dust.png',
      WeatherCondition.drizzle: 'assets/weather/drizzle.png',
      WeatherCondition.rain: 'assets/weather/rain.png',
      WeatherCondition.snow: 'assets/weather/snow.png',
      WeatherCondition.thunderstorm: 'assets/weather/thunderstorm.png',
      WeatherCondition.unknown: 'assets/weather/unknown.png',
    };

    expect(WeatherCondition.values, hasLength(expected.length));
    for (final entry in expected.entries) {
      expect(weatherBackgroundAssetFor(entry.key), entry.value);
    }
  });

  testWidgets(
    'weather standby keeps its static image when motion is disabled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 760);
      addTearDown(tester.view.reset);
      final controller = _createController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        ResearchLifeScope(
          controller: controller,
          child: MaterialApp(theme: AppTheme.light(), home: const HomePage()),
        ),
      );
      await tester.pump();
      await controller.setWeatherAnimationEnabled(false);
      await tester.pump();

      final assetImages = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .whereType<AssetImage>();
      expect(
        assetImages.map((image) => image.assetName),
        contains('assets/weather/unknown.png'),
      );
      expect(find.text('研LIFE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

ResearchLifeController _createController() {
  return ResearchLifeController(
    importService: const ImportService(),
    analysisService: const AnalysisService(),
    reviewService: const ReviewService(),
    institutionCalendarService: const InstitutionCalendarService(),
    localWorkspaceService: const LocalWorkspaceService(),
  );
}
