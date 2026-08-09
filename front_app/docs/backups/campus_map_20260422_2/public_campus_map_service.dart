import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:http/http.dart' as http;

class PublicCampusMapService {
  PublicCampusMapService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = 'https://map.cug.edu.cn/cmgis-server';

  final http.Client _client;

  Future<List<PublicCampusZone>> fetchZones() async {
    final root = await _getJsonObject(
      Uri.parse('$_baseUrl/map/v2/zone/page?page=0&pageSize=1000'),
    );
    final data = root['data'];
    final content = data is Map<String, dynamic> ? data['content'] : null;
    if (content is! List) {
      return const [];
    }

    final zones = <PublicCampusZone>[];
    for (final item in content) {
      if (item is! Map) {
        continue;
      }
      final zone = PublicCampusZone.fromJson(Map<String, dynamic>.from(item));
      if (zone.is2D && zone.rasterId != null) {
        zones.add(zone);
      }
    }

    zones.sort((left, right) => left.id.compareTo(right.id));
    return zones;
  }

  Future<PublicCampusMapScene> fetchScene(PublicCampusZone zone) async {
    final rasterId = zone.rasterId;
    if (rasterId == null) {
      throw Exception('Current zone does not expose a public rasterId.');
    }

    final root = await _getJsonObject(
      Uri.parse('$_baseUrl/map/v1/mapdata/threeDimensionSource/$rasterId'),
    );
    final features = root['features'];
    if (features is! List) {
      throw Exception('Public map response structure is invalid.');
    }

    final rawBuildings = <_RawCampusBuilding>[];
    for (final item in features) {
      if (item is! Map) {
        continue;
      }
      final raw = _parseBuilding(Map<String, dynamic>.from(item));
      if (raw != null) {
        rawBuildings.add(raw);
      }
    }

    final boundsPolygons = <List<Offset>>[
      for (final building in rawBuildings) ...building.geoPolygons,
      ...zone.outlineGeoPolygons,
    ];
    final sceneBounds = boundsPolygons.isEmpty
        ? zone.bounds
        : GeoBounds.fromPolygons(boundsPolygons);

    final buildings = rawBuildings
        .map((building) => building.normalize(sceneBounds))
        .toList();
    buildings.sort((left, right) {
      final namedDiff =
          (left.hasDisplayName ? 0 : 1).compareTo(right.hasDisplayName ? 0 : 1);
      if (namedDiff != 0) {
        return namedDiff;
      }
      final levelDiff = (right.levels ?? 0).compareTo(left.levels ?? 0);
      if (levelDiff != 0) {
        return levelDiff;
      }
      return left.name.compareTo(right.name);
    });

    final outlinePolygons = [
      for (final polygon in zone.outlineGeoPolygons)
        [for (final point in polygon) sceneBounds.normalizePoint(point)],
    ];

    return PublicCampusMapScene(
      zone: zone,
      sceneBounds: sceneBounds,
      outlinePolygons: List.unmodifiable(outlinePolygons),
      buildings: List.unmodifiable(buildings),
    );
  }

  void dispose() {
    _client.close();
  }

  Future<Map<String, dynamic>> _getJsonObject(Uri uri) async {
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Request failed: ${response.statusCode}');
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw Exception('Response is not a JSON object.');
    }
    return body;
  }

  _RawCampusBuilding? _parseBuilding(Map<String, dynamic> feature) {
    final geometry = feature['geometry'];
    if (geometry is! Map<String, dynamic>) {
      return null;
    }

    final geoPolygons = parseGeoPolygons(geometry);
    if (geoPolygons.isEmpty) {
      return null;
    }

    final properties = feature['properties'];
    final props = properties is Map<String, dynamic>
        ? properties
        : const <String, dynamic>{};
    final name = (props['name'] as String? ?? '').trim();
    final kind = (props['building'] as String? ??
            props['polygon_category'] as String? ??
            'building')
        .trim();
    final levels = _parseInt(props['building:levels']);
    final baseId =
        feature['id'] ??
        props['id'] ??
        props['raster_id'] ??
        (name.isEmpty ? 'building' : name);

    return _RawCampusBuilding(
      id: '${baseId}_${_polygonsHash(geoPolygons)}',
      name: name,
      kind: kind,
      levels: levels,
      geoPolygons: geoPolygons,
    );
  }

  int _polygonsHash(List<List<Offset>> polygons) {
    var hash = 17;
    for (final polygon in polygons) {
      for (final point in polygon.take(8)) {
        hash = 37 * hash + point.dx.toStringAsFixed(5).hashCode;
        hash = 37 * hash + point.dy.toStringAsFixed(5).hashCode;
      }
    }
    return hash.abs();
  }

  int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

