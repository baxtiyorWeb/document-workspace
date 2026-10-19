import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/models/chat_message.dart';
import 'package:mobile/features/chat/presentation/widgets/message_bubble.dart';

void main() {
  testWidgets('MessageBubble displays sequential status during pipeline processing', (tester) async {
    final stages = [
      'Fayl tekshirilmoqda',
      'Hujjat ochilmoqda',
      'Sahifalar va jadvallar tahlil qilinmoqda',
      'Kerakli ma\'lumotlar qidirilmoqda',
      'Javob tayyorlanmoqda',
    ];

    for (final stage in stages) {
      final msg = ChatMessage(
        id: 'test_asst',
        conversationId: 'conv_1',
        role: 'assistant',
        content: '',
        status: 'streaming',
        statusText: stage,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(message: msg),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Verify each real backend status text is displayed
      expect(find.text(stage), findsOneWidget);
    }
  });

  testWidgets('MessageBubble switches from status text to markdown when tokens arrive', (tester) async {
    final streamingMsg = ChatMessage(
      id: 'test_asst',
      conversationId: 'conv_1',
      role: 'assistant',
      content: 'Salom, hisobot muvaffaqiyatli tahlil qilindi.',
      status: 'streaming',
      statusText: null,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: streamingMsg),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Salom, hisobot muvaffaqiyatli tahlil qilindi.'), findsOneWidget);
    expect(find.text('Javob tayyorlanmoqda'), findsNothing);
  });
}
