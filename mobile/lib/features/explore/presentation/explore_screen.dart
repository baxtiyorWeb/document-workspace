import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ui_sound_feedback.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/presentation/widgets/hero_chat_bubble.dart';
import '../../conversations/models/conversation.dart';
import '../../conversations/presentation/conversations_drawer.dart';
import '../../profile/presentation/profile_screen.dart';
import '../models/explore_category.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  final Function(Conversation) onOpenConversation;
  final Function(String starterText, String category) onStartWithCategory;
  final VoidCallback onOpenChat;

  const ExploreScreen({
    super.key,
    required this.onOpenConversation,
    required this.onStartWithCategory,
    required this.onOpenChat,
  });

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userName = authState.user?.fullName.split(' ').first ?? 'Do\'stim';

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 80.0,
      onDrawerChanged: (isOpen) {
        if (isOpen) {
          UiSoundFeedback.playDrawerOpen();
        } else {
          UiSoundFeedback.playDrawerClose();
        }
      },
      drawer: ConversationsDrawer(
        onSelectConversation: widget.onOpenConversation,
        onNewChat: widget.onOpenChat,
      ),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Top App Bar: Left = Product Name, Right = Menu icon, Far right = User/Profile icon
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Product Branding & Name
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'The Go-getters AI',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                      ],
                    ),

                    // Right: Menu Bar & Far right: User Profile Icon
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Menu bar icon (opens drawer / history navigation)
                        Semantics(
                          label: 'Menyu',
                          button: true,
                          child: IconButton(
                            icon: const Icon(Icons.menu_rounded, size: 22),
                            tooltip: 'Menyu',
                            onPressed: () {
                              UiSoundFeedback.playDrawerOpen();
                              _scaffoldKey.currentState?.openDrawer();
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Far right: User Profile Avatar (opens Profile & Settings)
                        Semantics(
                          label: 'Foydalanuvchi profili',
                          button: true,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ProfileScreen(),
                                ),
                              );
                            },
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor:
                                      AppColors.primary.withOpacity(0.18),
                                  child: Text(
                                    userName.isNotEmpty
                                        ? userName[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.darkScaffold
                                            : AppColors.lightScaffold,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // Hero Bubble "Hi, [Name] / Tap to chat"
            SliverToBoxAdapter(
              child: HeroChatBubble(
                userName: userName,
                onTap: widget.onOpenChat,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // Smart AI Quick Tools Feature Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.bolt_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Tezkor AI Asboblar',
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
                        Text(
                          '1 marta bosish',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 110,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildQuickToolCard(
                            icon: Icons.edit_note_rounded,
                            title: 'Matn Tahriri',
                            subtitle: 'Imlo va uslubiy sayqallash',
                            color: const Color(0xFF3B82F6),
                            isDark: isDark,
                            onTap: () => widget.onStartWithCategory(
                              'Iltimos, quyidagi matnimni imlo va uslubiy jihatdan tekshirib, yanada ravon va professional qilib bering:\n\n',
                              'Writing',
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildQuickToolCard(
                            icon: Icons.code_rounded,
                            title: 'Kod Yordamchisi',
                            subtitle: 'Algoritm va bug tuzatish',
                            color: const Color(0xFF10B981),
                            isDark: isDark,
                            onTap: () => widget.onStartWithCategory(
                              'Menga quyidagi vazifani yechish uchun optimal va toza kod yozib bering:\n\n',
                              'Coding',
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildQuickToolCard(
                            icon: Icons.translate_rounded,
                            title: 'Ingliz Tili Repetitor',
                            subtitle: 'Erkin suhbat va grammatika',
                            color: const Color(0xFF8B5CF6),
                            isDark: isDark,
                            onTap: () => widget.onStartWithCategory(
                              'Let\'s practice conversational English! Please ask me a question and correct any mistakes I make.',
                              'Language',
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildQuickToolCard(
                            icon: Icons.lightbulb_outline_rounded,
                            title: 'G\'oyalar Generatori',
                            subtitle: 'Startap va loyiha rejalari',
                            color: const Color(0xFFF59E0B),
                            isDark: isDark,
                            onTap: () => widget.onStartWithCategory(
                              'Menga zamonaviy va talab yuqori bo\'lgan innovatsion loyiha g\'oyalarini taklif qiling.',
                              'Brainstorming',
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildQuickToolCard(
                            icon: Icons.description_outlined,
                            title: 'Rezyume & CV',
                            subtitle: 'Professional namuna yaratish',
                            color: const Color(0xFFEC4899),
                            isDark: isDark,
                            onTap: () => widget.onStartWithCategory(
                              'Menga IT sohasida vakansiyaga mos kuchli, professional rezyume (CV) tuzish bo\'yicha namuna bering.',
                              'Career',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Explore Section Title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Explore',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    Text(
                      'Bo\'limlar',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // 2-Column Category Grid
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final cat = ExploreCategory.categories[index];

                  return GestureDetector(
                    onTap: () {
                      UiSoundFeedback.playItemClick();
                      widget.onStartWithCategory(cat.starterPrompt, cat.id);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCard
                            : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.lightBorder,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cat.color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(cat.icon, color: cat.color, size: 20),
                          ),
                          const Spacer(),
                          Text(
                            cat.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cat.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }, childCount: ExploreCategory.categories.length),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickToolCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        UiSoundFeedback.playItemClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 175,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
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
    );
  }
}
