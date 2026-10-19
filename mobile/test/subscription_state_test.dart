import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/revenuecat_config.dart';
import 'package:mobile/features/subscription/models/subscription_state.dart';

void main() {
  group('RevenueCat Configuration Tests', () {
    test('Verifies default Entitlement identifier matches RevenueCat dashboard', () {
      expect(
        RevenueCatConfig.entitlementId,
        equals('cognidoc_ai_document_analyzer_and_chatbot_pro'),
      );
    });

    test('Verifies Google Play subscriptions URL format', () {
      expect(
        RevenueCatConfig.googlePlaySubscriptionsUrl,
        contains('play.google.com/store/account/subscriptions'),
      );
      expect(
        RevenueCatConfig.googlePlaySubscriptionsUrl,
        contains('com.aichat.app.mobile'),
      );
    });
  });

  group('SubscriptionState Model Tests', () {
    test('SubscriptionState default initial values', () {
      const state = SubscriptionState();

      expect(state.status, equals(SubscriptionStatus.uninitialized));
      expect(state.isPro, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.isPurchasing, isFalse);
      expect(state.isRestoring, isFalse);
      expect(state.customerInfo, isNull);
      expect(state.offerings, isNull);
      expect(state.errorMessage, isNull);
      expect(state.expirationDate, isNull);
    });

    test('SubscriptionState copyWith updates fields correctly', () {
      const initial = SubscriptionState();
      final expiry = DateTime.now().add(const Duration(days: 30));

      final updated = initial.copyWith(
        status: SubscriptionStatus.active,
        isPro: true,
        expirationDate: expiry,
      );

      expect(updated.status, equals(SubscriptionStatus.active));
      expect(updated.isPro, isTrue);
      expect(updated.expirationDate, equals(expiry));
      expect(updated.isLoading, isFalse);
    });

    test('SubscriptionState helper getters reflect status correctly', () {
      const loadingState = SubscriptionState(status: SubscriptionStatus.loading);
      expect(loadingState.isLoading, isTrue);

      const purchasingState = SubscriptionState(status: SubscriptionStatus.purchasing);
      expect(purchasingState.isPurchasing, isTrue);

      const restoringState = SubscriptionState(status: SubscriptionStatus.restoring);
      expect(restoringState.isRestoring, isTrue);
    });
  });
}
