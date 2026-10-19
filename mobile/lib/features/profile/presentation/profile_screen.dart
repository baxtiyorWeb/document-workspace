import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/models_provider.dart';
import '../../plans/presentation/plans_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../subscription/presentation/payment_bottom_sheet.dart';
import '../../subscription/providers/subscription_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hisobdan chiqish'),
        content: const Text('Haqiqatan ham hisobingizdan chiqmoqchimisiz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            child: const Text('Chiqish'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hisobni o\'chirish'),
        content: const Text(
          'Hisobingiz va barcha ma\'lumotlaringiz butunlay o\'chiriladi. Bu amalni ortga qaytarib bo\'lmaydi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Xavfsizlik yuzasidan qo\'llab-quvvatlash xizmatiga murojaat qiling.'),
                ),
              );
            },
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entitlementsAsync = ref.watch(userEntitlementsProvider);
    final subState = ref.watch(subscriptionProvider);
    final isProUser =
        subState.isPro || (entitlementsAsync.value?['is_pro'] == true);
    final planName = entitlementsAsync.value?['plan_name'] as String? ??
        (isProUser ? 'Pro Obuna' : 'Bepul (Free)');
    final remaining =
        entitlementsAsync.value?['daily_requests_remaining'] ?? 40;
    final dailyLimit =
        entitlementsAsync.value?['daily_requests_limit'] ?? 40;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mening Profilim'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // 1. User Info Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: Text(
                    user?.fullName.isNotEmpty == true
                        ? user!.fullName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user?.fullName.isNotEmpty == true
                                  ? user!.fullName
                                  : 'Foydalanuvchi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isProUser
                                  ? Colors.amber.withOpacity(0.15)
                                  : AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isProUser ? 'PRO' : 'FREE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isProUser ? Colors.amber : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
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

          const SizedBox(height: 20),

          // 2. Plan and Subscription Management
          Text(
            'TARIF VA OBUNA',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isProUser
                    ? Colors.amber.withOpacity(0.5)
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isProUser
                              ? Icons.workspace_premium_rounded
                              : Icons.star_border_rounded,
                          color: isProUser ? Colors.amber : AppColors.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          planName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 0),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PlansScreen()),
                        );
                      },
                      child: const Text('Tariflar jadvali'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: dailyLimit > 0
                      ? (remaining / dailyLimit).clamp(0.0, 1.0)
                      : 1.0,
                  backgroundColor: isDark
                      ? const Color(0xFF30363D)
                      : const Color(0xFFE2E8F0),
                  color: isProUser ? Colors.amber : AppColors.primary,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 6),
                Text(
                  'Bugungi qolgan so\'rovlar: $remaining / $dailyLimit',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                if (!isProUser) ...[
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => PaymentBottomSheet.show(context, isPro: true),
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text(
                      'Pro Tarifga O\'tish',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 3. Settings Navigation Menu Tile (Settings inside Profile)
          Text(
            'ILOVA SOZLAMALARI',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.settings_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              title: Text(
                'Sozlamalar va Konfiguratsiya',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              subtitle: Text(
                'API manzili, ko\'rinish mavzusi va ovoz effektlari',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey,
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // 4. Security & Account Actions
          Text(
            'XAVFSIZLIK VA HISOB AMALLARI',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                  title: const Text(
                    'Hisobdan chiqish',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                  onTap: () => _showLogoutDialog(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.grey,
                    size: 20,
                  ),
                  title: const Text(
                    'Hisobni butunlay o\'chirish',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey,
                    ),
                  ),
                  onTap: () => _showDeleteAccountDialog(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
