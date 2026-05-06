import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/weather_models.dart';
import 'package:research_life/services/weather/weather_service.dart';

void main() {
  group('WeatherService', () {
    test('maps weather codes to visual conditions', () {
      expect(WeatherService.conditionForCode(0), WeatherCondition.clear);
      expect(WeatherService.conditionForCode(2), WeatherCondition.cloudy);
      expect(WeatherService.conditionForCode(45), WeatherCondition.fog);
      expect(WeatherService.conditionForCode(51), WeatherCondition.drizzle);
      expect(WeatherService.conditionForCode(61), WeatherCondition.rain);
      expect(WeatherService.conditionForCode(71), WeatherCondition.snow);
      expect(
        WeatherService.conditionForCode(95),
        WeatherCondition.thunderstorm,
      );
      expect(WeatherService.conditionForCode(999), WeatherCondition.unknown);
    });
  });

  group('WeatherLocation', () {
    test('round trips stored location json', () {
      const location = WeatherLocation(
        city: '杭州',
        region: '浙江',
        countryCode: 'CN',
        latitude: 30.25,
        longitude: 120.17,
        timezone: 'Asia/Shanghai',
        source: WeatherLocationSource.selected,
      );

      final restored = WeatherLocation.fromJson(location.toJson());

      expect(restored, isNotNull);
      expect(restored!.city, '杭州');
      expect(restored.region, '浙江');
      expect(restored.countryCode, 'CN');
      expect(restored.latitude, 30.25);
      expect(restored.longitude, 120.17);
      expect(restored.timezone, 'Asia/Shanghai');
      expect(restored.source, WeatherLocationSource.selected);
    });
  });

  group('WeatherService city aliases', () {
    test('normalizes Open-Meteo Kunshan fallback result', () async {
      final service = _FakeWeatherService(
        responses: {
          '昆山': {'generationtime_ms': 0.1},
          'Kunshan': {
            'results': [
              {
                'id': 1785623,
                'name': '玉山镇',
                'latitude': 31.37762,
                'longitude': 120.95431,
                'country_code': 'CN',
                'timezone': 'Asia/Shanghai',
                'country': '中国',
                'admin1': '江苏',
                'admin2': '苏州',
              },
            ],
          },
        },
      );

      final results = await service.searchLocations('昆山');

      expect(results, hasLength(1));
      expect(results.single.city, '昆山');
      expect(results.single.region, '江苏');
      expect(results.single.countryCode, 'CN');
      expect(results.single.latitude, 31.37762);
      expect(results.single.longitude, 120.95431);
    });
  });
}

class _FakeWeatherService extends WeatherService {
  const _FakeWeatherService({required this.responses});

  final Map<String, Map<String, Object?>> responses;

  @override
  Future<Map<String, Object?>> fetchJson(Uri uri) async {
    return responses[uri.queryParameters['name']] ?? const {};
  }
}
