import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../chat/providers/models_provider.dart';
import '../../subscription/presentation/payment_bottom_sheet.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../models/plan_model.dart';
import '../providers/plans_provider.dart';

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlansScreen()),
    );
  }

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  bool _isLoading = false;

  void _openCheckout(bool isPro) {
    PaymentBottomSheet.show(context, isPro: isPro);
  }

  Future<void> _handleRestore() async {
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final isRestored = await ref.read(subscriptionProvider.notifier).restore();
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (isRestored) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.primary,
            content: Text('Xaridlar muvaffaqiyatli tiklandi!'),
          ),
        );
        ref.invalidate(userEntitlementsProvider);
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Faol xaridlar topilmadi.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Xaridlarni tiklashda xatolik: $e')),
        );
      }
    }
  }

  Future<void> _handleResetToFree() async {
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final success = await ref.read(subscriptionProvider.notifier).resetToFree();
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Bepul tarifga o\'tkazildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        messenger.showSnackBar(SnackBar(content: Text('Xatolik: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final plansAsync = ref.watch(plansListProvider);
    final entitlementsAsync = ref.watch(userEntitlementsProvider);
    final subState = ref.watch(subscriptionProvider);

    final isProUser = subState.isPro || (entitlementsAsync.value?['is_pro'] == true);
    final remainingRequests =
        entitlementsAsync.value?['daily_requests_remaining'] ?? 40;
    final dailyLimit = entitlementsAsync.value?['daily_requests_limit'] ?? 40;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarif Rejalari'),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _handleRestore,
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Tiklash', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
      body: plansAsync.when(
        data: (plans) {
          final freePlan = plans.firstWhere(
            (p) => !p.isPro,
            orElse: () => const PlanModel(
              id: 'free',
              name: 'Bepul (Free)',
              description: 'Boshlang\'ich tarif',
              dailyRequests: 40,
              monthlyTokens: 100000,
              maxInputTokens: 4000,
              maxOutputTokens: 1024,
              maxActiveStreams: 1,
              allowedModels: ['nemotron-ultra', 'cohere-code'],
              priceUsdCents: 0,
              isActive: true,
            ),
          );

          final proPlan = plans.firstWhere(
            (p) => p.isPro,
            orElse: () => const PlanModel(
              id: 'pro',
              name: 'Pro Obuna',
              description: 'Cheksiz sifat va premium modellar',
              dailyRequests: 400,
              monthlyTokens: 1000000,
              maxInputTokens: 32000,
              maxOutputTokens: 4096,
              maxActiveStreams: 3,
              allowedModels: [
                'nemotron-ultra',
                'cohere-code',
                'nemotron-super',
                'gpt-4o'
              ],
              priceUsdCents: 999,
              isActive: true,
            ),
          );

          final ultraPlan = plans.firstWhere(
            (p) => p.id == 'ultra',
            orElse: () => const PlanModel(
              id: 'ultra',
              name: 'Ultra Obuna',
              description: 'Maksimal professional imkoniyatlar',
              dailyRequests: 1200,
              monthlyTokens: 30000000,
              maxInputTokens: 128000,
              maxOutputTokens: 8192,
              maxActiveStreams: 10,
              allowedModels: [],
              priceUsdCents: 2499,
              isActive: true,
            ),
          );

          final isUltraUser = entitlementsAsync.value?['plan_id'] == 'ultra';

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Header description
              Text(
                'AI IMKONIYATLARINI OCHING',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'O\'zingizga mos tarifni tanlang. Istalgan vaqtda Google Play orqali yangilash yoki bekor qilish mumkin.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),

              const SizedBox(height: 16),

              // Current Status Badge Card
              Material(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: isUltraUser
                        ? Colors.deepPurpleAccent.withOpacity(0.5)
                        : (isProUser
                            ? Colors.amber.withOpacity(0.5)
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder)),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isUltraUser
                              ? Colors.deepPurpleAccent.withOpacity(0.15)
                              : (isProUser
                                  ? Colors.amber.withOpacity(0.15)
                                  : AppColors.primary.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isUltraUser
                              ? Icons.diamond_rounded
                              : (isProUser
                                  ? Icons.workspace_premium_rounded
                                  : Icons.check_circle_outline_rounded),
                          color: isUltraUser
                              ? Colors.deepPurpleAccent
                              : (isProUser ? Colors.amber : AppColors.primary),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUltraUser
                                  ? 'Sizning tarifingiz: ULTRA'
                                  : (isProUser ? 'Sizning tarifingiz: PRO' : 'Sizning tarifingiz: BEPUL'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bugungi limit: $remainingRequests / $dailyLimit so\'rov qoldi',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Plan 1: Free Card
              _buildPlanCard(
                context: context,
                plan: freePlan,
                isCurrentPlan: !isProUser && !isUltraUser,
                isHighlighted: false,
                features: const [
                  'Kunlik 40 ta tezkor savol-javob',
                  '10 MB gacha hujjatlar va PDF tahlili',
                  'Rasmlar va vizual ma\'lumotlarni tushunish',
                  'Suhbatlar tarixi va kontekst xotirasi',
                  'Standart server navbati',
                ],
                buttonText: !isProUser && !isUltraUser ? 'Joriy Faol Reja' : 'Bepul Tarifga O\'tish (Test)',
                onPressed: (isProUser || isUltraUser) ? _handleResetToFree : null,
              ),

              const SizedBox(height: 20),

              // Plan 2: Pro Card (Highlighted)
              _buildPlanCard(
                context: context,
                plan: proPlan,
                isCurrentPlan: isProUser && !isUltraUser,
                isHighlighted: true,
                badgeText: 'ENG TAVSIYA ETILADI',
                features: const [
                  'Kunlik 400 ta so\'rov (10 barobar ko\'proq)',
                  'Ilg\'or fikrlash va chuqur tahlil intellekti',
                  '50 MB gacha katta hujjatlar va PDF tahlili',
                  'Sahifama-sahifa aniq manbalar (Citations)',
                  'Bir vaqtning o\'zida 3 ta parallel suhbat',
                  'Yuqori server ustuvorligi (Tezkor javoblar)',
                ],
                buttonText: isProUser && !isUltraUser
                    ? 'Joriy Faol Reja'
                    : 'Pro Tarifini Tanlash (\$9.99 / oy)',
                isLoading: _isLoading,
                onPressed: () => _openCheckout(true),
              ),

              const SizedBox(height: 20),

              // Plan 3: Ultra Card
              _buildPlanCard(
                context: context,
                plan: ultraPlan,
                isCurrentPlan: isUltraUser,
                isHighlighted: false,
                badgeText: 'PROFESSIONAL',
                features: const [
                  'Kunlik 1,200 ta cheksiz darajadagi so\'rov',
                  '200 MB gacha ulkan hajmdagi hujjatlar va kitoblar',
                  'To\'liq multimodal (hujjat, rasm va media tahlili)',
                  'Bir vaqtning o\'zida 10 ta parallel oqim',
                  'Eng yuqori navbat ustuvorligi (Zero-wait queue)',
                  'Maksimal kontekst hajmi va chuqur qidiruv',
                ],
                buttonText: isUltraUser
                    ? 'Joriy Faol Reja'
                    : 'Ultra Tarifini Tanlash (\$24.99 / oy)',
                isLoading: _isLoading,
                onPressed: () => _openCheckout(false),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Tariflarni yuklashda xatolik: $err')),
      ),
    );
  }

  Widget _buildPlanCard({
    required BuildContext context,
    required PlanModel plan,
    required bool isCurrentPlan,
    required bool isHighlighted,
    String? badgeText,
    required List<String> features,
    required String buttonText,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isHighlighted
          ? (isDark ? const Color(0xFF1E2620) : const Color(0xFFF0FAF4))
          : (isDark ? AppColors.darkCard : AppColors.lightCard),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isHighlighted
              ? AppColors.primary
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: isHighlighted ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (badgeText != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  plan.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  plan.priceFormatted,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isHighlighted ? AppColors.primary : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              plan.description,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            ...features.map(
              (feat) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: isHighlighted ? AppColors.primary : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        feat,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (isCurrentPlan && !plan.isPro)
              OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(buttonText),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isHighlighted ? AppColors.primary : Colors.grey[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isLoading ? null : onPressed,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        buttonText,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
