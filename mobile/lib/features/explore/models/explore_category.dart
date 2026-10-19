import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class ExploreCategory {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String starterPrompt;

  const ExploreCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.starterPrompt,
  });

  static const List<ExploreCategory> categories = [
    ExploreCategory(
      id: 'art',
      title: 'Art',
      description: 'Create digital art concepts, from sketches to finished design ideas.',
      icon: Icons.palette_outlined,
      color: AppColors.catArt,
      starterPrompt: 'Menga yangi ilhomlantiruvchi san\'at va dizayn konsepti uchun g\'oyalar taklif qil.',
    ),
    ExploreCategory(
      id: 'booking',
      title: 'Booking',
      description:
          'Find stays, flights, car rentals, airport taxis, and attractions.',
      icon: Icons.calendar_today_rounded,
      color: AppColors.catBooking,
      starterPrompt: 'Toshkentdan Samarqand va Buxoroga 3 kunlik sayohat rejasini tuzib ber.',
    ),
    ExploreCategory(
      id: 'code',
      title: 'Code',
      description:
          'Write programming code or algorithms for complex applications.',
      icon: Icons.code_rounded,
      color: AppColors.catCode,
      starterPrompt: 'Go tilida yuqori yuklamali REST API microservice arxitekturasini tushuntirib ber.',
    ),
    ExploreCategory(
      id: 'content',
      title: 'Content',
      description: 'Generate well-written paragraphs on any given subject.',
      icon: Icons.article_outlined,
      color: AppColors.catContent,
      starterPrompt:
          'Startap loyihalar uchun professional taqdimot matnini yozib ber.',
    ),
    ExploreCategory(
      id: 'entertainment',
      title: 'Entertainment',
      description: 'Recommendations based on preferences, interests, and mood.',
      icon: Icons.auto_awesome_rounded,
      color: AppColors.catEntertainment,
      starterPrompt: 'Dasturchilar uchun eng qiziqarli ilmiy-fantastik kitoblar va filmlar ro\'yxati.',
    ),
    ExploreCategory(
      id: 'translator',
      title: 'Translator',
      description:
          'Translate to any language preserving tone, nuance, and context.',
      icon: Icons.translate_rounded,
      color: AppColors.catTranslator,
      starterPrompt:
          'Ushbu matnni professional ingliz tiliga ilmiy uslubda tarjima qil: ',
    ),
    ExploreCategory(
      id: 'health',
      title: 'Health',
      description:
          'Advice and recommendations for wellness and healthy lifestyle.',
      icon: Icons.favorite_rounded,
      color: AppColors.catHealth,
      starterPrompt: 'Kun bo\'yi kompyuter oldida o\'tiruvchi insonlar uchun sog\'lom odatlar tartibi.',
    ),
    ExploreCategory(
      id: 'music',
      title: 'Music',
      description:
          'Chord progressions, songwriting ideas, and music discovery.',
      icon: Icons.music_note_rounded,
      color: AppColors.catMusic,
      starterPrompt: 'Fokus va diqqatni jamlash uchun qanday janrdagi musiqalar eng samarali hisoblanadi?',
    ),
  ];
}
