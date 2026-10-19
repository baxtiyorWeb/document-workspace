import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/revenuecat_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../chat/providers/models_provider.dart';
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

class _PaymentBottomSheetState extends ConsumerState<PaymentBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected plan: 'monthly', 'yearly', 'lifetime'
  String _selectedPlan = 'yearly';

  // Card controllers
  final _cardNumberController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvcController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvcController.dispose();
    _cardHolderController.dispose();
    super.dispose();
  }

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

  String get _currentPlanTitle {
    switch (_selectedPlan) {
      case 'monthly':
        return 'Oylik Pro Obuna';
      case 'yearly':
        return 'Yillik Pro Obuna (33% chegirma)';
      case 'lifetime':
        return 'Umrbod Pro Obuna';
      default:
        return 'Pro Obuna';
    }
  }

  void _fillTestCard() {
    setState(() {
      _cardNumberController.text = '8600 5214 7890 3412';
      _cardExpiryController.text = '12/28';
      _cardCvcController.text = '777';
      _cardHolderController.text = 'FOYDALANUVCHI';
    });
  }

  Future<void> _handleCardPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);
    final cleanCard = _cardNumberController.text.replaceAll(' ', '');
    final last4 = cleanCard.length >= 4 ? cleanCard.substring(cleanCard.length - 4) : '8600';

    try {
      final success = await ref.read(subscriptionProvider.notifier).purchaseManual(
            productId: 'pro-$_selectedPlan',
            store: 'card_payment',
            last4: last4,
          );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (success) {
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'To\'lov qabul qilindi! $_currentPlanTitle muvaffaqiyatli faollashtirildi.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('To\'lovni amalga oshirishda xatolik yuz berdi.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
        );
      }
    }
  }

  Future<void> _handleGooglePlayPayment() async {
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final success = await ref.read(subscriptionProvider.notifier).presentPaywall();
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
          SnackBar(
            backgroundColor: Colors.orange.shade800,
            content: const Text(
              'Google Play xaridi amalga oshmadi. Agar ilova testing rejimida bo\'lsa, "Bank kartasi" bo\'limi orqali to\'lovni sinab ko\'rishingiz mumkin.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(
          SnackBar(content: Text('Xatolik: $e')),
        );
      }
    }
  }

  Future<void> _handleResetToFree() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Obunani bekor qilish'),
        content: const Text(
          'Haqiqatan ham obunani bekor qilib, qaytadan bepul rejimga o\'tmoqchimisiz? (Bu orqali to\'lov oqimini qaytadan sinab ko\'rishingiz mumkin).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ortga'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ha, bekor qilish', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final success = await ref.read(subscriptionProvider.notifier).resetToFree();
      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (success) {
        Navigator.pop(context);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Obuna bekor qilindi. Bepul tarifga o\'tkazildi.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        messenger.showSnackBar(SnackBar(content: Text('Xatolik: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subState = ref.watch(subscriptionProvider);
    final entitlementsAsync = ref.watch(userEntitlementsProvider);
    final isPro = subState.isPro || (entitlementsAsync.value?['is_pro'] == true);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2124) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPro ? 'Pro Obuna Boshqaruvi' : 'Pro Tarifga O\'tish',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          isPro ? 'Sizda faol obuna mavjud' : 'To\'lov turini tanlang',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          const Divider(height: 20),

          // Active Pro Banner / Reset Option if already Pro
          if (isPro)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Colors.amber, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Siz hozirda faol PRO foydalanuvchisiz! Qayta sinov uchun bepulga o\'tishingiz mumkin.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _isProcessing ? null : _handleResetToFree,
                    child: const Text('Qaytarish', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ],
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Plan Selectors
                  const Text(
                    'TARIF MUDDATINI TANLANG',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      _buildPlanOption(
                        id: 'monthly',
                        title: 'Oylik',
                        price: '\$9.99',
                        period: '/ oy',
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildPlanOption(
                        id: 'yearly',
                        title: 'Yillik',
                        price: '\$79.99',
                        period: '/ yil',
                        badge: '33% CHEGIRMA',
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

                  // Tab Bar for Payment Methods
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark ? Colors.white70 : Colors.black87,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.credit_card_rounded, size: 20),
                          text: 'Bank Kartasi',
                        ),
                        Tab(
                          icon: Icon(Icons.shop_two_rounded, size: 20),
                          text: 'Google Play',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tab Views
                  SizedBox(
                    height: 380,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // TAB 1: Card Entry Form
                        _buildCardPaymentView(isDark),

                        // TAB 2: Google Play Billing View
                        _buildGooglePlayView(isDark),
                      ],
                    ),
                  ),
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
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.12)
                : (isDark ? const Color(0xFF262A2E) : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                )
              else
                const SizedBox(height: 18),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.primary : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Text(
                period,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardPaymentView(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Karta ma\'lumotlari (Real / Test)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _fillTestCard,
                icon: const Icon(Icons.flash_on_rounded, size: 16, color: Colors.amber),
                label: const Text('Sinov kartasi', style: TextStyle(fontSize: 12, color: Colors.amber)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Card Number
          TextFormField(
            controller: _cardNumberController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(16),
              _CardNumberInputFormatter(),
            ],
            decoration: InputDecoration(
              hintText: '8600 0000 0000 0000',
              labelText: 'Karta raqami',
              prefixIcon: const Icon(Icons.credit_card_rounded),
              filled: true,
              fillColor: isDark ? const Color(0xFF282C31) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            validator: (v) {
              final clean = (v ?? '').replaceAll(' ', '');
              if (clean.length < 16) return '16 xonali karta raqamini kiriting';
              return null;
            },
          ),

          const SizedBox(height: 12),

          // Expiry and CVC
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _cardExpiryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                    _CardExpiryInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    hintText: '12/28',
                    labelText: 'Muddati (MM/YY)',
                    prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF282C31) : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 5) return 'MM/YY kiriting';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _cardCvcController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    hintText: '123',
                    labelText: 'CVV / CVC',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF282C31) : Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 3) return 'CVC kiriting';
                    return null;
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Cardholder Name
          TextFormField(
            controller: _cardHolderController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'ISM FAMILIYA',
              labelText: 'Karta egasi',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              filled: true,
              fillColor: isDark ? const Color(0xFF282C31) : Colors.grey.shade100,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Karta egasini kiriting';
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Pay Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _isProcessing ? null : _handleCardPayment,
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'To\'lash (\$${_currentPlanPrice.toStringAsFixed(2)})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGooglePlayView(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF282C31) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.shop_two_rounded, color: AppColors.primary, size: 22),
                  SizedBox(width: 8),
                  Text('Google Play Billing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Google Play orqali xarid qilish uchun ilova Google Play Console tizimida testing relizida bo\'lishi kerak. Google Play\'ga ulangan kartangiz orqali 1-bosishda to\'lov qilinadi.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _isProcessing ? null : _handleGooglePlayPayment,
          icon: const Icon(Icons.shopping_bag_rounded, size: 20),
          label: _isProcessing
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  'Google Play orqali xarid (\$${_currentPlanPrice.toStringAsFixed(2)})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
        ),

        const SizedBox(height: 16),

        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: RevenueCatConfig.googlePlaySubscriptionsUrl));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Google Play obuna boshqarish havolasi nusxalandi!')),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Google Play boshqaruv havolasini olish'),
        ),
      ],
    );
  }
}

/// Formatter for Card Number (groups of 4 digits: 8600 0000 0000 0000)
class _CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final clean = newValue.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      buffer.write(clean[i]);
      if ((i + 1) % 4 == 0 && (i + 1) != clean.length) {
        buffer.write(' ');
      }
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Formatter for Card Expiry Date (MM/YY)
class _CardExpiryInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final clean = newValue.text.replaceAll('/', '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      buffer.write(clean[i]);
      if (i == 1 && clean.length > 2) {
        buffer.write('/');
      }
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
