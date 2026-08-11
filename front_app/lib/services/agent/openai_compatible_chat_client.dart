import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'agent_models.dart';
import 'ai_profile.dart';

enum AiChatClientExceptionKind {
  authentication,
  rateLimited,
  unreachable,
  timeout,
  invalidResponse,
  server,
  cancelled,
}

class AiChatClientException implements Exception {
  const AiChatClientException(this.kind, this.message);

  const AiChatClientException.authentication()
    : this(AiChatClientExceptionKind.authentication, '身份验证失败，请检查访问凭据。');

  const AiChatClientException.rateLimited()
    : this(AiChatClientExceptionKind.rateLimited, '请求过于频繁，请稍后再试。');

  const AiChatClientException.unreachable()
    : this(AiChatClientExceptionKind.unreachable, '无法连接到模型服务。');

  const AiChatClientException.timeout()
    : this(AiChatClientExceptionKind.timeout, '模型服务请求超时。');

  const AiChatClientException.invalidResponse()
    : this(AiChatClientExceptionKind.invalidResponse, '模型服务返回了无效响应。');

  const AiChatClientException.server()
    : this(AiChatClientExceptionKind.server, '模型服务暂时不可用。');

  const AiChatClientException.cancelled()
    : this(AiChatClientExceptionKind.cancelled, '模型请求已取消。');

  final AiChatClientExceptionKind kind;
  final String message;

  @override
  String toString() => message;
}

class OpenAiCompatibleChatClient {
  OpenAiCompatibleChatClient({
    Duration connectTimeout = const Duration(seconds: 15),
    Duration sendTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 60),
    HttpClientAdapter? httpClientAdapter,
  }) : _dio = Dio(
         BaseOptions(
           connectTimeout: connectTimeout,
           sendTimeout: sendTimeout,
           receiveTimeout: receiveTimeout,
         ),
       ) {
    if (httpClientAdapter != null) {
      _dio.httpClientAdapter = httpClientAdapter;
    }
  }

  final Dio _dio;

  Future<AiChatCompletion> complete({
    required AiProviderProfile profile,
    required List<AiChatTurn> messages,
    required String? credential,
    CancelToken? cancelToken,
  }) async {
    final endpoint = _chatCompletionsUri(profile);
    final trimmedCredential = credential?.trim();

    try {
      final response = await _dio.postUri<String>(
        endpoint,
        data: <String, Object?>{
          'model': profile.model,
          'messages': [
            for (final message in messages)
              <String, String>{
                'role': message.role,
                'content': message.content,
              },
          ],
        },
        options: Options(
          headers: <String, String>{
            if (trimmedCredential != null && trimmedCredential.isNotEmpty)
              HttpHeaders.authorizationHeader: 'Bearer $trimmedCredential',
          },
          responseType: ResponseType.plain,
        ),
        cancelToken: cancelToken,
      );
      return _parseCompletion(response.data);
    } on AiChatClientException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException {
      throw const AiChatClientException.invalidResponse();
    } on Object {
      throw const AiChatClientException.invalidResponse();
    }
  }
}

Uri _chatCompletionsUri(AiProviderProfile profile) {
  final uri = Uri.tryParse(profile.baseUrl.trim());
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const AiChatClientException.invalidResponse();
  }
  if (uri.scheme == 'http' &&
      profile.provider != 'ollama' &&
      profile.provider != 'custom' &&
      !_isLoopbackHost(uri.host)) {
    throw const AiChatClientException.invalidResponse();
  }

  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (!path.endsWith('/chat/completions')) {
    path = path.isEmpty || path == '/'
        ? '/v1/chat/completions'
        : '$path/chat/completions';
  }
  return uri.replace(path: path, fragment: '');
}

bool _isLoopbackHost(String host) {
  if (host.toLowerCase() == 'localhost') return true;
  return InternetAddress.tryParse(host)?.isLoopback ?? false;
}

AiChatCompletion _parseCompletion(Object? responseData) {
  final Object? decoded;
  if (responseData is String) {
    decoded = jsonDecode(responseData);
  } else {
    decoded = responseData;
  }
  if (decoded is! Map) {
    throw const AiChatClientException.invalidResponse();
  }

  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty || choices.first is! Map) {
    throw const AiChatClientException.invalidResponse();
  }
  final choice = choices.first as Map;
  final message = choice['message'];
  if (message is! Map) {
    throw const AiChatClientException.invalidResponse();
  }
  final content = message['content'];
  if (content is! String || content.trim().isEmpty) {
    throw const AiChatClientException.invalidResponse();
  }

  return AiChatCompletion(
    content: content,
    reasoningContent: _optionalString(message['reasoning_content']),
    model: _optionalString(decoded['model']),
    finishReason: _optionalString(choice['finish_reason']),
  );
}

String? _optionalString(Object? value) => value is String ? value : null;

AiChatClientException _mapDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.cancel:
      return const AiChatClientException.cancelled();
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const AiChatClientException.timeout();
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return const AiChatClientException.unreachable();
    case DioExceptionType.badResponse:
      final statusCode = error.response?.statusCode;
      if (statusCode == HttpStatus.unauthorized ||
          statusCode == HttpStatus.forbidden) {
        return const AiChatClientException.authentication();
      }
      if (statusCode == HttpStatus.tooManyRequests) {
        return const AiChatClientException.rateLimited();
      }
      if (statusCode != null && statusCode >= 500) {
        return const AiChatClientException.server();
      }
      return const AiChatClientException.invalidResponse();
    case DioExceptionType.unknown:
      if (error.error is SocketException) {
        return const AiChatClientException.unreachable();
      }
      return const AiChatClientException.server();
  }
}
