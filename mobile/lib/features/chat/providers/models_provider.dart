import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/ai_model_dto.dart';

final selectedModelIdProvider = StateProvider<String>((ref) => 'nemotron-ultra');

final modelsListProvider = FutureProvider<List<AIModelDTO>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final authState = ref.watch(authProvider);

  if (authState.accessToken == null) return [];

  try {
    final res = await apiClient.get('/api/v1/models');
    if (res is List) {
      return res.map((item) => AIModelDTO.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  } catch (e) {
    // Return standard fallback models if offline or network error
    return const [
      AIModelDTO(
        id: 'nemotron-ultra',
        name: 'Nvidia Nemotron 550B',
        description: 'Eng kuchli 550B ochiq parametrli model (Bepul)',
        allowedPlans: ['free', 'pro'],
        maxContextTokens: 8192,
        maxOutputTokens: 2048,
        isFreeTier: true,
        isReasoning: false,
        isProOnly: false,
      ),
      AIModelDTO(
        id: 'cohere-code',
        name: 'Cohere North Mini Code',
        description: 'Dasturlash va tezkor kod tahlili (Bepul)',
        allowedPlans: ['free', 'pro'],
        maxContextTokens: 8192,
        maxOutputTokens: 2048,
        isFreeTier: true,
        isReasoning: false,
        isProOnly: false,
      ),
      AIModelDTO(
        id: 'nemotron-super',
        name: 'Nvidia Nemotron 120B Super',
        description: 'Mantiqiy fikrlash va chuqur tahlil (Pro)',
        allowedPlans: ['pro'],
        maxContextTokens: 16384,
        maxOutputTokens: 4096,
        isFreeTier: false,
        isReasoning: true,
        isProOnly: true,
      ),
      AIModelDTO(
        id: 'gpt-4o',
        name: 'GPT-4o Omni',
        description: 'Yuqori aniqlikdagi universal intellekt (Pro)',
        allowedPlans: ['pro'],
        maxContextTokens: 32768,
        maxOutputTokens: 4096,
        isFreeTier: false,
        isReasoning: false,
        isProOnly: true,
      ),
    ];
  }
});

final userEntitlementsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final authState = ref.watch(authProvider);

  if (authState.accessToken == null) return {};

  try {
    final res = await apiClient.get('/api/v1/me/entitlements');
    if (res is Map<String, dynamic>) {
      return res;
    }
  } catch (_) {}
  return {'plan_id': 'free', 'is_pro': false, 'daily_requests_remaining': 40};
});
