import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../models/attached_file.dart';

typedef OnSendCallback = void Function(String text, {List<String>? fileIds});

class MessageComposer extends ConsumerStatefulWidget {
  final bool isGenerating;
  final OnSendCallback onSend;
  final VoidCallback onStop;

  const MessageComposer({
    super.key,
    required this.isGenerating,
    required this.onSend,
    required this.onStop,
  });

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  final List<AttachedFile> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachedFiles.isEmpty) || widget.isGenerating) return;

    if (_attachedFiles.any((f) => f.isUploading)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏳ Fayllar serverga yuklanmoqda, kuting...'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final fileIds = _attachedFiles
        .where((f) => f.isUploaded)
        .map((f) => f.id!)
        .toList();

    final promptText = text.isEmpty && _attachedFiles.isNotEmpty
        ? 'Iltimos, ushbu biriktirilgan fayllarni tahlil qilib, asosiy ma\'lumotlarni tushuntirib bering.'
        : text;

    widget.onSend(promptText, fileIds: fileIds.isNotEmpty ? fileIds : null);
    _controller.clear();
    setState(() {
      _attachedFiles.clear();
    });
  }

  String _guessMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'application/octet-stream';
  }

  Future<void> _pickFiles({required bool isImagesOnly}) async {
    if (_attachedFiles.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitta xabarga ko\'pi bilan 5 ta fayl biriktirish mumkin.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final extensions = isImagesOnly
          ? ['jpg', 'jpeg', 'png', 'webp']
          : ['pdf', 'doc', 'docx', 'xlsx', 'xls', 'pptx', 'ppt', 'txt', 'md', 'csv', 'json'];

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: extensions,
      );

      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;

      for (final pf in result.files) {
        if (pf.path == null) continue;

        if (_attachedFiles.length >= 5) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bitta xabarga ko\'pi bilan 5 ta fayl biriktirish mumkin. Qolgan fayllar qo\'shilmadi.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
          break;
        }

        final attached = AttachedFile(
          name: pf.name,
          path: pf.path,
          sizeBytes: pf.size,
          mimeType: _guessMimeType(pf.name),
          isUploading: true,
        );

        setState(() {
          _attachedFiles.add(attached);
        });

        _uploadFile(attached);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fayl tanlashda xatolik: $e')),
      );
    }
  }

  Future<void> _uploadFile(AttachedFile file) async {
    if (file.path == null) return;
    final apiClient = ref.read(apiClientProvider);

    setState(() {
      final idx = _attachedFiles.indexWhere((f) => f.path == file.path);
      if (idx != -1) {
        _attachedFiles[idx] = file.copyWith(
          isUploading: true,
          errorMessage: null,
        );
      }
    });

    try {
      final resp = await apiClient.uploadFile(
        '/api/v1/files/upload',
        filePath: file.path!,
      );

      if (!mounted) return;

      String? fileId;
      if (resp is Map<String, dynamic>) {
        if (resp['id'] != null) {
          fileId = resp['id']?.toString();
        } else if (resp['file'] is Map<String, dynamic>) {
          fileId = (resp['file'] as Map<String, dynamic>)['id']?.toString();
        } else if (resp['data'] is Map<String, dynamic>) {
          final data = resp['data'] as Map<String, dynamic>;
          fileId = data['id']?.toString() ??
              (data['file'] is Map<String, dynamic>
                  ? (data['file'] as Map<String, dynamic>)['id']?.toString()
                  : null);
        }
      }

      if (fileId != null && fileId.isNotEmpty) {
        setState(() {
          final idx = _attachedFiles.indexWhere((f) => f.path == file.path);
          if (idx != -1) {
            _attachedFiles[idx] = file.copyWith(
              id: fileId,
              isUploading: false,
              errorMessage: null,
            );
          }
        });
      } else {
        throw 'Fayl ID qaytmadi';
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final idx = _attachedFiles.indexWhere((f) => f.path == file.path);
        if (idx != -1) {
          _attachedFiles[idx] = file.copyWith(
            isUploading: false,
            errorMessage: e.toString(),
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${file.name} yuklanmadi: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _removeFile(AttachedFile file) {
    setState(() {
      _attachedFiles.remove(file);
    });
  }

  void _showAttachmentMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.attach_file_rounded,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Fayl yoki Hujjat biriktirish',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'AI yordamchiga chuqur tahlil qilish uchun hujjat yoki rasm yuklang:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded,
                      color: Colors.redAccent, size: 24),
                ),
                title: const Text('Hujjatlar (PDF, DOCX, TXT, CSV)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Sahifama-sahifa RAG tahlili va manbalar',
                    style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles(isImagesOnly: false);
                },
              ),
              const Divider(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.image_rounded,
                      color: Colors.blueAccent, size: 24),
                ),
                title: const Text('Rasmlar (JPG, PNG, WEBP)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Vision modeli orqali vizual tushunish',
                    style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles(isImagesOnly: true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enhancePrompt() {
    final current = _controller.text.trim();
    if (current.isEmpty) {
      _showQuickPromptSheet();
      return;
    }

    String enhanced = current;
    final lower = current.toLowerCase();

    if (lower.contains('kod') ||
        lower.contains('dastur') ||
        lower.contains('python') ||
        lower.contains('flutter') ||
        lower.contains('sql')) {
      enhanced =
          'Quyidagi vazifa bo\'yicha toza, xavfsiz va to\'liq sharhlangan kod yozib bering. Har bir qismining ishlash mexanizmini va mumkin bo\'lgan xatoliklarni oldini olish yo\'llarini tushuntiring:\n\n$current';
    } else if (lower.contains('rezyume') ||
        lower.contains('cv') ||
        lower.contains('ish') ||
        lower.contains('xat')) {
      enhanced =
          'Quyidagi mavzu bo\'yicha zamonaviy, professional va yuqori taassurot qoldiruvchi namuna tayyorlab bering. Eng muhim yutuqlar, ko\'nikmalar va amaliy maslahatlarni ajratib ko\'rsating:\n\n$current';
    } else if (lower.contains('tarjima') ||
        lower.contains('ingliz') ||
        lower.contains('til')) {
      enhanced =
          'Quyidagi matnni ma\'nosini aniq saqlagan holda, tabiiy va adabiy uslubda tarjima qilib bering hamda undagi muhim iboralarni tushuntirib bering:\n\n$current';
    } else {
      enhanced =
          'Iltimos, quyidagi savolga batafsil, tushunarli va amaliy misollar bilan to\'liq javob bering. Asosiy tushunchalarni punktlar orqali ajratib ko\'rsating:\n\n$current';
    }

    setState(() {
      _controller.text = enhanced;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: enhanced.length),
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✨ Savolingiz professional shaklga boyitildi!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showQuickPromptSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF161B22) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Sehrli Prompt Yordamchisi',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Bir marta bosish bilan tayyor va samarali promptni kiriting:',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 14),
              _buildPromptOption(
                ctx,
                '✍️ Matnni tahrirlash',
                'Quyidagi matnimni imlo va uslubiy jihatdan tekshirib, yanada ravon qilib bering: ',
              ),
              _buildPromptOption(
                ctx,
                '💻 Kod tahlili va yozish',
                'Menga quyidagi vazifani yechish uchun optimal, xavfsiz va tushunarli kod yozib bering: ',
              ),
              _buildPromptOption(
                ctx,
                '🌍 Ingliz tilida suhbat',
                'Let\'s practice English conversation! Please ask me an engaging question and correct my mistakes.',
              ),
              _buildPromptOption(
                ctx,
                '💡 Innovatsion startap g\'oyalari',
                'Menga hozirgi kunda yuqori daromad keltiruvchi 3 ta zamonaviy startap g\'oyasini taklif qiling.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptOption(BuildContext ctx, String title, String prompt) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          _controller.text = prompt;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: prompt.length),
          );
        });
        _focusNode.requestFocus();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildFileChip(AttachedFile file, bool isDark) {
    IconData iconData = Icons.insert_drive_file_rounded;
    Color iconColor = AppColors.primary;

    if (file.isPdf) {
      iconData = Icons.picture_as_pdf_rounded;
      iconColor = Colors.redAccent;
    } else if (file.isDoc) {
      iconData = Icons.description_rounded;
      iconColor = Colors.blueAccent;
    } else if (file.isExcel) {
      iconData = Icons.table_view_rounded;
      iconColor = Colors.green;
    } else if (file.isPpt) {
      iconData = Icons.slideshow_rounded;
      iconColor = Colors.deepOrangeAccent;
    } else if (file.isImage) {
      iconData = Icons.image_rounded;
      iconColor = Colors.teal;
    } else if (file.isJson) {
      iconData = Icons.data_object_rounded;
      iconColor = Colors.amber;
    } else if (file.isCsvOrTable) {
      iconData = Icons.table_chart_rounded;
      iconColor = Colors.orangeAccent;
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2530) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: file.hasError
              ? AppColors.error
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 16, color: iconColor),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                Text(
                  file.formattedSize,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (file.isUploading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          else if (file.hasError)
            GestureDetector(
              onTap: () => _uploadFile(file),
              child: const Icon(Icons.refresh_rounded,
                  size: 16, color: AppColors.error),
            )
          else
            GestureDetector(
              onTap: () => _removeFile(file),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkComposer : AppColors.lightComposer,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Attached files horizontal row
            if (_attachedFiles.isNotEmpty) ...[
              Container(
                height: 48,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachedFiles.length,
                  itemBuilder: (context, index) =>
                      _buildFileChip(_attachedFiles[index], isDark),
                ),
              ),
            ],

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment Button
                IconButton(
                  icon: const Icon(Icons.attach_file_rounded),
                  tooltip: 'Fayl biriktirish (PDF, DOCX, Rasm)',
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  onPressed: widget.isGenerating ? null : _showAttachmentMenu,
                ),

                // Text Input Field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0D1117)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        prefixIcon: IconButton(
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.primary,
                            size: 19,
                          ),
                          tooltip: 'Sehrli takomillashtirgich',
                          onPressed: _enhancePrompt,
                        ),
                        suffixIcon: _hasText
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                onPressed: () => _controller.clear(),
                              )
                            : null,
                        hintText: _attachedFiles.isNotEmpty
                            ? 'Fayl haqida savol yozing...'
                            : 'Savolingizni yozing...',
                        hintStyle: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                          fontSize: 14,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 11,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send / Stop Button
                if (widget.isGenerating)
                  GestureDetector(
                    onTap: widget.onStop,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.error, width: 1.5),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.stop_rounded,
                          color: AppColors.error,
                          size: 24,
                        ),
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: (_hasText || _attachedFiles.isNotEmpty)
                        ? _handleSend
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_hasText || _attachedFiles.isNotEmpty)
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: (_hasText || _attachedFiles.isNotEmpty)
                              ? Colors.black
                              : (isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
