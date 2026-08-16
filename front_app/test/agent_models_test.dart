import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/agent/agent_models.dart';

void main() {
  test('thinking trace round-trips status and ordered steps', () {
    const trace = AgentThinkingTrace(
      status: AgentThinkingStatus.completed,
      steps: ['已保存用户消息', '已整理对话上下文', '已生成回复'],
    );

    final decoded = AgentThinkingTrace.tryDecode(trace.encode());

    expect(decoded?.status, AgentThinkingStatus.completed);
    expect(decoded?.steps, trace.steps);
  });

  test('thinking trace ignores foreign and malformed reasoning content', () {
    expect(AgentThinkingTrace.tryDecode(null), isNull);
    expect(AgentThinkingTrace.tryDecode('provider reasoning'), isNull);
    expect(AgentThinkingTrace.tryDecode('{"kind":"other"}'), isNull);
    expect(
      AgentThinkingTrace.tryDecode(
        '{"kind":"research_life_thinking_trace","version":2,'
        '"status":"completed","steps":["step"]}',
      ),
      isNull,
    );
    expect(
      AgentThinkingTrace.tryDecode(
        '{"kind":"research_life_thinking_trace","version":1,'
        '"status":"completed","steps":["step",1]}',
      ),
      isNull,
    );
    expect(
      AgentThinkingTrace.tryDecode(
        '{"kind":"research_life_thinking_trace","version":1,'
        '"status":"unknown","steps":["step"]}',
      ),
      isNull,
    );
  });
}
