import 'package:flutter/services.dart';

/// Central utility for Gemini-like UI sound and haptic feedback
class UiSoundFeedback {
  UiSoundFeedback._();

  /// Triggered when the side drawer opens (via swipe or button)
  static void playDrawerOpen() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  /// Triggered when the side drawer closes
  static void playDrawerClose() {
    HapticFeedback.lightImpact();
  }

  /// Triggered on tapping menu items, conversation items, or quick tools
  static void playItemClick() {
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
  }

  /// Triggered on new chat button or primary action
  static void playActionClick() {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }
}
