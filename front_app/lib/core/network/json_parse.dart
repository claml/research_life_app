Map<String, dynamic> parseJsonMap(Object? json, {String? field}) {
  if (json is Map<String, dynamic>) {
    return json;
  }
  if (json is Map) {
    return Map<String, dynamic>.from(json);
  }
  final label = field ?? '数据';
  throw FormatException('$label 格式错误（期望 JSON 对象）');
}

List<Map<String, dynamic>> parseJsonMapList(Object? json) {
  if (json == null) {
    return const [];
  }
  if (json is! List) {
    return const [];
  }
  return json
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
