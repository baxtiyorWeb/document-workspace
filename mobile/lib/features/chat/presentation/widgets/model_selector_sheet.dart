import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../plans/presentation/plans_screen.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../providers/models_provider.dart';

class ModelSelectorSheet extends ConsumerWidget {
  const ModelSelectorSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ModelSelectorSheet(),
    );
  }

  void _showUpgradeDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text('Pro Tarifiga O\'ting'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Ushbu model eng so\'nggi intellekt va kengaytirilgan imkoniyatlarga ega bo\'lib, Pro tarif foydalanuvchilari uchun ajratilgan.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              '• Kunlik 400 tagacha so\'rov\n'
              '• GPT-4o Omni va Nemotron 120B Super\n'
              '• 32,000 token gacha kengaytirilgan kontekst\n'
              '• Google Play Billing & RevenueCat orqali xavfsiz obuna',
              style: TextStyle(fontSize: 13, height: 1.5, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Keyinroq'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              PlansScreen.show(context);
            },
            child: const Text('Tariflarni ko\'rish'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              _presentPaywall(context, ref);
            },
            child: const Text('Obunani Rasmiylashtirish'),
          ),
        ],
      ),
    );
  }

  Future<void> _presentPaywall(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final isSuccess = await ref.read(subscriptionProvider.notifier).presentPaywall();
      if (isSuccess && context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.primary,
            content: Text('Tabriklaymiz! Pro obuna muvaffaqiyatli faollashtirildi.'),
          ),
        );
        ref.invalidate(userEntitlementsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Obuna oynasini ochishda xatolik: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modelsAsync = ref.watch(modelsListProvider);
    final selectedModelId = ref.watch(selectedModelIdProvider);
    final entitlementsAsync = ref.watch(userEntitlementsProvider);

    final isProUser = entitlementsAsync.value?['is_pro'] == true;

    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 32, left: 20, right: 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkScaffold : AppColors.lightScaffold,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AI Modelini Tanlang',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isProUser
                      ? Colors.amber.withOpacity(0.2)
                      : AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isProUser ? 'PRO TARIF' : 'BEPUL TARIF',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isProUser ? Colors.amber[800] : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Go AI Gateway tomonidan boshqariladigan neyrotarmoqlar',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 20),
          modelsAsync.when(
            data: (models) => ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: models.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final model = models[i];
                final isSelected = model.id == selectedModelId;
                final isLocked = model.isProOnly && !isProUser;

                return InkWell(
                  onTap: () {
                    if (isLocked) {
                      Navigator.pop(ctx);
                      _showUpgradeDialog(context, ref);
                      return;
                    }
                    ref.read(selectedModelIdProvider.notifier).state = model.id;
                    Navigator.pop(ctx);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.lightCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isLocked
                                ? Colors.grey.withOpacity(0.15)
                                : AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isLocked
                                ? Icons.lock_outline_rounded
                                : (model.isReasoning ? Icons.psychology_rounded : Icons.auto_awesome_rounded),
                            color: isLocked ? Colors.grey : AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    model.displayName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (model.isProOnly)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'PRO',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'BEPUL',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                model.displaySubtitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22),
                      ],
                    ),
                  ),
                );
              },
            ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Center(
              child: Text('Modellarni yuklashda xatolik: $err'),
            ),
          ),
        ],
      ),
    );
  }
}
