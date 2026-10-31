import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../models/chat_message.dart';
import 'markdown_view.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isEditing;
  final bool isGenerating;
  final VoidCallback? onStartEdit;
  final VoidCallback? onCancelEdit;
  final Function(String newText)? onSaveEdit;
  final VoidCallback? onRetry;
  final Future<void> Function(String reason, String comment)? onReport;

  const MessageBubble({
    super.key,
    required this.message,
    this.isEditing = false,
    this.isGenerating = false,
    this.onStartEdit,
    this.onCancelEdit,
    this.onSaveEdit,
    this.onRetry,
    this.onReport,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  late TextEditingController _editController;
  final FocusNode _editFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.message.content);
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isEditing && widget.isEditing) {
      _editController.text = widget.message.content;
      _editFocusNode.requestFocus();
    } else if (oldWidget.message.content != widget.message.content && !widget.isEditing) {
      _editController.text = widget.message.content;
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Xabar nusxalandi'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleSaveEdit() {
    final trimmed = _editController.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Xabar matni bo\'sh bo\'lishi mumkin emas'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    widget.onSaveEdit?.call(trimmed);
  }

  void _showReportDialog(BuildContext context) {
    if (widget.onReport == null) return;
    String selectedReason = 'harmful_content';
    final commentController = TextEditingController();

    final reasons = [
      {'key': 'harmful_content', 'label': 'Zararli yoki xavfli kontent'},
      {'key': 'offensive_content', 'label': 'Haqoratomuz yoki odobsiz javob'},
      {'key': 'inaccurate_content', 'label': 'Noto\'g\'ri yoki chalg\'ituvchi ma\'lumot'},
      {'key': 'copyright_violation', 'label': 'Mualliflik huquqining buzilishi'},
      {'key': 'other', 'label': 'Boshqa muammo'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.flag_outlined, color: AppColors.error, size: 22),
                SizedBox(width: 8),
                Text('AI javobi ustidan shikoyat', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ushbu AI xabari qanday qoidabuzarlikka ega?',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  ...reasons.map((r) {
                    final isSelected = selectedReason == r['key'];
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          selectedReason = r['key']!;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 18,
                              color: isSelected ? AppColors.primary : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r['label']!,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Qo\'shimcha izoh (ixtiyoriy)...',
                      hintStyle: const TextStyle(fontSize: 12),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1E2530)
                          : const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Bekor qilish'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await widget.onReport!(selectedReason, commentController.text.trim());
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Shikoyat qabul qilindi. Moderatsiya ko\'rib chiqadi.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Shikoyat yuborishda xatolik yuz berdi'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Yuborish'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.message.isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkBubbleUser
                    : AppColors.lightBubbleUser,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
                border: Border.all(
                  color: isDark
                      ? AppColors.primary.withOpacity(0.3)
                      : AppColors.primary.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.message.hasFiles) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.attach_file_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.message.fileIds.length} ta biriktirilgan fayl',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Inline Edit Mode
                  if (widget.isEditing) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF161B22)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.2,
                        ),
                      ),
                      child: TextField(
                        controller: _editController,
                        focusNode: _editFocusNode,
                        maxLines: null,
                        minLines: 2,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.all(10),
                          border: InputBorder.none,
                          hintText: 'Xabarni tahrirlang...',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: widget.onCancelEdit,
                          child: Text(
                            'Bekor qilish',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _handleSaveEdit,
                          icon: const Icon(Icons.check_rounded, size: 14),
                          label: const Text(
                            'Saqlash',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Normal display mode
                    SelectableText(
                      widget.message.content,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormatter.formatMessageTime(
                            widget.message.createdAt,
                          ),
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        if (widget.onStartEdit != null) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Tahrirlash',
                            child: Semantics(
                              label: 'Xabarni tahrirlash',
                              button: true,
                              child: InkWell(
                                onTap: widget.isGenerating
                                    ? null
                                    : widget.onStartEdit,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(3.0),
                                  child: Icon(
                                    Icons.edit_outlined,
                                    size: 13,
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Tooltip(
                          message: 'Nusxalash',
                          child: Semantics(
                            label: 'Xabarni nusxalash',
                            button: true,
                            child: InkWell(
                              onTap: () => _copyToClipboard(
                                context,
                                widget.message.content,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(3.0),
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 13,
                                  color: isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Assistant Message
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkBubbleAssistant
              : AppColors.lightBubbleAssistant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message.content.isEmpty && widget.message.isStreaming) ...[
              if (widget.message.statusText != null &&
                  widget.message.statusText!.isNotEmpty)
                _SequentialStatusWidget(
                  statusText: widget.message.statusText!,
                  isDark: isDark,
                )
              else
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Javob tayyorlanmoqda...',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
            ] else ...[
              MarkdownView(content: widget.message.content),
            ],

            if (widget.message.hasCitations) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF161B22)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Hujjat manbalari',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: widget.message.citations.map((c) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Actions row (copy, status badge, retry)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.message.isCancelled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'To\'xtatilgan',
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 10,
                      ),
                    ),
                  )
                else if (widget.message.isFailed)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Xatolik',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      if (widget.onRetry != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: widget.isGenerating ? null : widget.onRetry,
                          child: const Text(
                            'Qayta urinish',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  const SizedBox(),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Retry icon action on every completed assistant message
                    if (!widget.message.isStreaming && widget.onRetry != null) ...[
                      Semantics(
                        label: 'Javobni qayta yaratish',
                        button: true,
                        child: IconButton(
                          icon: Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: widget.isGenerating
                                ? (isDark
                                    ? AppColors.darkTextSecondary.withOpacity(0.4)
                                    : AppColors.lightTextSecondary.withOpacity(0.4))
                                : (isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary),
                          ),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          tooltip: 'Qayta yaratish',
                          onPressed:
                              widget.isGenerating ? null : widget.onRetry,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    if (widget.message.content.isNotEmpty) ...[
                      Semantics(
                        label: 'Xabarni nusxalash',
                        button: true,
                        child: IconButton(
                          icon: Icon(
                            Icons.copy_rounded,
                            size: 15,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Nusxalash',
                          onPressed: () => _copyToClipboard(
                            context,
                            widget.message.content,
                          ),
                        ),
                      ),
                      if (widget.onReport != null && !widget.message.isStreaming) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          label: 'Shikoyat qilish',
                          button: true,
                          child: IconButton(
                            icon: Icon(
                              Icons.flag_outlined,
                              size: 15,
                              color: isDark
                                  ? AppColors.darkTextSecondary.withOpacity(0.7)
                                  : AppColors.lightTextSecondary.withOpacity(0.7),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Shikoyat qilish',
                            onPressed: () => _showReportDialog(context),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SequentialStatusWidget extends StatelessWidget {
  final String statusText;
  final bool isDark;

  const _SequentialStatusWidget({
    required this.statusText,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Text(
              statusText,
              key: ValueKey<String>(statusText),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
