import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/models/attached_file.dart';
import 'package:mobile/features/chat/models/chat_message.dart';
import 'package:mobile/features/chat/presentation/widgets/markdown_view.dart';
import 'package:mobile/features/chat/presentation/widgets/message_bubble.dart';

void main() {
  group('AttachedFile Universal File Extension Tests', () {
    test('Correctly identifies XLSX and XLS files', () {
      const xlsx = AttachedFile(
        name: 'hisobot.xlsx',
        sizeBytes: 1024 * 50,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(xlsx.isExcel, isTrue);
      expect(xlsx.isPdf, isFalse);
      expect(xlsx.isDoc, isFalse);
      expect(xlsx.isPpt, isFalse);

      const xls = AttachedFile(
        name: 'malumot.xls',
        sizeBytes: 1024 * 20,
        mimeType: 'application/vnd.ms-excel',
      );
      expect(xls.isExcel, isTrue);
    });

    test('Correctly identifies PPTX and PPT files', () {
      const pptx = AttachedFile(
        name: 'prezentatsiya.pptx',
        sizeBytes: 1024 * 300,
        mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      );
      expect(pptx.isPpt, isTrue);
      expect(pptx.isExcel, isFalse);

      const ppt = AttachedFile(
        name: 'slaydlar.ppt',
        sizeBytes: 1024 * 150,
        mimeType: 'application/vnd.ms-powerpoint',
      );
      expect(ppt.isPpt, isTrue);
    });

    test('Correctly identifies JSON files', () {
      const jsonFile = AttachedFile(
        name: 'schema.json',
        sizeBytes: 1024 * 5,
        mimeType: 'application/json',
      );
      expect(jsonFile.isJson, isTrue);
      expect(jsonFile.isDoc, isFalse);
    });
  });

  group('MessageBubble Interaction Tests', () {
    testWidgets('Assistant message bubble displays retry and copy action buttons', (tester) async {
      bool retryClicked = false;

      final assistantMsg = ChatMessage(
        id: 'ast-1',
        conversationId: 'c-1',
        role: 'assistant',
        content: 'Bu AI tomonidan qaytarilgan javob matni.',
        status: 'completed',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: assistantMsg,
              onRetry: () => retryClicked = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Retry button check
      final retryFinder = find.byTooltip('Qayta yaratish');
      expect(retryFinder, findsOneWidget);
      await tester.tap(retryFinder);
      expect(retryClicked, isTrue);

      // Copy button check
      final copyFinder = find.byTooltip('Nusxalash');
      expect(copyFinder, findsOneWidget);
      await tester.tap(copyFinder);
      await tester.pumpAndSettle();
      // Snack bar feedback
      expect(find.text('Xabar nusxalandi'), findsOneWidget);
    });

    testWidgets('User message bubble displays edit and copy buttons in normal mode', (tester) async {
      bool editTriggered = false;

      final userMsg = ChatMessage(
        id: 'usr-1',
        conversationId: 'c-1',
        role: 'user',
        content: 'Original savol matni',
        status: 'completed',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: userMsg,
              onStartEdit: () => editTriggered = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final editFinder = find.byTooltip('Tahrirlash');
      expect(editFinder, findsOneWidget);
      await tester.tap(editFinder);
      expect(editTriggered, isTrue);
    });

    testWidgets('User message bubble switches to inline editing without modal dialog', (tester) async {
      String? savedContent;
      bool cancelCalled = false;

      final userMsg = ChatMessage(
        id: 'usr-2',
        conversationId: 'c-1',
        role: 'user',
        content: 'Eski xabar',
        status: 'completed',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: userMsg,
              isEditing: true, // inline edit mode active
              onSaveEdit: (newText) => savedContent = newText,
              onCancelEdit: () => cancelCalled = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Ensure no dialog is shown, TextField is rendered inline
      expect(find.byType(Dialog), findsNothing);
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      // Action buttons: "Saqlash" and "Bekor qilish"
      final saveBtn = find.text('Saqlash');
      final cancelBtn = find.text('Bekor qilish');
      expect(saveBtn, findsOneWidget);
      expect(cancelBtn, findsOneWidget);

      // Enter new text and tap Saqlash
      await tester.enterText(textFieldFinder, 'Yangi tahrirlangan savol');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(savedContent, 'Yangi tahrirlangan savol');

      // Test Cancel button
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();
      expect(cancelCalled, isTrue);
    });
  });

  group('MarkdownView Code Block Copying Tests', () {
    testWidgets('Code block in markdown renders copy button', (tester) async {
      const codeMarkdown = '''
Mana namuna kod:

```python
def salom():
    print("Salom dunyo!")
```
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownView(content: codeMarkdown),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify code language label and copy button are rendered
      expect(find.text('python'), findsOneWidget);
      expect(find.byTooltip('Kodni nusxalash'), findsOneWidget);
    });
  });
}
