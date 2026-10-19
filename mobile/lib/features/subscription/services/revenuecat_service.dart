import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../core/config/revenuecat_config.dart';

class RevenueCatService {
  RevenueCatService._();
  static final RevenueCatService instance = RevenueCatService._();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initializes RevenueCat SDK exactly once.
  Future<void> initialize({String? initialAppUserId}) async {
    if (_isInitialized) return;
    if (!RevenueCatConfig.isPlatformSupported) {
      debugPrint('[RevenueCat] Platform unsupported, skipping initialization');
      return;
    }

    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      final configuration = PurchasesConfiguration(RevenueCatConfig.apiKey);
      if (initialAppUserId != null && initialAppUserId.trim().isNotEmpty) {
        configuration.appUserID = initialAppUserId.trim();
      }

      await Purchases.configure(configuration);
      _isInitialized = true;
      debugPrint('[RevenueCat] Successfully configured SDK with key ${RevenueCatConfig.apiKey.substring(0, 8)}...');
    } catch (e, stack) {
      debugPrint('[RevenueCat] Initialization failed: $e\n$stack');
      _isInitialized = false;
    }
  }

  /// Identifies the current user in RevenueCat using their authenticated database UUID.
  Future<CustomerInfo?> logIn(String userId) async {
    if (!_isInitialized || userId.trim().isEmpty) return null;
    try {
      final result = await Purchases.logIn(userId.trim());
      debugPrint('[RevenueCat] Logged in with user ID: $userId');
      return result.customerInfo;
    } catch (e) {
      debugPrint('[RevenueCat] logIn error: $e');
      return null;
    }
  }

  /// Logs out of RevenueCat (resets identity to an anonymous user).
  Future<CustomerInfo?> logOut() async {
    if (!_isInitialized) return null;
    try {
      final customerInfo = await Purchases.logOut();
      debugPrint('[RevenueCat] Logged out to anonymous user');
      return customerInfo;
    } catch (e) {
      debugPrint('[RevenueCat] logOut error: $e');
      return null;
    }
  }

  /// Retrieves the latest customer info.
  Future<CustomerInfo?> getCustomerInfo() async {
    if (!_isInitialized) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('[RevenueCat] getCustomerInfo error: $e');
      return null;
    }
  }

  /// Checks whether the user has an active Pro entitlement.
  bool hasProEntitlement(CustomerInfo? customerInfo) {
    if (customerInfo == null) return false;
    final active = customerInfo.entitlements.active;
    return active.containsKey(RevenueCatConfig.entitlementId);
  }

  /// Fetches the configured offerings and packages.
  Future<Offerings?> getOfferings() async {
    if (!_isInitialized) return null;
    try {
      return await Purchases.getOfferings();
    } catch (e) {
      debugPrint('[RevenueCat] getOfferings error: $e');
      return null;
    }
  }

  /// Purchases a specific package (e.g. Monthly, Yearly).
  Future<CustomerInfo> purchasePackage(Package package) async {
    if (!_isInitialized) {
      throw UnsupportedError('RevenueCat is not initialized');
    }
    final result = await Purchases.purchasePackage(package);
    return result.customerInfo;
  }

  /// Restores previous purchases across devices / reinstalls.
  Future<CustomerInfo> restorePurchases() async {
    if (!_isInitialized) {
      throw UnsupportedError('RevenueCat is not initialized');
    }
    return await Purchases.restorePurchases();
  }

  /// Presents the official RevenueCat paywall modal.
  Future<PaywallResult> presentPaywall() async {
    if (!_isInitialized) {
      return PaywallResult.error;
    }
    try {
      return await RevenueCatUI.presentPaywall();
    } catch (e) {
      debugPrint('[RevenueCat] presentPaywall error: $e');
      return PaywallResult.error;
    }
  }

  /// Adds a listener for real-time customer info changes.
  void addCustomerInfoUpdateListener(CustomerInfoUpdateListener listener) {
    if (_isInitialized) {
      Purchases.addCustomerInfoUpdateListener(listener);
    }
  }
}
