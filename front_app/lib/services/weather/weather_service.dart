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
  WeatherService({
    HttpClient? client,
    String apiKey = '',
    String apiHost = '',
    this.timeout = const Duration(seconds: 8),
  }) : _client = client,
       _apiKey = apiKey.trim(),
       _apiHost = normalizeHost(apiHost);

  final HttpClient? _client;
  final Duration timeout;

  String _apiKey;
  String _apiHost;

  String get apiKey => _apiKey;
  String get apiHost => _apiHost;

  void setCredentials({required String apiKey, required String apiHost}) {
    _apiKey = apiKey.trim();
    _apiHost = normalizeHost(apiHost);
  }

  static String normalizeHost(String host) {
    var value = host.trim();
    if (value.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      value = uri.host;
    } else {
      value = value.replaceFirst(RegExp(r'^[a-z]+://'), '');
    }
    return value.replaceAll(RegExp(r'/+$'), '').toLowerCase();
  }

  Future<WeatherLocation> detectLocalLocation() async {
    final body = await _fetchRawText(Uri.https('myip.ipip.net', '/'));
    final query = _publicLocationQuery(body);
    if (query == null) {
      throw const WeatherServiceException('没有拿到本地定位。');
    }

    final results = await searchLocations(query);
    for (final result in results) {
      if (result.countryCode == 'CN') {
        return result.copyWith(source: WeatherLocationSource.automatic);
      }
    }
    if (results.isNotEmpty) {
      return results.first.copyWith(source: WeatherLocationSource.automatic);
    }
    throw const WeatherServiceException('没有拿到本地定位。');
  }

  Future<List<WeatherLocation>> searchLocations(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      return const [];
    }

    return _lookupLocations(normalizedQuery);
  }

  Future<List<WeatherLocation>> _lookupLocations(String query) async {
    final json = await fetchJson(
      Uri.https(_apiHost, '/geo/v2/city/lookup', {
        'location': query,
        'range': 'cn',
        'number': '12',
        'lang': 'zh',
      }),
    );
    _throwIfError(json);

    final rawResults = json['location'];
    if (rawResults is! List) {
      return const [];
    }

    final locations = <WeatherLocation>[];
    for (final rawResult in rawResults.whereType<Map>()) {
      final location = _locationFromLookup(rawResult.cast<String, Object?>());
      if (location != null) {
        locations.add(location);
      }
    }
    return locations;
  }

  Future<WeatherSnapshot> fetchCurrentWeather(WeatherLocation location) async {
    final json = await fetchJson(
      Uri.https(_apiHost, '/v7/weather/now', {
        'location': [
          location.longitude.toStringAsFixed(2),
          location.latitude.toStringAsFixed(2),
        ].join(','),
        'lang': 'zh',
      }),
    );
    _throwIfError(json);

    final rawNow = json['now'];
    if (rawNow is! Map) {
      throw const WeatherServiceException('天气数据格式不完整。');
    }
    final now = rawNow.cast<String, Object?>();

    final temperature = _readDouble(now['temp']);
    final apparentTemperature = _readDouble(now['feelsLike']);
    final humidity = _readInt(now['humidity']);
    final windSpeed = _readDouble(now['windSpeed']);
    final text = _readString(now['text']);
    if (temperature == null ||
        apparentTemperature == null ||
        humidity == null ||
        windSpeed == null ||
        text == null) {
      throw const WeatherServiceException('天气数据缺少关键字段。');
    }

    final icon = _readString(now['icon']);
    final iconCode = int.tryParse(icon ?? '') ?? 0;

    return WeatherSnapshot(
      location: location,
      temperatureC: temperature,
      apparentTemperatureC: apparentTemperature,
      relativeHumidity: humidity,
      precipitationMm: _readDouble(now['precip']) ?? 0,
      windSpeedKmh: windSpeed,
      weatherCode: iconCode,
      condition: conditionForText(text),
      isDay: !_nightIcons.contains(iconCode),
      fetchedAt: DateTime.now(),
    );
  }

  static const _nightIcons = {150, 151, 152, 153};

  static WeatherCondition conditionForText(String text) {
    final value = text.trim();
    if (value.isEmpty) {
      return WeatherCondition.unknown;
    }
    if (value.contains('雷')) {
      return WeatherCondition.thunderstorm;
    }
    if (value.contains('雪') || value.contains('冰雹')) {
      return WeatherCondition.snow;
    }
    if (value.contains('雨')) {
      if (value.contains('毛') ||
          value.contains('细') ||
          value.contains('小') ||
          value.contains('阵雨')) {
        return WeatherCondition.drizzle;
      }
      return WeatherCondition.rain;
    }
    if (value.contains('雾') || value.contains('霾')) {
      return WeatherCondition.fog;
    }
    if (value.contains('沙') || value.contains('尘')) {
      return WeatherCondition.dust;
    }
    if (value.contains('晴')) {
      return WeatherCondition.clear;
    }
    if (value.contains('云') || value.contains('阴')) {
      return WeatherCondition.cloudy;
    }
    if (value.contains('热')) {
      return WeatherCondition.clear;
    }
    if (value.contains('冷')) {
      return WeatherCondition.cloudy;
    }
    return WeatherCondition.unknown;
  }

  void _throwIfError(Map<String, Object?> json) {
    final code = _readString(json['code']);
    if (code == null || code == '200') {
      return;
    }
    throw WeatherServiceException(_errorMessageForCode(code));
  }

  static String _errorMessageForCode(String code) {
    const messages = <String, String>{
      '400': '请求参数错误',
      '401': '认证失败，请检查 API Key 和 API Host',
      '402': '今日免费额度已用完或账户欠费',
      '403': '无访问权限，请确认订阅套餐',
      '404': '未找到该城市或数据',
      '429': '请求过于频繁，请稍后再试',
      '500': '天气服务内部错误',
      '502': '天气服务网关错误',
      '503': '天气服务暂时不可用',
      '504': '天气服务网关超时',
    };
    return '天气服务错误 $code（${messages[code] ?? '未知错误'}）';
  }

  WeatherLocation? _locationFromLookup(Map<String, Object?> json) {
    final latitude = _readDouble(json['lat']);
    final longitude = _readDouble(json['lon']);
    final city = _readString(json['name']);
    if (latitude == null || longitude == null || city == null) {
      return null;
    }

    final country = _readString(json['country']);
    return WeatherLocation(
      city: city,
      region: _compactRegion(_readString(json['adm1'])),
      countryCode: country == '中国' ? 'CN' : country,
      latitude: latitude,
      longitude: longitude,
      timezone: _readString(json['tz']),
      source: WeatherLocationSource.selected,
    );
  }

  static String? _compactRegion(String? region) {
    if (region == null) {
      return null;
    }
    for (final suffix in ['省', '市', '自治区', '特别行政区']) {
      if (region.endsWith(suffix)) {
        return region.substring(0, region.length - suffix.length);
      }
    }
    return region;
  }

  static String? _publicLocationQuery(String body) {
    final ipMatch = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b').firstMatch(body);
    final fromMatch = RegExp(
      r'(?:来自于|来自)\s*[:：]\s*([^\s][\s\S]*?)\s*$',
    ).firstMatch(body);
    if (fromMatch == null) {
      return ipMatch?.group(0);
    }

    const operators = <String>{
      '电信',
      '联通',
      '移动',
      '铁通',
      '教育网',
      '长城宽带',
      '鹏博士',
      '广电',
      '卫通',
      '有线通',
      '方正宽带',
    };
    final tokens = fromMatch
        .group(1)!
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .where((token) => token != '中国' && !operators.contains(token))
        .toList();
    if (tokens.isEmpty) {
      return ipMatch?.group(0);
    }
    return tokens.take(2).join(' ');
  }

  Future<Map<String, Object?>> fetchJson(Uri uri) async {
    final ownsClient = _client == null;
    final client = _client ?? HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'ResearchLife/0.1');
      if (_apiKey.isNotEmpty) {
        request.headers.set('X-QW-Api-Key', _apiKey);
      }
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

  Future<String> _fetchRawText(Uri uri) async {
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
        throw WeatherServiceException('定位服务返回 ${response.statusCode}。');
      }
      return body;
    } on TimeoutException {
      throw const WeatherServiceException('定位服务连接超时。');
    } on SocketException {
      throw const WeatherServiceException('无法连接定位服务。');
    } finally {
      if (ownsClient) {
        client.close(force: true);
      }
    }
  }
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