class PublicCampusMapScene {
  const PublicCampusMapScene({
    required this.zone,
    required this.sceneBounds,
    required this.outlinePolygons,
    required this.buildings,
  });

  final PublicCampusZone zone;
  final GeoBounds sceneBounds;
  final List<List<Offset>> outlinePolygons;
  final List<PublicCampusBuilding> buildings;

  List<PublicCampusBuilding> searchBuildings(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }

    final matches = buildings.where((building) {
      if (!building.hasDisplayName) {
        return false;
      }
      return building.name.toLowerCase().contains(normalized) ||
          building.kind.toLowerCase().contains(normalized);
    }).toList();

    matches.sort((left, right) {
      final scoreDiff = _score(right, normalized).compareTo(
        _score(left, normalized),
      );
      if (scoreDiff != 0) {
        return scoreDiff;
      }
      return left.name.compareTo(right.name);
    });
    return matches;
  }

  int _score(PublicCampusBuilding building, String query) {
    var score = 0;
    final name = building.name.toLowerCase();
    if (name == query) {
      score += 10;
    }
    if (name.startsWith(query)) {
      score += 4;
    }
    if (name.contains(query)) {
      score += 2;
    }
    score += math.min(building.levels ?? 0, 9);
    return score;
  }
}

class PublicCampusZone {
  const PublicCampusZone({
    required this.id,
    required this.name,
    required this.center,
    required this.bounds,
    required this.outlineGeoPolygons,
    required this.is2D,
    required this.rasterId,
  });

  factory PublicCampusZone.fromJson(Map<String, dynamic> json) {
    final centerText = (json['center'] as String? ?? '').split(',');
    final bounds = GeoBounds.parse(json['bbox'] as String?);
    final centerLng = centerText.length >= 2
        ? double.tryParse(centerText[0].trim())
        : null;
    final centerLat = centerText.length >= 2
        ? double.tryParse(centerText[1].trim())
        : null;
    final center = centerLng != null && centerLat != null
        ? Offset(centerLng, centerLat)
        : bounds.center;

    final polygonData = json['polygonBBox'];
    final outlineGeoPolygons = polygonData is Map<String, dynamic>
        ? parseGeoPolygons(polygonData)
        : const <List<Offset>>[];

    return PublicCampusZone(
      id: json['id'] is int ? json['id'] as int : 0,
      name: (json['name'] as String? ?? '未命名校区').trim(),
      center: center,
      bounds: bounds,
      outlineGeoPolygons: List.unmodifiable(outlineGeoPolygons),
      is2D: json['is2D'] == true,
      rasterId: json['rasterId'] is int ? json['rasterId'] as int : null,
    );
  }

  final int id;
  final String name;
  final Offset center;
  final GeoBounds bounds;
  final List<List<Offset>> outlineGeoPolygons;
  final bool is2D;
  final int? rasterId;
}

class PublicCampusBuilding {
  const PublicCampusBuilding({
    required this.id,
    required this.name,
    required this.kind,
    required this.levels,
    required this.polygons,
    required this.center,
  });

  final String id;
  final String name;
  final String kind;
  final int? levels;
  final List<List<Offset>> polygons;
  final Offset center;

  bool get hasDisplayName => name.isNotEmpty && name != '未知';
}

class GeoBounds {
  const GeoBounds({
    required this.minLng,
    required this.minLat,
    required this.maxLng,
    required this.maxLat,
  });

  factory GeoBounds.parse(String? value) {
    final parts = (value ?? '').split(',');
    if (parts.length < 4) {
      return const GeoBounds(
        minLng: 0,
        minLat: 0,
        maxLng: 1,
        maxLat: 1,
      );
    }

    return GeoBounds(
      minLng: double.tryParse(parts[0].trim()) ?? 0,
      minLat: double.tryParse(parts[1].trim()) ?? 0,
      maxLng: double.tryParse(parts[2].trim()) ?? 1,
      maxLat: double.tryParse(parts[3].trim()) ?? 1,
    );
  }

