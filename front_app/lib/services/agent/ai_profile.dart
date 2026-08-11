final class AiProviderProfile {
  const AiProviderProfile({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.requiresCredential,
  }) : assert(id != ''),
       assert(provider != ''),
       assert(displayName != ''),
       assert(baseUrl != ''),
       assert(model != '');

  final String id;
  final String provider;
  final String displayName;
  final String baseUrl;
  final String model;
  final bool requiresCredential;

  factory AiProviderProfile.fromJson(Map<String, Object?> json) {
    return AiProviderProfile(
      id: _requiredString(json, 'id'),
      provider: _requiredString(json, 'provider'),
      displayName: _requiredString(json, 'displayName'),
      baseUrl: _requiredString(json, 'baseUrl'),
      model: _requiredString(json, 'model'),
      requiresCredential: _requiredBool(json, 'requiresCredential'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider,
    'displayName': displayName,
    'baseUrl': baseUrl,
    'model': model,
    'requiresCredential': requiresCredential,
  };

  @override
  bool operator ==(Object other) {
    return other is AiProviderProfile &&
        other.id == id &&
        other.provider == provider &&
        other.displayName == displayName &&
        other.baseUrl == baseUrl &&
        other.model == model &&
        other.requiresCredential == requiresCredential;
  }

  @override
  int get hashCode => Object.hash(
    id,
    provider,
    displayName,
    baseUrl,
    model,
    requiresCredential,
  );
}

final class AiProviderPreset {
  const AiProviderPreset({
    required this.provider,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.requiresCredential,
  });

  final String provider;
  final String displayName;
  final String baseUrl;
  final String model;
  final bool requiresCredential;

  AiProviderProfile toProfile({
    required String id,
    String? displayName,
    String? baseUrl,
    String? model,
  }) {
    return AiProviderProfile(
      id: id,
      provider: provider,
      displayName: displayName ?? this.displayName,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      requiresCredential: requiresCredential,
    );
  }
}

const aiProviderPresets = <AiProviderPreset>[
  AiProviderPreset(
    provider: 'deepseek',
    displayName: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    requiresCredential: true,
  ),
  AiProviderPreset(
    provider: 'openai',
    displayName: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    requiresCredential: true,
  ),
  AiProviderPreset(
    provider: 'moonshot',
    displayName: 'Kimi (Moonshot)',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
    requiresCredential: true,
  ),
  AiProviderPreset(
    provider: 'zhipu',
    displayName: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
    requiresCredential: true,
  ),
  AiProviderPreset(
    provider: 'ollama',
    displayName: 'Ollama（本地）',
    baseUrl: 'http://localhost:11434/v1',
    model: 'llama3',
    requiresCredential: false,
  ),
  AiProviderPreset(
    provider: 'custom',
    displayName: '自定义',
    baseUrl: '',
    model: '',
    requiresCredential: true,
  ),
];

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty || value != value.trim()) {
    throw FormatException('Invalid AI profile $key');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('Invalid AI profile $key');
  }
  return value;
}
