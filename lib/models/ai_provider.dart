enum AiProtocol { openai, gemini, anthropic }

class AiProvider {
  final String id;
  final String label;
  final String baseUrl;
  final String model;
  final AiProtocol protocol;

  const AiProvider({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.protocol,
  });

  static const List<AiProvider> all = <AiProvider>[
    AiProvider(
      id: 'openai',
      label: 'OpenAI (GPT)',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      protocol: AiProtocol.openai,
    ),
    AiProvider(
      id: 'gemini',
      label: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      model: 'gemini-2.0-flash',
      protocol: AiProtocol.gemini,
    ),
    AiProvider(
      id: 'anthropic',
      label: 'Anthropic Claude',
      baseUrl: 'https://api.anthropic.com',
      model: 'claude-3-5-sonnet-latest',
      protocol: AiProtocol.anthropic,
    ),
    AiProvider(
      id: 'groq',
      label: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'meta-llama/llama-4-scout-17b-16e-instruct',
      protocol: AiProtocol.openai,
    ),
    AiProvider(
      id: 'openrouter',
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openai/gpt-4o-mini',
      protocol: AiProtocol.openai,
    ),
    AiProvider(
      id: 'deepseek',
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
      protocol: AiProtocol.openai,
    ),
    AiProvider(
      id: 'ollama',
      label: 'Ollama (محلي)',
      baseUrl: 'http://127.0.0.1:11434/v1',
      model: 'llava',
      protocol: AiProtocol.openai,
    ),
    AiProvider(
      id: 'custom',
      label: 'مخصص (OpenAI-compatible)',
      baseUrl: '',
      model: '',
      protocol: AiProtocol.openai,
    ),
  ];

  static AiProvider byId(String id) {
    final key = id.trim().toLowerCase();
    for (final provider in all) {
      if (provider.id == key) return provider;
    }
    return all.first;
  }
}
