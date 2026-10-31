import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/revenuecat_config.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/subscription_provider.dart';

class PaymentBottomSheet extends ConsumerStatefulWidget {
  final bool initialIsPro;

  const PaymentBottomSheet({
    super.key,
    this.initialIsPro = false,
  });

  static Future<void> show(BuildContext context, {bool isPro = false}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PaymentBottomSheet(initialIsPro: isPro),
    );
  }

  @override
  ConsumerState<PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends ConsumerState<PaymentBottomSheet> {
  // Selected plan: 'monthly', 'yearly', 'lifetime'
  String _selectedPlan = 'yearly';
  bool _isProcessing = false;

  double get _currentPlanPrice {
    switch (_selectedPlan) {
      case 'monthly':
        return 9.99;
      case 'yearly':
        return 79.99;
      case 'lifetime':
        return 149.99;
      default:
        return 9.99;
    }
  }

  Future<void> _handleGooglePlayPayment() async {
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final success =
          await ref.read(subscriptionProvider.notifier).presentPaywall();
      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (success) {
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.primary,
            content: Text('Google Play xaridi muvaffaqiyatli yakunlandi!'),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Xarid jarayoni yakunlanmadi yoki bekor qilindi.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Google Play xatoligi: $e'),
          ),
        );
      }
    }
  }

  Future<void> _handleRestorePurchases() async {
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final success =
          await ref.read(subscriptionProvider.notifier).restore();
      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (success) {
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.primary,
            content: Text('Avvalgi xaridlaringiz muvaffaqiyatli tiklandi!'),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Faol obuna yoki xaridlar topilmadi.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Tiklashda xatolik: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C2128) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 14),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title & Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'CogniDoc AI Pro',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Pro Features List
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF161B22)
                          : const Color(0xFFF6F8FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Column(
                      children: const [
                        _FeatureRow(
                          icon: Icons.flash_on_rounded,
                          text: 'GPT-4o, Claude 3.5 Sonnet va DeepSeek R1',
                        ),
                        SizedBox(height: 8),
                        _FeatureRow(
                          icon: Icons.upload_file_rounded,
                          text: '50MB gacha hujjatlar, PDF, Excel va rasmlar tahlili',
                        ),
                        SizedBox(height: 8),
                        _FeatureRow(
                          icon: Icons.speed_rounded,
                          text: 'Kuniga 400 tagacha so\'rov va ustuvor yuqori tezlik',
                        ),
                        SizedBox(height: 8),
                        _FeatureRow(
                          icon: Icons.security_rounded,
                          text: 'Reklamasiz, to\'liq maxfiy va shifrlangan arxiv',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Plans Selection (Monthly, Yearly, Lifetime)
                  Row(
                    children: [
                      _buildPlanOption(
                        id: 'monthly',
                        title: 'Oylik',
                        price: '\$9.99',
                        period: 'oyiga',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildPlanOption(
                        id: 'yearly',
                        title: 'Yillik',
                        price: '\$79.99',
                        period: 'yiliga',
                        badge: 'TEJAMKOR',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildPlanOption(
                        id: 'lifetime',
                        title: 'Umrbod',
                        price: '\$149.99',
                        period: 'bir martalik',
                        isDark: isDark,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Google Play Trust & Security Notice
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF21262D) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.verified_user_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Google Play xavfsiz to\'lov tizimi orqali himoyalangan. Istalgan vaqtda Google Play orqali bekor qilish mumkin.',
                            style: TextStyle(fontSize: 11.5, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Primary Google Play Purchase Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isProcessing ? null : _handleGooglePlayPayment,
                    icon: _isProcessing
                        ? const SizedBox.shrink()
                        : const Icon(Icons.shop_two_rounded, size: 22),
                    label: _isProcessing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Google Play orqali ulanish (\$${_currentPlanPrice.toStringAsFixed(2)})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),

                  const SizedBox(height: 12),

                  // Restore Purchases & Manage Subscription
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _isProcessing ? null : _handleRestorePurchases,
                        icon: const Icon(Icons.restore_rounded, size: 16),
                        label: const Text(
                          'Xaridlarni tiklash',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(
                              text: RevenueCatConfig.googlePlaySubscriptionsUrl,
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Obunani boshqarish havolasi nusxalandi!'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const Text(
                          'Obunani boshqarish',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Terms & Privacy Notice (Google Play Mandatory Footnote)
                  const Center(
                    child: Text(
                      'Xaridni tasdiqlash bilan siz Maxfiylik siyosati va Foydalanish shartlariga rozilik bildirasiz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanOption({
    required String id,
    required String title,
    required String price,
    required String period,
    String? badge,
    required bool isDark,
  }) {
    final isSelected = _selectedPlan == id;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlan = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.12)
                : (isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                const SizedBox(height: 15),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                period,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}
