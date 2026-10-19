import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref
        .read(authProvider.notifier)
        .register(
          _emailController.text,
          _passwordController.text,
          _nameController.text,
        );
    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Ro\'yxatdan o\'tish')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Yangi hisob yaratish',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'AI yordamchisi bilan suhbatlarni boshlang',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error Banner
                    if (authState.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                authState.errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Full Name Field
                    Text(
                      'To\'liq ismingiz',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Sardor Rahimov',
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          size: 20,
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Ismingizni kiriting';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Email Field
                    Text(
                      'Email manzili',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'user@example.com',
                        prefixIcon: Icon(
                          Icons.alternate_email_rounded,
                          size: 20,
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Emailni kiriting';
                        }
                        if (!val.contains('@')) {
                          return 'Yaroqli email kiriting';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password Field
                    Text(
                      'Parol (kamida 8 ta belgi)',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        prefixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Parolni kiriting';
                        }
                        if (val.length < 8) {
                          return 'Kamida 8 ta belgidan iborat bo\'lishi kerak';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    ElevatedButton(
                      onPressed: authState.isLoading ? null : _submit,
                      child: authState.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text('Hisob yaratish'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
