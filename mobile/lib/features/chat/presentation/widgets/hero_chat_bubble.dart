import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class HeroChatBubble extends StatefulWidget {
  final String userName;
  final VoidCallback onTap;

  const HeroChatBubble({
    super.key,
    required this.userName,
    required this.onTap,
  });

  @override
  State<HeroChatBubble> createState() => _HeroChatBubbleState();
}

class _HeroChatBubbleState extends State<HeroChatBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final scale = 1.0 + (_animController.value * 0.03);

            return Transform.scale(
              scale: scale,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF131A26)
                      : const Color(0xFFF1F5F9),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(
                      0.25 + (_animController.value * 0.2),
                    ),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(
                        isDark ? 0.12 : 0.08,
                      ),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Salom, ${widget.userName} 👋',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Suhbatni boshlash',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Soundwave indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final heights = [14.0, 22.0, 28.0, 18.0, 12.0];
                        final factor =
                            (_animController.value + (index * 0.2)) % 1.0;
                        final h = heights[index] * (0.6 + (0.4 * factor));

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: 3.5,
                          height: h,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
