class AIModelDTO {
  final String id;
  final String name;
  final String description;
  final List<String> allowedPlans;
  final int maxContextTokens;
  final int maxOutputTokens;
  final bool isFreeTier;
  final bool isReasoning;
  final bool isProOnly;

  const AIModelDTO({
    required this.id,
    required this.name,
    required this.description,
    required this.allowedPlans,
    required this.maxContextTokens,
    required this.maxOutputTokens,
    required this.isFreeTier,
    required this.isReasoning,
    required this.isProOnly,
  });

  factory AIModelDTO.fromJson(Map<String, dynamic> json) {
    return AIModelDTO(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      allowedPlans: (json['allowed_plans'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      maxContextTokens: json['max_context_tokens'] as int? ?? 8192,
      maxOutputTokens: json['max_output_tokens'] as int? ?? 2048,
      isFreeTier: json['is_free_tier'] as bool? ?? false,
      isReasoning: json['is_reasoning'] as bool? ?? false,
      isProOnly: json['is_pro_only'] as bool? ?? false,
    );
  }

  String get displayName {
    switch (id) {
      case 'gpt-4o':
      case 'nemotron-super':
        return 'Chuqur Tahlil & Intellekt';
      case 'cohere-code':
        return 'Dasturlash & Mantiq';
      case 'gpt-4o-mini':
        return 'Tezkor & Samarali';
      case 'deepseek-r1':
        return 'Ilg\'or Mulohaza (Reasoning)';
      case 'claude-3-5-sonnet':
        return 'Hujjatlar & Yozuv Eksperti';
      case 'nemotron-ultra':
      default:
        return 'Umumiy Intellekt';
    }
  }

  String get displaySubtitle {
    switch (id) {
      case 'gpt-4o':
      case 'nemotron-super':
        return 'Murakkab savollar, chuqur tahlil va mantiqiy xulosalar';
      case 'cohere-code':
        return 'Dasturlash tillari, algoritmlar va xatolarni tuzatish';
      case 'gpt-4o-mini':
        return 'Kundalik tezkor savol-javoblar va umumiy vazifalar';
      case 'deepseek-r1':
        return 'Bosqichma-bosqich chuqur mulohaza yuritish';
      case 'claude-3-5-sonnet':
        return 'Katta matnlar, ilmiy maqolalar va tahrirlash';
      case 'nemotron-ultra':
      default:
        return 'Kundalik savol-javoblar va umumiy yordam';
    }
  }
}
