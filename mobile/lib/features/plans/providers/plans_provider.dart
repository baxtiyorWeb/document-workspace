import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../models/plan_model.dart';

final plansListProvider = FutureProvider<List<PlanModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);

  try {
    final res = await apiClient.get('/api/v1/plans');
    if (res is List) {
      return res.map((item) => PlanModel.fromJson(item as Map<String, dynamic>)).toList();
    }
  } catch (_) {}

  // Fallback plans if offline
  return const [
    PlanModel(
      id: 'free',
      name: 'Bepul (Free)',
      description: 'Boshlang\'ich bepul tarif',
      dailyRequests: 40,
      monthlyTokens: 100000,
      maxInputTokens: 4000,
      maxOutputTokens: 1024,
      maxActiveStreams: 1,
      allowedModels: ['nemotron-ultra', 'cohere-code'],
      priceUsdCents: 0,
      isActive: true,
    ),
    PlanModel(
      id: 'pro',
      name: 'Pro Obuna',
      description: 'Cheksiz sifat va premium modellar',
      dailyRequests: 400,
      monthlyTokens: 1000000,
      maxInputTokens: 32000,
      maxOutputTokens: 4096,
      maxActiveStreams: 3,
      allowedModels: ['nemotron-ultra', 'cohere-code', 'nemotron-super', 'gpt-4o'],
      priceUsdCents: 999,
      isActive: true,
    ),
  ];
});
