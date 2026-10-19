import 'dart:io';
import 'package:flutter/foundation.dart';

class RevenueCatConfig {
  RevenueCatConfig._();

  // Public SDK Keys (Never store secret keys in the client app)
  static const String _androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: 'test_cIFXbSPHrdQEoAnMrJseRTRiPDP',
  );

  static const String _iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: 'test_cIFXbSPHrdQEoAnMrJseRTRiPDP',
  );

  // Authoritative Entitlement Identifier configured in RevenueCat dashboard
  static const String entitlementId = 'cognidoc_ai_document_analyzer_and_chatbot_pro';

  // Package identifiers
  static const String packageMonthly = 'monthly';
  static const String packageYearly = 'yearly';
  static const String packageLifetime = 'lifetime';

  // Google Play subscription management deep link
  static const String googlePlaySubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions?package=com.aichat.app.mobile';

  static String get apiKey {
    if (kIsWeb) {
      throw UnsupportedError('RevenueCat in-app purchases are not supported on Web');
    }
    if (Platform.isAndroid) {
      return _androidApiKey;
    } else if (Platform.isIOS || Platform.isMacOS) {
      return _iosApiKey;
    }
    throw UnsupportedError('Platform ${Platform.operatingSystem} is not supported by RevenueCat');
  }

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }
}
