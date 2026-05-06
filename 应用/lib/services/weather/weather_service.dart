import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/models/weather_models.dart';

class WeatherServiceException implements Exception {
  const WeatherServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WeatherService {
  const WeatherService({
    HttpClient? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client;

  final HttpClient? _client;
  final Duration timeout;

  Future<WeatherLocation> detectLocalLocation() async {
    final json = await fetchJson(Uri.https('ipapi.co', '/json/'));
    final latitude = _readDouble(json['latitude']);
    final longitude = _readDouble(json['longitude']);
    final city = _readString(json['city']);

    if (latitude == null || longitude == null || city == null) {
      throw const WeatherServiceException('没有拿到本地定位。');
    }

    return WeatherLocation(
      city: city,
      region: _readString(json['region']),
      countryCode: _readString(json['country_code']),
      latitude: latitude,
      longitude: longitude,
      timezone: _readString(json['timezone']),
      source: WeatherLocationSource.automatic,
    );
  }

  Future<List<WeatherLocation>> searchLocations(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return const [];
    }

    final locations = <WeatherLocation>[];
    final seenKeys = <String>{};
    for (final searchQuery in _searchQueryVariants(normalizedQuery)) {
      final json = await fetchJson(
        Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
          'name': searchQuery,
          'count': '12',
          'language': 'zh',
          'format': 'json',
        }),
      );
      final rawResults = json['results'];
      if (rawResults is! List) {
        continue;
      }

      for (final rawResult in rawResults.whereType<Map>()) {
        final location = _locationFromGeocodingResult(
          rawResult.cast<String, Object?>(),
          requestedQuery: normalizedQuery,
        );
        if (location == null) {
          continue;
        }
        final key = _dedupeKey(location);
        if (seenKeys.add(key)) {
          locations.add(location);
        }
      }
    }

    return locations;
  }

  Future<WeatherSnapshot> fetchCurrentWeather(WeatherLocation location) async {
    final json = await fetchJson(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': location.latitude.toStringAsFixed(4),
        'longitude': location.longitude.toStringAsFixed(4),
        'current': [
          'temperature_2m',
          'relative_humidity_2m',
          'apparent_temperature',
          'is_day',
          'precipitation',
          'rain',
          'showers',
          'snowfall',
          'weather_code',
          'cloud_cover',
          'wind_speed_10m',
          'wind_gusts_10m',
        ].join(','),
        'timezone': 'auto',
        'forecast_days': '1',
      }),
    );
    final rawCurrent = json['current'];
    if (rawCurrent is! Map) {
      throw const WeatherServiceException('天气数据格式不完整。');
    }
    final current = rawCurrent.cast<String, Object?>();

    final temperature = _readDouble(current['temperature_2m']);
    final apparentTemperature = _readDouble(current['apparent_temperature']);
    final humidity = _readInt(current['relative_humidity_2m']);
    final windSpeed = _readDouble(current['wind_speed_10m']);
    final weatherCode = _readInt(current['weather_code']);
    if (temperature == null ||
        apparentTemperature == null ||
        humidity == null ||
        windSpeed == null ||
        weatherCode == null) {
      throw const WeatherServiceException('天气数据缺少关键字段。');
    }

    final precipitation = _readDouble(current['precipitation']) ?? 0;
    final isDay = (_readInt(current['is_day']) ?? 1) == 1;

    return WeatherSnapshot(
      location: location.copyWith(timezone: _readString(json['timezone'])),
      temperatureC: temperature,
      apparentTemperatureC: apparentTemperature,
      relativeHumidity: humidity,
      precipitationMm: precipitation,
      windSpeedKmh: windSpeed,
      weatherCode: weatherCode,
      condition: conditionForCode(weatherCode),
      isDay: isDay,
      fetchedAt: DateTime.now(),
    );
  }

  static WeatherCondition conditionForCode(int code) {
    if (code == 0) {
      return WeatherCondition.clear;
    }
    if (code >= 1 && code <= 3) {
      return WeatherCondition.cloudy;
    }
    if (code == 45 || code == 48) {
      return WeatherCondition.fog;
    }
    if ((code >= 51 && code <= 57)) {
      return WeatherCondition.drizzle;
    }
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
      return WeatherCondition.rain;
    }
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return WeatherCondition.snow;
    }
    if (code == 95 || code == 96 || code == 99) {
      return WeatherCondition.thunderstorm;
    }
    return WeatherCondition.unknown;
  }

  Future<Map<String, Object?>> fetchJson(Uri uri) async {
    final ownsClient = _client == null;
    final client = _client ?? HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'ResearchLife/0.1');
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WeatherServiceException('天气服务返回 ${response.statusCode}。');
      }

      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
      throw const WeatherServiceException('天气服务返回了无法识别的数据。');
    } on TimeoutException {
      throw const WeatherServiceException('天气服务连接超时。');
    } on SocketException {
      throw const WeatherServiceException('无法连接天气服务。');
    } on FormatException {
      throw const WeatherServiceException('天气服务返回格式错误。');
    } finally {
      if (ownsClient) {
        client.close(force: true);
      }
    }
  }

  WeatherLocation? _locationFromGeocodingResult(
    Map<String, Object?> json, {
    required String requestedQuery,
  }) {
    final latitude = _readDouble(json['latitude']);
    final longitude = _readDouble(json['longitude']);
    final city = _readString(json['name']);
    if (latitude == null || longitude == null || city == null) {
      return null;
    }
    final alias = _locationAliasForResult(json, requestedQuery);

    return WeatherLocation(
      city: alias?.city ?? city,
      region: _readString(json['admin1']) ?? _readString(json['country']),
      countryCode: _readString(json['country_code']),
      latitude: latitude,
      longitude: longitude,
      timezone: _readString(json['timezone']),
      source: WeatherLocationSource.selected,
    );
  }

  List<String> _searchQueryVariants(String query) {
    final variants = <String>[query];
    final aliases =
        _queryAliases[query] ?? _queryAliases[_stripCitySuffix(query)];
    if (aliases != null) {
      variants.addAll(aliases);
    }
    return variants.toSet().toList();
  }

  String _stripCitySuffix(String query) {
    return query.endsWith('市') ? query.substring(0, query.length - 1) : query;
  }

  String _dedupeKey(WeatherLocation location) {
    return [
      location.city.trim().toLowerCase(),
      location.region?.trim().toLowerCase() ?? '',
      location.countryCode?.trim().toLowerCase() ?? '',
      location.latitude.toStringAsFixed(3),
      location.longitude.toStringAsFixed(3),
    ].join('|');
  }

  _WeatherLocationAlias? _locationAliasForResult(
    Map<String, Object?> json,
    String requestedQuery,
  ) {
    final normalizedQuery = _stripCitySuffix(requestedQuery);
    if (normalizedQuery == '昆山' &&
        _readString(json['name']) == '玉山镇' &&
        _readString(json['country_code']) == 'CN' &&
        _readString(json['admin1']) == '江苏' &&
        _readString(json['admin2']) == '苏州') {
      return const _WeatherLocationAlias(city: '昆山');
    }
    return null;
  }
}

const _queryAliases = <String, List<String>>{
  '昆山': ['Kunshan'],
};

class _WeatherLocationAlias {
  const _WeatherLocationAlias({required this.city});

  final String city;
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String? _readString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}
