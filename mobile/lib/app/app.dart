import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/providers/auth_provider.dart';
import 'home_shell.dart';

class AiChatApp extends ConsumerWidget {
  const AiChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'The Go-getters AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: authState.isLoading
          ? const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          : authState.isAuthenticated
          ? const HomeShell()
          : const LoginScreen(),
    );
  }
}
