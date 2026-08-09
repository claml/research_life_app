import '../../core/network/api_client.dart';
import '../../core/network/json_parse.dart';
import 'llm_analysis_provider.dart';

class RemoteLlmAnalysisProvider implements LlmAnalysisProvider {
  RemoteLlmAnalysisProvider({
    ApiClient? apiClient,
    RemoteLlmTransport? transport,
    this.endpointPath = '/api/v1/analysis/weekly',
  }) : assert(apiClient != null || transport != null),
       _transport = transport ?? ApiClientRemoteLlmTransport(apiClient!);

  final String endpointPath;
  final RemoteLlmTransport _transport;

  @override
  Future<String> generateAnalysisJson({
    required String prompt,
    required Object? format,
    Map<String, Object?>? options,
    Map<String, Object?>? extraBody,
    Duration? timeout,
  }) async {
    final response = await _transport.post(
      endpointPath,
      body: {
        'prompt': prompt,
        'format': format ?? 'json',
        'options': options,
        if (extraBody != null && extraBody.isNotEmpty) ...extraBody,
      },
      timeout: timeout,
    );
    if (response.response.trim().isEmpty) {
      throw const RemoteLlmProviderException('Remote LLM response is empty.');
    }
    return response.response;
  }
}

abstract interface class RemoteLlmTransport {
  Future<RemoteLlmTransportResponse> post(
    String path, {
    required Map<String, Object?> body,
    Duration? timeout,
  });
}

class ApiClientRemoteLlmTransport implements RemoteLlmTransport {
  const ApiClientRemoteLlmTransport(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<RemoteLlmTransportResponse> post(
    String path, {
    required Map<String, Object?> body,
    Duration? timeout,
  }) async {
    try {
      return await _apiClient.postData<RemoteLlmTransportResponse>(
        path,
        data: body,
        receiveTimeout: timeout,
        fromJson: (json) => RemoteLlmTransportResponse.fromJson(
          parseJsonMap(json, field: 'remote LLM response'),
        ),
      );
    } catch (error) {
      throw RemoteLlmProviderException(
        'Remote LLM request failed.',
        cause: error,
      );
    }
  }
}

class RemoteLlmTransportResponse {
  const RemoteLlmTransportResponse({required this.response, this.model});

  factory RemoteLlmTransportResponse.fromJson(Map<String, dynamic> json) {
    final response = json['response'];
    if (response is! String) {
      throw const RemoteLlmProviderException(
        'Remote LLM response is missing "response".',
      );
    }
    final model = json['model'];
    return RemoteLlmTransportResponse(
      response: response,
      model: model is String ? model : null,
    );
  }

  final String response;
  final String? model;
}

class RemoteLlmProviderException implements Exception {
  const RemoteLlmProviderException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final causeText = cause == null ? '' : ': $cause';
    return '$message$causeText';
  }
}
