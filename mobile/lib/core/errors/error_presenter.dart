import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum ErrorSeverity {
  error,
  warning,
  info,
  success,
}

enum ErrorActionType {
  none,
  retry,
  selectOtherFile,
  splitFile,
  upgradePlan,
}

/// A structured user-facing error model with sanitized messages and actionable next steps.
class PresentableError {
  final String id;
  final String code;
  final String message;
  final String? actionLabel;
  final ErrorActionType actionType;
  final ErrorSeverity severity;
  final bool isDismissible;
  final DateTime timestamp;

  const PresentableError({
    required this.id,
    required this.code,
    required this.message,
    this.actionLabel,
    this.actionType = ErrorActionType.none,
    this.severity = ErrorSeverity.error,
    this.isDismissible = true,
    required this.timestamp,
  });

  /// Maps any raw exception, SSE error code, or network error into a concise, actionable Uzbek message.
  /// Never exposes technical stack traces, provider details, or raw server responses.
  factory PresentableError.fromRaw(
    dynamic rawError, {
    String? code,
    String? actionLabel,
    ErrorActionType? actionType,
  }) {
    final rawString = rawError?.toString() ?? '';
    final lower = rawString.toLowerCase();
    final effectiveCode = code ?? _extractErrorCode(rawString);

    String userMessage = 'So\'rov vaqtincha bajarilmadi. Qayta urinishingiz mumkin.';
    String? resolvedActionLabel = actionLabel;
    ErrorActionType resolvedActionType = actionType ?? ErrorActionType.none;
    ErrorSeverity severity = ErrorSeverity.warning;

    if (effectiveCode == 'NETWORK_ERROR' ||
        lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('clientexception') ||
        lower.contains('connection refused') ||
        lower.contains('aloqa uzildi') ||
        lower.contains('internet')) {
      userMessage = 'Internet bilan aloqa uzildi. Qayta urinib ko\'ring.';
      resolvedActionLabel = actionLabel ?? 'Qayta urinish';
      resolvedActionType = ErrorActionType.retry;
      severity = ErrorSeverity.warning;
    } else if (effectiveCode == 'NETWORK_RESTORED' || lower.contains('aloqa tiklandi')) {
      userMessage = 'Internet aloqasi qayta tiklandi.';
      resolvedActionLabel = null;
      resolvedActionType = ErrorActionType.none;
      severity = ErrorSeverity.success;
    } else if (effectiveCode == 'FILE_TOO_LARGE' ||
        effectiveCode == 'FILE_SIZE_LIMIT_EXCEEDED' ||
        lower.contains('file_too_large') ||
        lower.contains('hajmi') && lower.contains('oshdi')) {
      userMessage = 'Hujjat juda katta. Uni qismlarga ajratib yuboring.';
      resolvedActionLabel = null;
      resolvedActionType = ErrorActionType.splitFile;
      severity = ErrorSeverity.warning;
    } else if (effectiveCode == 'FILE_COUNT_LIMIT_EXCEEDED' || lower.contains('5 ta fayl')) {
      userMessage = 'Bitta xabarga ko\'pi bilan 5 ta fayl biriktirish mumkin.';
      resolvedActionLabel = null;
      severity = ErrorSeverity.warning;
    } else if (effectiveCode == 'UNSUPPORTED_FORMAT' ||
        effectiveCode == 'FILE_CORRUPTED' ||
        lower.contains('unsupported') ||
        lower.contains('format') ||
        lower.contains('buzilgan')) {
      userMessage = 'Faylni o\'qib bo\'lmadi. Boshqa fayl tanlang.';
      resolvedActionLabel = actionLabel ?? 'Boshqa fayl';
      resolvedActionType = ErrorActionType.selectOtherFile;
      severity = ErrorSeverity.warning;
    } else if (effectiveCode == 'QUOTA_EXCEEDED' ||
        effectiveCode == 'LIMIT_REACHED' ||
        lower.contains('quota') ||
        lower.contains('limit')) {
      userMessage = 'Foydalanish limiti tugadi. Keyinroq urinib ko\'ring.';
      resolvedActionLabel = actionLabel ?? 'Tariflar';
      resolvedActionType = ErrorActionType.upgradePlan;
      severity = ErrorSeverity.warning;
    } else if (effectiveCode == 'RATE_LIMIT_EXCEEDED' ||
        effectiveCode == 'UPSTREAM_ERROR' ||
        lower.contains('rate limit') ||
        lower.contains('429')) {
      userMessage = 'So\'rov vaqtincha bajarilmadi. Qayta urinishingiz mumkin.';
      resolvedActionLabel = actionLabel ?? 'Qayta urinish';
      resolvedActionType = ErrorActionType.retry;
      severity = ErrorSeverity.warning;
    } else if (effectiveCode == 'EMPTY_MESSAGE' || lower.contains('bo\'sh')) {
      userMessage = 'Xabar matni bo\'sh bo\'lishi mumkin emas.';
      resolvedActionLabel = null;
      severity = ErrorSeverity.info;
    }

    return PresentableError(
      id: '${DateTime.now().millisecondsSinceEpoch}_$effectiveCode',
      code: effectiveCode,
      message: userMessage,
      actionLabel: resolvedActionLabel,
      actionType: resolvedActionType,
      severity: severity,
      isDismissible: true,
      timestamp: DateTime.now(),
    );
  }

