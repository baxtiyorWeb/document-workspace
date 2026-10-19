import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/chat/providers/chat_provider.dart';
import '../features/conversations/models/conversation.dart';
import '../features/conversations/providers/conversations_provider.dart';
import '../features/explore/presentation/explore_screen.dart';
import '../features/profile/presentation/profile_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _currentIndex = 0;

  void _onOpenConversation(Conversation conv) {
    ref.read(selectedConversationIdProvider.notifier).state = conv.id;
    ref.read(chatProvider.notifier).loadConversation(conv.id);
    setState(() => _currentIndex = 1);
  }

  void _onStartWithCategory(String prompt, String category) {
    ref.read(selectedConversationIdProvider.notifier).state = null;
    ref.read(chatProvider.notifier).startNewChat();
    ref.read(chatProvider.notifier).sendMessage(prompt, category: category);
    setState(() => _currentIndex = 1);
  }

  void _onOpenChat() {
    setState(() => _currentIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = [
      ExploreScreen(
        onOpenConversation: _onOpenConversation,
        onStartWithCategory: _onStartWithCategory,
        onOpenChat: _onOpenChat,
      ),
      ChatScreen(onBackToExplore: () => setState(() => _currentIndex = 0)),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(bottom: 12, top: 6, left: 24, right: 24),
        color: Colors.transparent,
        child: SafeArea(
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161B22) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(0, Icons.grid_view_rounded, 'Explore'),
                _buildNavItem(1, Icons.chat_bubble_rounded, 'Chat'),
                _buildNavItem(2, Icons.person_rounded, 'Profil'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
