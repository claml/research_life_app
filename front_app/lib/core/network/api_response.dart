class ApiResponse<T> {
  const ApiResponse({required this.code, required this.msg, this.data});

  final int code;
  final String msg;
  final T? data;

  bool get isSuccess => code == 200;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T? Function(Object? json) fromJsonT, {
    bool allowNullData = false,
  }) {
    final rawData = json['data'];
    T? data;
    if (rawData != null) {
      data = fromJsonT(rawData);
    } else if (allowNullData) {
      data = null;
    }
    return ApiResponse<T>(
      code: _intValue(json['code']) ?? 500,
      msg: '${json['msg'] ?? ''}',
      data: data,
    );
  }
}

int? _intValue(Object? value) {
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
