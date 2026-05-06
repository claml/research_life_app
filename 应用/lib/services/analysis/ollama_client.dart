import 'dart:async';
import 'dart:convert';
import 'dart:io';

class OllamaClient {
  OllamaClient({
    Uri? baseUri,
    this.timeout = const Duration(seconds: 30),
    HttpClient? httpClient,
    OllamaTransport? transport,
  }) : baseUri = _normalizeBaseUri(
         baseUri ?? Uri.parse('http://127.0.0.1:11434'),
       ),
       _transport =
           transport ??
           OllamaHttpClientTransport(
             client: httpClient,
             ownsClient: httpClient == null,
           );

  final Uri baseUri;
  final Duration timeout;
  final OllamaTransport _transport;

  Future<OllamaGenerateResponse> generate({
    required String model,
    required String prompt,
    Object? format,
    Map<String, Object?>? options,
    Duration? timeout,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'prompt': prompt,
      'stream': false,
    };
    if (format != null) {
      body['format'] = format;
    }
    if (options != null) {
      body['options'] = options;
    }
    final json = await _postJson(
      '/api/generate',
      body,
      timeout: timeout ?? this.timeout,
    );
    return OllamaGenerateResponse.fromJson(json);
  }

  Future<bool> checkHealth({Duration? timeout}) async {
    await listModels(timeout: timeout);
    return true;
  }

  Future<List<OllamaModel>> listModels({Duration? timeout}) async {
    final json = await _getJson('/api/tags', timeout: timeout ?? this.timeout);
    final models = json['models'];
    if (models is! List) {
      throw OllamaInvalidJsonException(
        'Ollama model list response is missing "models".',
        uri: _uriFor('/api/tags'),
      );
    }

    return models.map((model) {
      if (model is Map<String, dynamic>) {
        return OllamaModel.fromJson(model);
      }
      if (model is Map) {
        return OllamaModel.fromJson(
          model.map((key, value) => MapEntry('$key', value)),
        );
      }
      throw OllamaInvalidJsonException(
        'Ollama model list contains an invalid model item.',
        uri: _uriFor('/api/tags'),
      );
    }).toList();
  }

  void close({bool force = false}) {
    _transport.close(force: force);
  }

  Future<Map<String, Object?>> _getJson(
    String path, {
    required Duration timeout,
  }) async {
    final uri = _uriFor(path);
    final response = await _send(
      uri,
      () => _transport.get(uri, timeout: timeout),
    );
    return _decodeObjectJson(response, uri);
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body, {
    required Duration timeout,
  }) async {
    final uri = _uriFor(path);
    final response = await _send(
      uri,
      () => _transport.post(uri, body: body, timeout: timeout),
    );
    return _decodeObjectJson(response, uri);
  }

  Future<OllamaTransportResponse> _send(
    Uri uri,
    Future<OllamaTransportResponse> Function() send,
  ) async {
    try {
      final response = await send();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OllamaHttpStatusException(
          'Ollama returned HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
          responseBody: response.body,
          uri: uri,
        );
      }
      return response;
    } on OllamaClientException {
      rethrow;
    } on TimeoutException catch (error) {
      throw OllamaTimeoutException(
        'Ollama request timed out.',
        uri: uri,
        cause: error,
      );
    } on SocketException catch (error) {
      throw OllamaConnectionException(
        'Unable to connect to Ollama.',
        uri: uri,
        cause: error,
      );
    } on HttpException catch (error) {
      throw OllamaConnectionException(
        'Ollama connection failed.',
        uri: uri,
        cause: error,
      );
    } on IOException catch (error) {
      throw OllamaConnectionException(
        'Ollama I/O request failed.',
        uri: uri,
        cause: error,
      );
    }
  }

  Map<String, Object?> _decodeObjectJson(
    OllamaTransportResponse response,
    Uri uri,
  ) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      throw OllamaInvalidJsonException(
        'Ollama returned JSON that is not an object.',
        uri: uri,
      );
    } on OllamaInvalidJsonException {
      rethrow;
    } on FormatException catch (error) {
      throw OllamaInvalidJsonException(
        'Ollama returned invalid JSON.',
        uri: uri,
        cause: error,
      );
    }
  }

  Uri _uriFor(String path) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(path: '$basePath$path', query: null);
  }

  static Uri _normalizeBaseUri(Uri uri) {
    if (!uri.hasScheme) {
      return Uri.parse('http://$uri');
    }
    return uri;
  }
}

abstract class OllamaTransport {
  Future<OllamaTransportResponse> get(Uri uri, {required Duration timeout});