  factory GeoBounds.fromPolygons(List<List<Offset>> polygons) {
    var minLng = double.infinity;
    var minLat = double.infinity;
    var maxLng = double.negativeInfinity;
    var maxLat = double.negativeInfinity;

    for (final polygon in polygons) {
      for (final point in polygon) {
        minLng = math.min(minLng, point.dx);
        minLat = math.min(minLat, point.dy);
        maxLng = math.max(maxLng, point.dx);
        maxLat = math.max(maxLat, point.dy);
      }
    }

    if (!minLng.isFinite ||
        !minLat.isFinite ||
        !maxLng.isFinite ||
        !maxLat.isFinite) {
      return const GeoBounds(
        minLng: 0,
        minLat: 0,
        maxLng: 1,
        maxLat: 1,
      );
    }

    if (minLng == maxLng) {
      maxLng += 0.0001;
    }
    if (minLat == maxLat) {
      maxLat += 0.0001;
    }

    return GeoBounds(
      minLng: minLng,
      minLat: minLat,
      maxLng: maxLng,
      maxLat: maxLat,
    );
  }

  final double minLng;
  final double minLat;
  final double maxLng;
  final double maxLat;

  Offset get center => Offset((minLng + maxLng) / 2, (minLat + maxLat) / 2);

  Offset normalize({
    required double lng,
    required double lat,
  }) {
    final width = maxLng - minLng;
    final height = maxLat - minLat;
    if (width == 0 || height == 0) {
      return const Offset(0.5, 0.5);
    }

    final dx = ((lng - minLng) / width).clamp(0.0, 1.0);
    final dy = (1 - (lat - minLat) / height).clamp(0.0, 1.0);
    return Offset(dx.toDouble(), dy.toDouble());
  }

  Offset normalizePoint(Offset point) => normalize(lng: point.dx, lat: point.dy);
}

List<List<Offset>> parseGeoPolygons(Map<String, dynamic> geometry) {
  final type = geometry['type'];
  final coordinates = geometry['coordinates'];
  final polygonGroups = <dynamic>[];

  if (type == 'Polygon' && coordinates is List) {
    polygonGroups.add(coordinates);
  } else if (type == 'MultiPolygon' && coordinates is List) {
    polygonGroups.addAll(coordinates);
  } else {
    return const [];
  }

  final polygons = <List<Offset>>[];
  for (final group in polygonGroups) {
    if (group is! List || group.isEmpty) {
      continue;
    }
    final outerRing = group.first;
    if (outerRing is! List) {
      continue;
    }

    final points = <Offset>[];
    for (final point in outerRing) {
      if (point is! List || point.length < 2) {
        continue;
      }
      final lng = _parseDouble(point[0]);
      final lat = _parseDouble(point[1]);
      if (lng == null || lat == null) {
        continue;
      }
      points.add(Offset(lng, lat));
    }

    if (points.length >= 3) {
      polygons.add(points);
    }
  }

  return polygons;
}

double? _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

class _RawCampusBuilding {
  const _RawCampusBuilding({
    required this.id,
    required this.name,
    required this.kind,
    required this.levels,
    required this.geoPolygons,
  });

  final String id;
  final String name;
  final String kind;
  final int? levels;
  final List<List<Offset>> geoPolygons;

  PublicCampusBuilding normalize(GeoBounds bounds) {
    final polygons = [
      for (final polygon in geoPolygons)
        [for (final point in polygon) bounds.normalizePoint(point)],
    ];
    return PublicCampusBuilding(
      id: id,
      name: name,
      kind: kind,
      levels: levels,
      polygons: List.unmodifiable(polygons),
      center: _resolveCenter(polygons),
    );
  }

  Offset _resolveCenter(List<List<Offset>> polygons) {
    var minDx = double.infinity;
    var minDy = double.infinity;
    var maxDx = double.negativeInfinity;
    var maxDy = double.negativeInfinity;

    for (final polygon in polygons) {
      for (final point in polygon) {
        minDx = math.min(minDx, point.dx);
        minDy = math.min(minDy, point.dy);
        maxDx = math.max(maxDx, point.dx);
        maxDy = math.max(maxDy, point.dy);
      }
    }

    return Offset((minDx + maxDx) / 2, (minDy + maxDy) / 2);
  }
}
