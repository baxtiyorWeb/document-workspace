import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../core/theme/app_colors.dart';

class MarkdownView extends StatelessWidget {
  final String content;

  const MarkdownView({super.key, required this.content});

  String _sanitizeMarkdown(String raw) {
    if (raw.isEmpty) return raw;

    String sanitized = raw;

    // 1. Balance unclosed code blocks
    final codeBlockMatches = RegExp(r'```').allMatches(sanitized);
    if (codeBlockMatches.length % 2 != 0) {
      sanitized += '\n```\n';
    }

    // 2. Sanitize incomplete streaming table rows if needed
    final lines = sanitized.split('\n');
    if (lines.isNotEmpty) {
      final lastLine = lines.last.trim();
      if (lastLine.startsWith('|') && !lastLine.endsWith('|')) {
        lines[lines.length - 1] = '$lastLine |';
        sanitized = lines.join('\n');
      }
    }

    return sanitized;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final processedContent = _sanitizeMarkdown(content);

    final markdownStyle = MarkdownStyleSheet(
      p: TextStyle(
        fontSize: 14.5,
        height: 1.5,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      h1: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      h2: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      h3: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      code: TextStyle(
        fontSize: 13,
        fontFamily: 'monospace',
        color: AppColors.primary,
        backgroundColor: isDark
            ? const Color(0xFF0D1117)
            : const Color(0xFFF1F5F9),
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF21262D)),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      blockquote: TextStyle(
        fontSize: 14,
        fontStyle: FontStyle.italic,
        color: isDark
            ? AppColors.darkTextSecondary
            : AppColors.lightTextSecondary,
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      listBullet: TextStyle(
        fontSize: 14,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      // Independent Horizontal Scrolling Table Configuration
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableScrollbarThumbVisibility: true,
      tableBorder: TableBorder.all(
        color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE),
        width: 1,
        borderRadius: BorderRadius.circular(8),
      ),
      tablePadding: const EdgeInsets.symmetric(vertical: 8),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      tableHead: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      tableBody: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      tableHeadAlign: TextAlign.left,
      tableVerticalAlignment: TableCellVerticalAlignment.middle,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarkdownBody(
          data: processedContent,
          selectable: true,
          styleSheet: markdownStyle,
          builders: {
            'code': _CodeElementBuilder(context, isDark: isDark),
          },
          onTapLink: (text, href, title) {},
        ),
      ],
    );
  }
}

class _CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  final bool isDark;

  _CodeElementBuilder(this.context, {required this.isDark});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final isCodeBlock =
        element.attributes.containsKey('class') || text.contains('\n');
    if (!isCodeBlock) {
      return null;
    }

    var language = '';
    final className = element.attributes['class'] ?? '';
    if (className.startsWith('language-')) {
      language = className.substring(9);
    }

    final codeText = text.trimRight();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(
                bottom: BorderSide(color: Color(0xFF30363D), width: 0.8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.isNotEmpty ? language.toLowerCase() : 'kod',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF8B949E),
                  ),
                ),
                Tooltip(
                  message: 'Kodni nusxalash',
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: codeText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📋 Kod nusxalandi!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: Color(0xFF8B949E),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Nusxalash',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8B949E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              codeText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.45,
                color: Color(0xFFE6EDF3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
