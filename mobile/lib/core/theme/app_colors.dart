import 'package:flutter/material.dart';

/// App color tokens matching The Go-getters web design and modern mobile reference.
class AppColors {
  // Brand accents
  static const Color primary = Color(0xFF00D26A); // Vibrant Mint Green
  static const Color primaryDark = Color(0xFF059669);
  static const Color primaryLight = Color(0xFF34D399);

  // Dark Theme Tokens (from website dark mode)
  static const Color darkScaffold = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF161B22);
  static const Color darkCard = Color(0xFF161B22);
  static const Color darkBorder = Color(0xFF21262D);
  static const Color darkTextPrimary = Color(0xFFF0F6FC);
  static const Color darkTextSecondary = Color(0xFF8B949E);
  static const Color darkBubbleAssistant = Color(0xFF161B22);
  static const Color darkBubbleUser = Color(
    0xFF1F4A32,
  ); // Emerald-tinted dark bubble
  static const Color darkComposer = Color(0xFF161B22);

  // Light Theme Tokens (from website light mode)
  static const Color lightScaffold = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightBubbleAssistant = Color(0xFFFFFFFF);
  static const Color lightBubbleUser = Color(0xFFE8F9F0); // Soft emerald tint
  static const Color lightComposer = Color(0xFFFFFFFF);

  // Category Colors (from Image 3 Mobile Mockup)
  static const Color catArt = Color(0xFFA855F7);
  static const Color catBooking = Color(0xFFF59E0B);
  static const Color catCode = Color(0xFF10B981);
  static const Color catContent = Color(0xFF0EA5E9);
  static const Color catEntertainment = Color(0xFFEAB308);
  static const Color catTranslator = Color(0xFF0284C7);
  static const Color catHealth = Color(0xFFEC4899);
  static const Color catMusic = Color(0xFFD946EF);

  // Status colors
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
}
