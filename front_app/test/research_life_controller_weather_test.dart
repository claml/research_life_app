import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/weather_models.dart';
import 'package:research_life/services/analysis/analysis_service.dart';
import 'package:research_life/services/calendar/institution_calendar_service.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/import/import_service.dart';
import 'package:research_life/services/review/review_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/weather/weather_service.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads weather from stored city before automatic location', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferencesRepository = PreferencesRepository(database);
    await preferencesRepository.saveWeatherApiKey('test-key');
    await preferencesRepository.saveWeatherApiHost('test.qweatherapi.com');
    const storedLocation = WeatherLocation(
      city: '杭州',
      region: '浙江',
      countryCode: 'CN',
      latitude: 30.25,
      longitude: 120.17,
      timezone: 'Asia/Shanghai',
      source: WeatherLocationSource.selected,
    );
    await preferencesRepository.saveWeatherLocation(
      jsonEncode(storedLocation.toJson()),
    );

    final weatherService = _FakeWeatherService();
    final controller = _createController(
      preferencesRepository: preferencesRepository,
      weatherService: weatherService,
    );
    addTearDown(controller.dispose);

    await controller.ensureWeatherLoaded();

    expect(weatherService.detectCount, 0);
    expect(weatherService.fetchCount, 1);
    expect(weatherService.lastFetchedLocation?.city, '杭州');
    expect(controller.weatherSnapshot?.location.city, '杭州');
    expect(controller.weatherSnapshot?.condition, WeatherCondition.rain);
    expect(controller.weatherError, isNull);
  });

  test('reports missing weather api key', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferencesRepository = PreferencesRepository(database);
    final weatherService = _FakeWeatherService();
    final controller = _createController(
      preferencesRepository: preferencesRepository,
      weatherService: weatherService,
    );
    addTearDown(controller.dispose);

    await controller.ensureWeatherLoaded();

    expect(weatherService.fetchCount, 0);
    expect(controller.weatherSnapshot, isNull);
    expect(controller.weatherError, contains('API Key'));
  });

  test('saves and applies weather api settings', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferencesRepository = PreferencesRepository(database);
    final weatherService = _FakeWeatherService();
    final controller = _createController(
      preferencesRepository: preferencesRepository,
      weatherService: weatherService,
    );
    addTearDown(controller.dispose);

    final message = await controller.saveWeatherApiSettings(
      apiKey: 'new-key',
      apiHost: 'new.qweatherapi.com',
    );

    expect(message, contains('天气已刷新'));
    expect(controller.weatherApiKey, 'new-key');
    expect(controller.weatherApiHost, 'new.qweatherapi.com');
    expect(await preferencesRepository.loadWeatherApiKey(), 'new-key');
    expect(
      await preferencesRepository.loadWeatherApiHost(),
      'new.qweatherapi.com',
    );
    expect(weatherService.fetchCount, 1);
  });

  test('selects and persists a searched weather city', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final preferencesRepository = PreferencesRepository(database);
    await preferencesRepository.saveWeatherApiKey('test-key');
    await preferencesRepository.saveWeatherApiHost('test.qweatherapi.com');
    const selectedLocation = WeatherLocation(
      city: '上海',
      region: '上海市',
      countryCode: 'CN',
      latitude: 31.23,
      longitude: 121.47,
      timezone: 'Asia/Shanghai',
      source: WeatherLocationSource.selected,
    );
    final weatherService = _FakeWeatherService(
      searchResults: const [selectedLocation],
    );
    final controller = _createController(
      preferencesRepository: preferencesRepository,
      weatherService: weatherService,
    );
    addTearDown(controller.dispose);

    final results = await controller.searchWeatherLocations('上海');
    final message = await controller.useWeatherLocation(results.single);

    expect(message, '已切换到上海天气。');
    expect(controller.weatherSnapshot?.location.city, '上海');
    expect(weatherService.lastFetchedLocation?.city, '上海');

    final stored = await preferencesRepository.loadWeatherLocation();
    expect(stored, isNotNull);
    expect(
      WeatherLocation.fromJson(
        (jsonDecode(stored!) as Map).cast<String, Object?>(),
      )?.city,
      '上海',
    );
  });
}

ResearchLifeController _createController({
  required PreferencesRepository preferencesRepository,
  required WeatherService weatherService,
}) {
  return ResearchLifeController(
    importService: const ImportService(),
    analysisService: const AnalysisService(),
    reviewService: const ReviewService(),
    institutionCalendarService: const InstitutionCalendarService(),
    localWorkspaceService: const LocalWorkspaceService(),
    preferencesRepository: preferencesRepository,
    weatherService: weatherService,
  );
}

class _FakeWeatherService extends WeatherService {
  _FakeWeatherService({this.searchResults = const []});

  final List<WeatherLocation> searchResults;
  int detectCount = 0;
  int fetchCount = 0;
  WeatherLocation? lastFetchedLocation;

  @override
  Future<WeatherLocation> detectLocalLocation() async {
    detectCount += 1;
    return const WeatherLocation(
      city: '北京',
      region: '北京',
      countryCode: 'CN',
      latitude: 39.9,
      longitude: 116.4,
      timezone: 'Asia/Shanghai',
      source: WeatherLocationSource.automatic,
    );
  }

  @override
  Future<List<WeatherLocation>> searchLocations(String query) async {
    return searchResults;
  }

  @override
  Future<WeatherSnapshot> fetchCurrentWeather(WeatherLocation location) async {
    fetchCount += 1;
    lastFetchedLocation = location;
    return WeatherSnapshot(
      location: location,
      temperatureC: 22.4,
      apparentTemperatureC: 24.1,
      relativeHumidity: 78,
      precipitationMm: 1.2,
      windSpeedKmh: 12.6,
      weatherCode: 61,
      condition: WeatherCondition.rain,
      isDay: true,
      fetchedAt: DateTime(2026, 4, 27, 10, 30),
    );
  }
}
