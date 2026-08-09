class LlmProviderPreset {
  const LlmProviderPreset({
    required this.id,
    required this.label,
    required this.defaultBaseUrl,
    required this.defaultModel,
  });

  final String id;
  final String label;
  final String defaultBaseUrl;
  final String defaultModel;
}

const llmProviderPresets = <LlmProviderPreset>[
  LlmProviderPreset(
    id: 'deepseek',
    label: 'DeepSeek',
    defaultBaseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-v4-flash',
  ),
  LlmProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    defaultBaseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
  ),
  LlmProviderPreset(
    id: 'moonshot',
    label: 'Kimi（Moonshot）',
    defaultBaseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'moonshot-v1-8k',
  ),
  LlmProviderPreset(
    id: 'zhipu',
    label: '智谱 GLM',
    defaultBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4-flash',
  ),
  LlmProviderPreset(
    id: 'ollama',
    label: 'Ollama（本地）',
    defaultBaseUrl: 'http://localhost:11434/v1',
    defaultModel: 'llama3',
  ),
];

const llmCustomProviderId = 'custom';

const llmCustomProviderPreset = LlmProviderPreset(
  id: llmCustomProviderId,
  label: '自定义',
  defaultBaseUrl: '',
  defaultModel: '',
);

LlmProviderPreset? llmPresetById(String? id) {
  if (id == null || id == llmCustomProviderId) {
    return null;
  }
  for (final preset in llmProviderPresets) {
    if (preset.id == id) {
      return preset;
    }
  }
  return null;
}

String? llmResolveBaseUrl({required String? provider, String? baseUrl}) {
  final customBaseUrl = baseUrl?.trim();
  if (customBaseUrl != null && customBaseUrl.isNotEmpty) {
    return customBaseUrl;
  }
  final preset = llmPresetById(provider);
  if (preset != null && preset.defaultBaseUrl.isNotEmpty) {
    return preset.defaultBaseUrl;
  }
  return null;
}

String? llmResolveModelName({required String? provider, String? modelName}) {
  final customModel = modelName?.trim();
  if (customModel != null && customModel.isNotEmpty) {
    return customModel;
  }
  final preset = llmPresetById(provider);
  if (preset != null && preset.defaultModel.isNotEmpty) {
    return preset.defaultModel;
  }
  return null;
}
