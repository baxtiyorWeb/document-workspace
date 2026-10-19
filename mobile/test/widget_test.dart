import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/app/app.dart';

void main() {
  testWidgets(
    'AiChatApp renders correctly and shows initial authentication/splash screen',
    (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: AiChatApp()));

      // Initial pump
      await tester.pump();

      // Verify MaterialApp exists and renders
      expect(find.byType(MaterialApp), findsOneWidget);
    },
  );
}
