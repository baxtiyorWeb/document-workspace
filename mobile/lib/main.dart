import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/subscription/services/revenuecat_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RevenueCat SDK
  await RevenueCatService.instance.initialize();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FLUTTER_ERROR] ${details.exception}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PLATFORM_ERROR] $error');
    return true; // handled
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'Xatolik yuz berdi: ${details.exception}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ),
    );
  };

  runApp(const ProviderScope(child: AiChatApp()));
}
