import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../core/config/revenuecat_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/models_provider.dart';
import '../models/subscription_state.dart';
import '../services/revenuecat_service.dart';

final subscriptionServiceProvider = Provider<RevenueCatService>((ref) {
  return RevenueCatService.instance;
});

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier(ref);
});

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final Ref _ref;
  final RevenueCatService _service = RevenueCatService.instance;

  SubscriptionNotifier(this._ref) : super(const SubscriptionState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(status: SubscriptionStatus.loading);

    final authState = _ref.read(authProvider);
    final userId = authState.user?.id;

    await _service.initialize(initialAppUserId: userId);

    if (!_service.isInitialized) {
      state = state.copyWith(
        status: SubscriptionStatus.inactive,
        isPro: false,
      );
      return;
    }

    _service.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

    await refresh();
  }

  /// Refreshes both CustomerInfo and Offerings.
  Future<void> refresh() async {
    try {
      final info = await _service.getCustomerInfo();
      final offerings = await _service.getOfferings();
      _updateFromCustomerInfo(info, offerings: offerings);
    } catch (e) {
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void _onCustomerInfoUpdated(CustomerInfo customerInfo) {
    debugPrint('[RevenueCat] CustomerInfo updated in real-time');
    _updateFromCustomerInfo(customerInfo);
    _syncWithBackend(customerInfo);
  }

  void _updateFromCustomerInfo(CustomerInfo? info, {Offerings? offerings}) {
    if (info == null) {
      state = state.copyWith(
        status: SubscriptionStatus.inactive,
        isPro: false,
        offerings: offerings ?? state.offerings,
      );
      return;
    }

    final hasPro = _service.hasProEntitlement(info);
    final ent = info.entitlements.active[RevenueCatConfig.entitlementId];
    DateTime? expDate;
    if (ent?.expirationDate != null) {
      try {
        expDate = DateTime.parse(ent!.expirationDate!);
      } catch (_) {}
    }

    state = state.copyWith(
      status: hasPro ? SubscriptionStatus.active : SubscriptionStatus.inactive,
      isPro: hasPro,
      customerInfo: info,
      offerings: offerings ?? state.offerings,
      expirationDate: expDate,
    );
  }

  /// Synchronizes subscription state with the backend PostgreSQL database.
  Future<void> _syncWithBackend(CustomerInfo info) async {
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated) return;

    final hasPro = _service.hasProEntitlement(info);
    final ent = info.entitlements.active[RevenueCatConfig.entitlementId];

    DateTime? expDate;
    if (ent?.expirationDate != null) {
      try {
        expDate = DateTime.parse(ent!.expirationDate!);
      } catch (_) {}
    }

    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(
        '/api/v1/billing/sync',
        body: {
          'original_transaction_id': ent?.originalPurchaseDate ?? info.originalAppUserId,
          'product_id': ent?.productIdentifier ?? 'pro',
          'entitlement_id': RevenueCatConfig.entitlementId,
          'is_active': hasPro,
          'expiration_date': expDate?.toIso8601String(),
          'store': ent?.store.name ?? 'play_store',
        },
      );
      // Invalidate backend entitlements provider so all limits update immediately
      _ref.invalidate(userEntitlementsProvider);
    } catch (e) {
      debugPrint('[RevenueCat] Sync with backend error: $e');
    }
  }

  /// Presents the official RevenueCat paywall.
  Future<bool> presentPaywall() async {
    state = state.copyWith(status: SubscriptionStatus.purchasing);
    try {
      final result = await _service.presentPaywall();
      final isPurchased = result == PaywallResult.purchased || result == PaywallResult.restored;

      await refresh();

      if (state.customerInfo != null) {
        await _syncWithBackend(state.customerInfo!);
      }

      state = state.copyWith(
        status: state.isPro ? SubscriptionStatus.active : SubscriptionStatus.inactive,
      );
      return isPurchased;
    } catch (e) {
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Purchases a specific package directly.
  Future<bool> purchase(Package package) async {
    state = state.copyWith(status: SubscriptionStatus.purchasing);
    try {
      final customerInfo = await _service.purchasePackage(package);
      _updateFromCustomerInfo(customerInfo);
      await _syncWithBackend(customerInfo);
      return state.isPro;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('[RevenueCat] User cancelled purchase');
        state = state.copyWith(
          status: state.isPro ? SubscriptionStatus.active : SubscriptionStatus.inactive,
        );
        return false;
      }
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: 'To\'lov xatosi: $e',
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: 'To\'lov xatosi: $e',
      );
      return false;
    }
  }

  /// Restores previous purchases.
  Future<bool> restore() async {
    state = state.copyWith(status: SubscriptionStatus.restoring);
    try {
      final customerInfo = await _service.restorePurchases();
      _updateFromCustomerInfo(customerInfo);
      await _syncWithBackend(customerInfo);
      return state.isPro;
    } catch (e) {
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: 'Xaridlarni tiklashda xatolik: $e',
      );
      return false;
    }
  }

  /// Alias for restore()
  Future<bool> restorePurchases() => restore();

  /// Manually activates Pro subscription via backend synchronization (Card / Sandbox / Test purchase)
  Future<bool> purchaseManual({
    required String productId,
    String store = 'card_payment',
    String? last4,
  }) async {
    state = state.copyWith(status: SubscriptionStatus.purchasing);
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated) {
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: 'To\'lov qilish uchun tizimga kirgan bo\'lishingiz kerak',
      );
      return false;
    }

    try {
      final now = DateTime.now();
      DateTime expiration;
      if (productId.contains('yearly')) {
        expiration = now.add(const Duration(days: 365));
      } else if (productId.contains('lifetime')) {
        expiration = now.add(const Duration(days: 36500)); // 100 years
      } else {
        expiration = now.add(const Duration(days: 30)); // 1 month
      }

      final txId = 'tx_card_${now.millisecondsSinceEpoch}_${last4 ?? "8600"}';
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(
        '/api/v1/billing/sync',
        body: {
          'original_transaction_id': txId,
          'product_id': productId,
          'entitlement_id': RevenueCatConfig.entitlementId,
          'is_active': true,
          'expiration_date': expiration.toIso8601String(),
          'store': store,
        },
      );

      state = state.copyWith(
        status: SubscriptionStatus.active,
        isPro: true,
        expirationDate: expiration,
      );

      _ref.invalidate(userEntitlementsProvider);
      return true;
    } catch (e) {
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: 'To\'lovni faollashtirishda xatolik: $e',
      );
      return false;
    }
  }

  /// Resets the user's subscription to Free (useful for re-testing billing)
  Future<bool> resetToFree() async {
    state = state.copyWith(status: SubscriptionStatus.loading);
    try {
      final authState = _ref.read(authProvider);
      if (!authState.isAuthenticated) return false;

      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(
        '/api/v1/billing/sync',
        body: {
          'original_transaction_id': 'reset_${DateTime.now().millisecondsSinceEpoch}',
          'product_id': 'free',
          'entitlement_id': RevenueCatConfig.entitlementId,
          'is_active': false,
          'store': 'system',
        },
      );

      state = state.copyWith(
        status: SubscriptionStatus.inactive,
        isPro: false,
        expirationDate: null,
      );

      _ref.invalidate(userEntitlementsProvider);
      return true;
    } catch (e) {
      debugPrint('[SubscriptionNotifier] resetToFree error: $e');
      state = state.copyWith(
        status: SubscriptionStatus.error,
        errorMessage: 'Obunani bekor qilishda xatolik: $e',
      );
      return false;
    }
  }
}
