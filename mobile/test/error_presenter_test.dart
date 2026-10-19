import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/error_presenter.dart';

void main() {
  group('PresentableError sanitization and mapping tests', () {
    test('Sanitizes network exceptions into actionable Uzbek message', () {
      final err1 = PresentableError.fromRaw('SocketException: OS Error: Connection refused, errno = 111');
      expect(err1.code, 'NETWORK_ERROR');
      expect(err1.message, "Internet bilan aloqa uzildi. Qayta urinib ko'ring.");
      expect(err1.actionLabel, "Qayta urinish");
      expect(err1.actionType, ErrorActionType.retry);
      expect(err1.severity, ErrorSeverity.warning);

      final err2 = PresentableError.fromRaw('ClientException: Failed host lookup: api.example.com');
      expect(err2.code, 'NETWORK_ERROR');
      expect(err2.actionType, ErrorActionType.retry);
    });

    test('Sanitizes 5-file count limit error', () {
      final err = PresentableError.fromRaw('FILE_COUNT_LIMIT_EXCEEDED: maximum 5 files allowed');
      expect(err.code, 'FILE_COUNT_LIMIT_EXCEEDED');
      expect(err.message, contains("ko'pi bilan 5 ta fayl"));
      expect(err.actionType, ErrorActionType.none);
      expect(err.severity, ErrorSeverity.warning);
    });

    test('Sanitizes file size limit error', () {
      final err = PresentableError.fromRaw('FILE_TOO_LARGE: uploaded file exceeds 25MB limit');
      expect(err.code, 'FILE_TOO_LARGE');
      expect(err.message, "Hujjat juda katta. Uni qismlarga ajratib yuboring.");
      expect(err.actionType, ErrorActionType.splitFile);
    });

    test('Sanitizes unreadable or unsupported file format error', () {
      final err = PresentableError.fromRaw('UNSUPPORTED_FORMAT: corrupt or unknown header');
      expect(err.code, 'UNSUPPORTED_FORMAT');
      expect(err.message, "Faylni o'qib bo'lmadi. Boshqa fayl tanlang.");
      expect(err.actionLabel, "Boshqa fayl");
      expect(err.actionType, ErrorActionType.selectOtherFile);
    });

    test('Sanitizes quota exceeded error without leaking backend trace', () {
      final err = PresentableError.fromRaw('QUOTA_EXCEEDED: tier monthly message limit reached for user');
      expect(err.code, 'QUOTA_EXCEEDED');
      expect(err.message, "Foydalanish limiti tugadi. Keyinroq urinib ko'ring.");
      expect(err.actionType, ErrorActionType.upgradePlan);
    });

    test('Sanitizes internal server error and stack traces safely', () {
      const rawTrace = '''
goroutine 12 [running]:
internal/files.ExtractXLSXContent(...)
    /app/backend/internal/files/parsers.go:342 +0x12a
runtime.gopanic(...)
''';
      final err = PresentableError.fromRaw(rawTrace);
      expect(err.message, "So'rov vaqtincha bajarilmadi. Qayta urinishingiz mumkin.");
      expect(err.message, isNot(contains("goroutine")));
      expect(err.message, isNot(contains("ExtractXLSXContent")));
    });
  });

  group('InlineErrorBanner Widget Tests', () {
    testWidgets('Renders error banner with message and actionable buttons', (tester) async {
      bool actionPressed = false;
      bool dismissPressed = false;

      final error = PresentableError(
        id: 'err-test-1',
        code: 'NETWORK_ERROR',
        message: "Internet bilan aloqa uzildi. Qayta urinib ko'ring.",
        severity: ErrorSeverity.warning,
        actionLabel: "Qayta urinish",
        actionType: ErrorActionType.retry,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                InlineErrorBanner(
                  error: error,
                  onAction: () => actionPressed = true,
                  onDismiss: () => dismissPressed = true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify message
      expect(find.text("Internet bilan aloqa uzildi. Qayta urinib ko'ring."), findsOneWidget);

      // Verify action button exists and works
      final actionBtn = find.text("Qayta urinish");
      expect(actionBtn, findsOneWidget);
      await tester.tap(actionBtn);
      expect(actionPressed, isTrue);

      // Verify dismiss button exists and works
      final dismissBtn = find.byTooltip('Xabarni yopish');
      expect(dismissBtn, findsOneWidget);
      await tester.tap(dismissBtn);
      expect(dismissPressed, isTrue);
    });

    testWidgets('Renders empty space when error is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InlineErrorBanner(error: null),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);
    });
  });
}
