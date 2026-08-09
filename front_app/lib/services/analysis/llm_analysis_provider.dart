abstract interface class LlmAnalysisProvider {
  Future<String> generateAnalysisJson({
    required String prompt,
    required Object? format,
    Map<String, Object?>? options,
    Map<String, Object?>? extraBody,
    Duration? timeout,
  });
}
