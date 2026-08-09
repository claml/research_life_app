import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/weather_models.dart';
import 'package:research_life/services/weather/weather_service.dart';

void main() {
  group('WeatherService', () {
    test('maps weather text to visual conditions', () {
      expect(WeatherService.conditionForText('晴'), WeatherCondition.clear);
      expect(WeatherService.conditionForText('多云'), WeatherCondition.cloudy);
      expect(WeatherService.conditionForText('阴'), WeatherCondition.cloudy);
      expect(WeatherService.conditionForText('雾'), WeatherCondition.fog);
      expect(WeatherService.conditionForText('霾'), WeatherCondition.fog);
      expect(
        WeatherService.conditionForText('沙尘暴'),
        WeatherCondition.dust,
      );
      expect(
        WeatherService.conditionForText('扬沙'),
        WeatherCondition.dust,
      );
      expect(
        WeatherService.conditionForText('浮尘'),
        WeatherCondition.dust,
      );
      expect(
        WeatherService.conditionForText('毛毛雨'),
        WeatherCondition.drizzle,
      );
      expect(
        WeatherService.conditionForText('小雨'),
        WeatherCondition.drizzle,
      );
      expect(
        WeatherService.conditionForText('中雨'),
        WeatherCondition.rain,
      );
      expect(
        WeatherService.conditionForText('雷阵雨'),
        WeatherCondition.thunderstorm,
      );
      expect(
        WeatherService.conditionForText('小雪'),
        WeatherCondition.snow,
      );
      expect(WeatherService.conditionForText('热'), WeatherCondition.clear);
      expect(WeatherService.conditionForText('冷'), WeatherCondition.cloudy);
      expect(
        WeatherService.conditionForText('未知'),
        WeatherCondition.unknown,
      );
      expect(WeatherService.conditionForText(''), WeatherCondition.unknown);
    });

    test('normalizes api host input', () {
      expect(WeatherService.normalizeHost(' abc.qweatherapi.com/ '), 'abc.qweatherapi.com');
      expect(
        WeatherService.normalizeHost('https://abc.qweatherapi.com'),
        'abc.qweatherapi.com',
      );
      expect(WeatherService.normalizeHost(''), '');
    });

    test('parses QWeather city lookup into locations without aliases', () async {
      final service = _FakeWeatherService(responses: [
        _FakeResponse(
          path: '/geo/v2/city/lookup',
          json: {
            'code': '200',
            'location': [
              {
                'name': '昆山',
                'id': '101190404',
                'lat': '31.38193',
                'lon': '120.95814',
                'adm1': '江苏省',
                'adm2': '苏州市',
                'country': '中国',
                'tz': 'Asia/Shanghai',
                'type': 'city',
                'rank': '23',
              },
            ],
          },
        ),
      ]);

      final results = await service.searchLocations('昆山');

      expect(results, hasLength(1));
      final location = results.single;
      expect(location.city, '昆山');
      expect(location.region, '江苏');
      expect(location.countryCode, 'CN');
      expect(location.latitude, closeTo(31.38193, 0.0001));
      expect(location.longitude, closeTo(120.95814, 0.0001));
      expect(location.timezone, 'Asia/Shanghai');
      expect(location.source, WeatherLocationSource.selected);
    });

    test('parses QWeather current weather snapshot', () async {
      final service = _FakeWeatherService(responses: [
        _FakeResponse(
          path: '/v7/weather/now',
          json: {
            'code': '200',
            'now': {
              'obsTime': '2026-08-01T12:00+08:00',
              'temp': '28',
              'feelsLike': '32',
              'icon': '101',
              'text': '多云',
              'windDir': '东南风',
              'windScale': '2',
              'windSpeed': '6',
              'humidity': '89',
              'precip': '4.0',
              'pressure': '1005',
              'vis': '26',
              'cloud': '40',
            },
          },
        ),
      ]);
      const location = WeatherLocation(
        city: '昆山',
        region: '江苏',
        countryCode: 'CN',
        latitude: 31.38193,
        longitude: 120.95814,
        timezone: 'Asia/Shanghai',
        source: WeatherLocationSource.selected,
      );

      final snapshot = await service.fetchCurrentWeather(location);

      expect(snapshot.temperatureC, 28);
      expect(snapshot.apparentTemperatureC, 32);
      expect(snapshot.relativeHumidity, 89);
      expect(snapshot.windSpeedKmh, 6);
      expect(snapshot.precipitationMm, 4.0);
      expect(snapshot.weatherCode, 101);
      expect(snapshot.condition, WeatherCondition.cloudy);
      expect(snapshot.isDay, isTrue);
      expect(snapshot.location.city, '昆山');
    });

    test('marks night icons as not daytime', () async {
      final service = _FakeWeatherService(responses: [
        _FakeResponse(
          path: '/v7/weather/now',
          json: {
            'code': '200',
            'now': {
              'temp': '24',
              'feelsLike': '26',
              'icon': '150',
              'text': '晴',
              'windSpeed': '3',
              'humidity': '72',
              'precip': '0.0',
            },
          },
        ),
      ]);
      const location = WeatherLocation(
        city: '杭州',
        region: '浙江',
        countryCode: 'CN',
        latitude: 30.25,
        longitude: 120.17,
        source: WeatherLocationSource.selected,
      );

      final snapshot = await service.fetchCurrentWeather(location);

      expect(snapshot.isDay, isFalse);
      expect(snapshot.condition, WeatherCondition.clear);
    });

    test('reports QWeather error codes', () async {
      final service = _FakeWeatherService(responses: [
        _FakeResponse(path: '/v7/weather/now', json: {'code': '401'}),
      ]);
      const location = WeatherLocation(
        city: '杭州',
        region: '浙江',
        countryCode: 'CN',
        latitude: 30.25,
        longitude: 120.17,
        source: WeatherLocationSource.selected,
      );

      expect(
        service.fetchCurrentWeather(location),
        throwsA(isA<WeatherServiceException>()),
      );
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
}

class _FakeResponse {
  const _FakeResponse({required this.path, required this.json});

  final String path;
  final Map<String, Object?> json;
}

class _FakeWeatherService extends WeatherService {
  _FakeWeatherService({required this.responses});

  final List<_FakeResponse> responses;

  @override
  Future<Map<String, Object?>> fetchJson(Uri uri) async {
    for (final response in responses) {
      if (uri.path.startsWith(response.path)) {
        return response.json;
      }
    }
    return const {};
  }
}