  Future<OllamaTransportResponse> post(
    Uri uri, {
    required Map<String, Object?> body,
    required Duration timeout,
  });

  void close({bool force = false});
}

class OllamaHttpClientTransport implements OllamaTransport {
  OllamaHttpClientTransport({HttpClient? client, bool ownsClient = true})
    : _client = client ?? HttpClient(),
      _ownsClient = ownsClient;

  final HttpClient _client;
  final bool _ownsClient;

  @override
  Future<OllamaTransportResponse> get(Uri uri, {required Duration timeout}) {
    return _send('GET', uri, timeout: timeout);
  }

  @override
  Future<OllamaTransportResponse> post(
    Uri uri, {
    required Map<String, Object?> body,
    required Duration timeout,
  }) {
    return _send('POST', uri, body: body, timeout: timeout);
  }

  @override
  void close({bool force = false}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  Future<OllamaTransportResponse> _send(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    required Duration timeout,
  }) async {
    _client.connectionTimeout = timeout;
    final request = await _client.openUrl(method, uri).timeout(timeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'ResearchLife/0.1');
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close().timeout(timeout);
    final responseBody = await response
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    return OllamaTransportResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  }
}

class OllamaTransportResponse {
  const OllamaTransportResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class OllamaGenerateResponse {
  const OllamaGenerateResponse({
    required this.model,
    required this.response,
    required this.done,
    required this.rawJson,
    this.createdAt,
    this.doneReason,
  });

  final String model;
  final String response;
  final bool done;
  final DateTime? createdAt;
  final String? doneReason;
  final Map<String, Object?> rawJson;

  factory OllamaGenerateResponse.fromJson(Map<String, Object?> json) {
    final response = json['response'];
    if (response is! String) {
      throw const OllamaInvalidJsonException(
        'Ollama generate response is missing "response".',
      );
    }

    return OllamaGenerateResponse(
      model: _stringValue(json['model']) ?? '',
      response: response,
      done: _boolValue(json['done']) ?? false,
      createdAt: _dateTimeValue(json['created_at']),
      doneReason: _stringValue(json['done_reason']),
      rawJson: json,
    );
  }
}

class OllamaModel {
  const OllamaModel({
    required this.name,
    this.model,
    this.modifiedAt,
    this.size,
    this.digest,
    this.details,
  });

  final String name;
  final String? model;
  final DateTime? modifiedAt;
  final int? size;
  final String? digest;
  final Map<String, Object?>? details;

  factory OllamaModel.fromJson(Map<String, Object?> json) {
    final name = _stringValue(json['name']) ?? _stringValue(json['model']);
    if (name == null || name.isEmpty) {
      throw const OllamaInvalidJsonException(
        'Ollama model item is missing a name.',
      );
    }

    final details = json['details'];
    return OllamaModel(
      name: name,
      model: _stringValue(json['model']),
      modifiedAt: _dateTimeValue(json['modified_at']),
      size: _intValue(json['size']),
      digest: _stringValue(json['digest']),
      details: details is Map<String, dynamic>
          ? details
          : details is Map
          ? details.map((key, value) => MapEntry('$key', value))
          : null,
    );
  }
}

class OllamaClientException implements Exception {
  const OllamaClientException(this.message, {this.uri, this.cause});

  final String message;
  final Uri? uri;
  final Object? cause;

  @override
  String toString() {
    final uriText = uri == null ? '' : ' ($uri)';
    final causeText = cause == null ? '' : ': $cause';
    return '$message$uriText$causeText';
  }
}

class OllamaConnectionException extends OllamaClientException {
  const OllamaConnectionException(super.message, {super.uri, super.cause});
}

class OllamaTimeoutException extends OllamaClientException {
  const OllamaTimeoutException(super.message, {super.uri, super.cause});
}

class OllamaHttpStatusException extends OllamaClientException {
  const OllamaHttpStatusException(
    super.message, {
    required this.statusCode,
    required this.responseBody,
    super.uri,
  });

  final int statusCode;
  final String responseBody;
}

class OllamaInvalidJsonException extends OllamaClientException {
  const OllamaInvalidJsonException(super.message, {super.uri, super.cause});
}

String? _stringValue(Object? value) {
  if (value == null) {
    return null;
  }
  final text = '$value';
  return text.isEmpty ? null : text;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('$value');
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true'
        ? true
        : value.toLowerCase() == 'false'
        ? false
        : null;
  }
  return null;
}

DateTime? _dateTimeValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return DateTime.tryParse('$value');
}
