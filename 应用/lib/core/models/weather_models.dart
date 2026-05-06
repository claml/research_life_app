enum WeatherCondition {
  clear,
  cloudy,
  fog,
  drizzle,
  rain,
  snow,
  thunderstorm,
  unknown,
}

extension WeatherConditionLabel on WeatherCondition {
  String get label => switch (this) {
    WeatherCondition.clear => '晴',
    WeatherCondition.cloudy => '多云',
    WeatherCondition.fog => '雾',
    WeatherCondition.drizzle => '小雨',
    WeatherCondition.rain => '雨',
    WeatherCondition.snow => '雪',
    WeatherCondition.thunderstorm => '雷雨',
    WeatherCondition.unknown => '天气',
  };

  bool get hasVisiblePrecipitation =>
      this == WeatherCondition.drizzle ||
      this == WeatherCondition.rain ||
      this == WeatherCondition.snow ||
      this == WeatherCondition.thunderstorm;
}

enum WeatherLocationSource { automatic, selected }

class WeatherLocation {
  const WeatherLocation({
    required this.city,
    required this.latitude,
    required this.longitude,
    this.region,
    this.countryCode,
    this.timezone,
    this.source = WeatherLocationSource.selected,
  });

  final String city;
  final String? region;
  final String? countryCode;
  final double latitude;
  final double longitude;
  final String? timezone;
  final WeatherLocationSource source;

  String get displayName {
    final parts = <String>[
      city,
      if (region != null && region!.trim().isNotEmpty) region!,
      if (countryCode != null && countryCode!.trim().isNotEmpty) countryCode!,
    ];
    final seen = <String>{};
    return parts
        .where((part) => seen.add(part.trim().toLowerCase()))
        .join(' · ');
  }

  WeatherLocation copyWith({
    String? city,
    String? region,
    String? countryCode,
    double? latitude,
    double? longitude,
    String? timezone,
    WeatherLocationSource? source,
  }) {
    return WeatherLocation(
      city: city ?? this.city,
      region: region ?? this.region,
      countryCode: countryCode ?? this.countryCode,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timezone: timezone ?? this.timezone,
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'city': city,
      'region': region,
      'countryCode': countryCode,
      'latitude': latitude,
      'longitude': longitude,
      'timezone': timezone,
      'source': source.name,
    };
  }

  static WeatherLocation? fromJson(Map<String, Object?> json) {
    final city = json['city'];
    final latitude = _readDouble(json['latitude']);
    final longitude = _readDouble(json['longitude']);
    if (city is! String ||
        city.trim().isEmpty ||
        latitude == null ||
        longitude == null) {
      return null;
    }

    final sourceName = json['source'];
    final source = WeatherLocationSource.values.firstWhere(
      (item) => item.name == sourceName,
      orElse: () => WeatherLocationSource.selected,
    );

    return WeatherLocation(
      city: city.trim(),
      region: _readString(json['region']),
      countryCode: _readString(json['countryCode']),
      latitude: latitude,
      longitude: longitude,
      timezone: _readString(json['timezone']),
      source: source,
    );
  }
}

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.location,
    required this.temperatureC,
    required this.apparentTemperatureC,
    required this.relativeHumidity,
    required this.precipitationMm,
    required this.windSpeedKmh,
    required this.weatherCode,
    required this.condition,
    required this.isDay,
    required this.fetchedAt,
  });

  final WeatherLocation location;
  final double temperatureC;
  final double apparentTemperatureC;
  final int relativeHumidity;
  final double precipitationMm;
  final double windSpeedKmh;
  final int weatherCode;
  final WeatherCondition condition;
  final bool isDay;
  final DateTime fetchedAt;

  String get temperatureLabel => '${temperatureC.round()}°';
  String get detailLabel =>
      '体感 ${apparentTemperatureC.round()}° · 湿度 $relativeHumidity% · 风 ${windSpeedKmh.round()} km/h';
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

String? _readString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}
