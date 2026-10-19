import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/ui_sound_feedback.dart';
import '../../auth/providers/auth_provider.dart';
import '../../plans/presentation/plans_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../models/conversation.dart';
import '../providers/conversations_provider.dart';

class ConversationsDrawer extends ConsumerWidget {
  final Function(Conversation) onSelectConversation;
  final VoidCallback onNewChat;

  const ConversationsDrawer({
    super.key,
    required this.onSelectConversation,
    required this.onNewChat,
  });

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    Conversation conv,
  ) {
    final controller = TextEditingController(text: conv.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suhbat nomini o\'zgartirish'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Yangi sarlavha...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                await ref
                    .read(conversationsProvider.notifier)
                    .updateTitle(conv.id, newTitle);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    Conversation conv,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suhbatni o\'chirish'),
        content: Text(
          '"${conv.title}" suhbati va undagi barcha xabarlar o\'chiriladi. Ushbu amalni ortga qaytarib bo\'lmaydi.',
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
              await ref
                  .read(conversationsProvider.notifier)
                  .deleteConversation(conv.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final selectedId = ref.watch(selectedConversationIdProvider);
    final authState = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The Go-getters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // New Chat Action Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ElevatedButton.icon(
                onPressed: () {
                  UiSoundFeedback.playActionClick();
                  Navigator.pop(context);
                  onNewChat();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Yangi suhbat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            const Divider(),

            // Conversation List
            Expanded(
              child: conversationsAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_outlined,
                            size: 40,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Suhbatlar tarixi bo\'sh',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: items.length,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = item.id == selectedId;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: isSelected
                              ? (isDark
                                    ? AppColors.darkBorder
                                    : AppColors.lightBorder)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            side: isSelected
                                ? BorderSide(
                                    color: AppColors.primary.withOpacity(0.5),
                                  )
                                : BorderSide.none,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          leading: Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 18,
                            color: isSelected
                                ? AppColors.primary
                                : (isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary),
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                          subtitle: Text(
                            DateFormatter.formatConversationTime(
                              item.lastMessageAt,
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              size: 16,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                            onSelected: (val) {
                              if (val == 'rename') {
                                _showRenameDialog(context, ref, item);
                              } else if (val == 'delete') {
                                _showDeleteDialog(context, ref, item);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 16),
                                    SizedBox(width: 8),
                                    Text('Nomlash'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'O\'chirish',
                                      style: TextStyle(color: AppColors.error),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            UiSoundFeedback.playItemClick();
                            Navigator.pop(context);
                            onSelectConversation(item);
                          },
                        ),
                      ),
                    );
                  },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error),
                        const SizedBox(height: 8),
                        Text(
                          'Suhbatlarni yuklashda xatolik: $e',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => ref
                              .read(conversationsProvider.notifier)
                              .loadConversations(),
                          child: const Text('Qayta urinish'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Plan Selection & Pro Upgrade Shortcut
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: InkWell(
                onTap: () {
                  Navigator.pop(context);
                  PlansScreen.show(context);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E2620) : const Color(0xFFF0FAF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Tariflar & Pro Obuna',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 12, color: isDark ? Colors.white54 : Colors.black45),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(),

            // User Info & Settings Footer
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withOpacity(0.2),
                    child: Text(
                      authState.user?.fullName.isNotEmpty == true
                          ? authState.user!.fullName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authState.user?.fullName ?? 'Foydalanuvchi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        Text(
                          authState.user?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 20),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
