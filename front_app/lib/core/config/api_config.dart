/// 后端 API 配置（开发环境默认本机 Spring Boot）。
class ApiConfig {
  const ApiConfig._();

  static const String defaultBaseUrl = 'http://127.0.0.1:8080';
  static const String configuredBaseUrl = String.fromEnvironment(
    'RESEARCH_LIFE_API_BASE_URL',
  );

  static String get baseUrl {
    final value = configuredBaseUrl.trim();
    return value.isEmpty ? defaultBaseUrl : value;
  }

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
