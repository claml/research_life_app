import '../../core/models/app_models.dart';
import 'analysis_service.dart';

abstract interface class AnalysisEngine {
  Future<AnalysisDraft> analyze(
    AnalysisInput input, {
    String? historyPersonText,
    List<String>? clarificationAnswers,
  });
}

class RuleBasedAnalysisEngine implements AnalysisEngine {
  const RuleBasedAnalysisEngine(this._analysisService);

  final AnalysisService _analysisService;

  @override
  Future<AnalysisDraft> analyze(
    AnalysisInput input, {
    String? historyPersonText,
    List<String>? clarificationAnswers,
  }) async {
    return _analysisService.analyze(input);
  }
}
