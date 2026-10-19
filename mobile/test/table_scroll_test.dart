import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/presentation/widgets/markdown_view.dart';

void main() {
  testWidgets('20+ column markdown table renders with independent horizontal SingleChildScrollView', (tester) async {
    // Generate a 20+ column Markdown table
    final headers = List.generate(22, (i) => 'Ustun_${i + 1}');
    final row1 = List.generate(22, (i) => 'Qiymat_${i + 1}');
    final row2 = List.generate(22, (i) => 'Natija_${i + 1}');

    final md = StringBuffer();
    md.writeln('| ${headers.join(' | ')} |');
    md.writeln('| ${List.filled(22, '---').join(' | ')} |');
    md.writeln('| ${row1.join(' | ')} |');
    md.writeln('| ${row2.join(' | ')} |');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360, // Standard mobile device screen width constraint
            child: SingleChildScrollView(
              child: MarkdownView(content: md.toString()),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify MarkdownView rendered without exceptions
    expect(find.byType(MarkdownView), findsOneWidget);

    // Verify that a horizontal SingleChildScrollView was created specifically for the wide table
    final horizontalScrollFinder = find.byWidgetPredicate(
      (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrollFinder, findsOneWidget);

    // Verify first and second header text exist
    expect(find.text('Ustun_1'), findsOneWidget);
    expect(find.text('Ustun_2'), findsOneWidget);

    // Test horizontal drag on the table
    await tester.drag(horizontalScrollFinder, const Offset(-400, 0));
    await tester.pumpAndSettle();

    // After scrolling horizontally, deeper columns become visible
    expect(horizontalScrollFinder, findsOneWidget);
  });

  testWidgets('Sanitizes partial/unclosed streaming markdown tables gracefully', (tester) async {
    // Incomplete table during streaming
    const partialTable = '| Ustun 1 | Ustun 2 | Ustun 3 |\n| --- | --- |\n| Qator 1 | Qator 2';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownView(content: partialTable),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.byType(MarkdownView), findsOneWidget);
  });
}