  static String _extractErrorCode(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('file_count_limit_exceeded') || lower.contains('5 ta fayl')) {
      return 'FILE_COUNT_LIMIT_EXCEEDED';
    }
    if (lower.contains('file_size_limit_exceeded') ||
        lower.contains('file_too_large') ||
        lower.contains('juda katta')) {
      return 'FILE_TOO_LARGE';
    }
    if (lower.contains('unsupported_format') ||
        lower.contains('unsupported') ||
        lower.contains('o\'qib bo\'lmadi')) {
      return 'UNSUPPORTED_FORMAT';
    }
    if (lower.contains('file_corrupted') || lower.contains('buzilgan')) {
      return 'FILE_CORRUPTED';
    }
    if (lower.contains('quota_exceeded') || lower.contains('limit_reached') || lower.contains('limiti tugadi')) {
      return 'QUOTA_EXCEEDED';
    }
    if (lower.contains('rate_limit_exceeded') || lower.contains('rate_limit')) {
      return 'RATE_LIMIT_EXCEEDED';
    }
    if (lower.contains('network_restored') || lower.contains('aloqa tiklandi')) {
      return 'NETWORK_RESTORED';
    }
    if (lower.contains('network_error') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('aloqa uzildi') ||
        lower.contains('internet')) {
      return 'NETWORK_ERROR';
    }
    return 'UNKNOWN_ERROR';
  }
}

/// Inline compact notification banner anchored below the chat header.
class InlineErrorBanner extends StatelessWidget {
  final PresentableError? error;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;

  const InlineErrorBanner({
    super.key,
    required this.error,
    this.onDismiss,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVisible = error != null;

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 220),
      firstCurve: Curves.easeOutCubic,
      secondCurve: Curves.easeInCubic,
      crossFadeState:
          isVisible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      secondChild: const SizedBox(width: double.infinity, height: 0),
      firstChild: isVisible
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _backgroundColor(error!.severity, isDark),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _borderColor(error!.severity, isDark),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    _iconData(error!.severity),
                    size: 18,
                    color: _iconColor(error!.severity),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!.message,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                  ),
                  if (error!.actionLabel != null && onAction != null) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppColors.primary,
                      ),
                      onPressed: onAction,
                      child: Text(
                        error!.actionLabel!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  if (error!.isDismissible && onDismiss != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Xabarni yopish',
                      child: Semantics(
                        label: 'Xabarni yopish',
                        button: true,
                        child: InkWell(
                          onTap: onDismiss,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  IconData _iconData(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.warning:
        return Icons.warning_amber_rounded;
      case ErrorSeverity.info:
        return Icons.info_outline_rounded;
      case ErrorSeverity.success:
        return Icons.check_circle_outline_rounded;
      case ErrorSeverity.error:
        return Icons.error_outline_rounded;
    }
  }

  Color _iconColor(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.warning:
        return AppColors.warning;
      case ErrorSeverity.info:
        return AppColors.primary;
      case ErrorSeverity.success:
        return AppColors.success;
      case ErrorSeverity.error:
        return AppColors.error;
    }
  }

  Color _backgroundColor(ErrorSeverity severity, bool isDark) {
    switch (severity) {
      case ErrorSeverity.warning:
        return AppColors.warning.withOpacity(isDark ? 0.15 : 0.08);
      case ErrorSeverity.info:
        return AppColors.primary.withOpacity(isDark ? 0.15 : 0.08);
      case ErrorSeverity.success:
        return AppColors.success.withOpacity(isDark ? 0.15 : 0.08);
      case ErrorSeverity.error:
        return AppColors.error.withOpacity(isDark ? 0.15 : 0.08);
    }
  }

  Color _borderColor(ErrorSeverity severity, bool isDark) {
    switch (severity) {
      case ErrorSeverity.warning:
        return AppColors.warning.withOpacity(isDark ? 0.4 : 0.3);
      case ErrorSeverity.info:
        return AppColors.primary.withOpacity(isDark ? 0.4 : 0.3);
      case ErrorSeverity.success:
        return AppColors.success.withOpacity(isDark ? 0.4 : 0.3);
      case ErrorSeverity.error:
        return AppColors.error.withOpacity(isDark ? 0.4 : 0.3);
    }
  }
}
