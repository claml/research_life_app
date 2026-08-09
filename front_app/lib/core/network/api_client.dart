import 'package:dio/dio.dart';

import '../config/api_config.dart';
import 'api_exception.dart';
import 'api_response.dart';
import 'json_parse.dart';

typedef TokenReader = String? Function();
typedef UnauthorizedHandler = Future<bool> Function();

class ApiClient {
  ApiClient({
    Dio? dio,
    TokenReader? accessTokenReader,
    UnauthorizedHandler? onUnauthorized,
  }) : _accessTokenReader = accessTokenReader,
       _onUnauthorized = onUnauthorized {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: ApiConfig.baseUrl,
            connectTimeout: ApiConfig.connectTimeout,
            receiveTimeout: ApiConfig.receiveTimeout,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _accessTokenReader?.call();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (options.data is FormData) {
            options.headers.remove('Content-Type');
          }
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;
  final TokenReader? _accessTokenReader;
  final UnauthorizedHandler? _onUnauthorized;

  Dio get dio => _dio;

  Future<T> postData<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Duration? receiveTimeout,
    required T Function(Object? json) fromJson,
    bool allowNullData = false,
  }) {
    return _request<T>(
      () => _dio.post<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: receiveTimeout == null
            ? null
            : Options(receiveTimeout: receiveTimeout),
      ),
      fromJson,
      allowNullData: allowNullData,
    );
  }

  Future<T> getData<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    required T Function(Object? json) fromJson,
    bool allowNullData = false,
  }) {
    return _request<T>(
      () => _dio.get<dynamic>(path, queryParameters: queryParameters),
      fromJson,
      allowNullData: allowNullData,
    );
  }

  Future<T> patchData<T>(
    String path, {
    Object? data,
    required T Function(Object? json) fromJson,
    bool allowNullData = false,
  }) {
    return _request<T>(
      () => _dio.patch<dynamic>(path, data: data),
      fromJson,
      allowNullData: allowNullData,
    );
  }

  Future<void> deleteVoid(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _requestVoid(
      () => _dio.delete<dynamic>(path, queryParameters: queryParameters),
    );
  }

  Future<void> postVoid(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) {
    return _requestVoid(
      () => _dio.post<dynamic>(
        path,
        data: data,
        options: Options(headers: headers),
      ),
    );
  }

  Future<T> _request<T>(
    Future<Response<dynamic>> Function() call,
    T Function(Object? json) fromJson, {
    bool allowNullData = false,
  }) async {
    return _withUnauthorizedRetry(() async {
      final response = await call();
      final body = _readBodyMap(response.data);
      final envelope = ApiResponse<T>.fromJson(
        body,
        fromJson,
        allowNullData: allowNullData,
      );
      if (!envelope.isSuccess) {
        throw ApiException(
          envelope.code,
          envelope.msg.isEmpty ? '请求失败' : envelope.msg,
        );
      }
      if (envelope.data == null && !allowNullData) {
        throw ApiException(
          envelope.code,
          envelope.msg.isEmpty ? '响应数据为空' : envelope.msg,
        );
      }
      return envelope.data as T;
    });
  }

  Future<void> _requestVoid(Future<Response<dynamic>> Function() call) async {
    return _withUnauthorizedRetry(() async {
      final response = await call();
      final body = _readBodyMap(response.data);
      final code = _intValue(body['code']) ?? 500;
      final msg = '${body['msg'] ?? ''}';
      if (code != 200) {
        throw ApiException(code, msg.isEmpty ? '请求失败' : msg);
      }
    });
  }

  Future<T> _withUnauthorizedRetry<T>(Future<T> Function() action) async {
    try {
      return await _attempt(action);
    } on ApiException catch (error) {
      if (error.code == 401 && await _refreshForRetry()) {
        return _attempt(action);
      }
      rethrow;
    }
  }

  Future<T> _attempt<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (error) {
      throw _mapDioError(error);
    } on ApiException {
      rethrow;
    } on FormatException catch (error) {
      throw ApiException(500, error.message);
    } catch (error) {
      throw ApiException(500, '请求失败：$error');
    }
  }

  Future<bool> _refreshForRetry() async {
    final onUnauthorized = _onUnauthorized;
    if (onUnauthorized == null) {
      return false;
    }
    try {
      return await onUnauthorized();
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _readBodyMap(dynamic body) {
    if (body == null) {
      throw const ApiException(500, '服务器返回为空');
    }
    if (body is String && body.trim().isEmpty) {
      throw const ApiException(500, '服务器返回为空');
    }
    return parseJsonMap(body, field: '响应体');
  }

  ApiException _mapDioError(DioException error) {
    final response = error.response;
    final raw = response?.data;
    if (raw != null) {
      try {
        final body = parseJsonMap(raw, field: '错误响应');
        final code = _intValue(body['code']);
        final msg = body['msg'];
        if (code != null) {
          return ApiException(
            code,
            msg == null || '$msg'.isEmpty ? '请求失败' : '$msg',
          );
        }
      } on FormatException {
        // 非 JSON 错误体，走下方默认分支
      }
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const ApiException(408, '连接超时，请确认后端已启动');
      case DioExceptionType.connectionError:
        return ApiException(
          503,
          '无法连接服务器（${ApiConfig.baseUrl}），请确认 Spring Boot 与 Redis 已运行',
        );
      default:
        return ApiException(
          response?.statusCode ?? 500,
          '网络错误：${error.message ?? 'unknown'}',
        );
    }
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
