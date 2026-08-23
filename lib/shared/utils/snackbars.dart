import 'package:flutter/material.dart';
import 'package:whatsapp_clone/theme/theme.dart';

enum AppNotificationType { success, info, warning, error }

/// Shows one consistent, dismissible notification without stacking old messages.
void showAppNotification({
  required BuildContext context,
  required String message,
  AppNotificationType type = AppNotificationType.info,
  Duration? duration,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final colorTheme = Theme.of(context).custom.colorTheme;
  final (backgroundColor, icon, foregroundColor) = switch (type) {
    AppNotificationType.success =>
      (colorTheme.greenColor, Icons.check_circle_outline_rounded, Colors.white),
    AppNotificationType.info =>
      (colorTheme.blueColor, Icons.info_outline_rounded, Colors.white),
    AppNotificationType.warning =>
      (colorTheme.yellowColor, Icons.warning_amber_rounded, Colors.black87),
    AppNotificationType.error =>
      (colorTheme.errorSnackBarColor, Icons.error_outline_rounded, Colors.white),
  };

  final displayDuration = duration ?? switch (type) {
    AppNotificationType.error => const Duration(seconds: 4),
    AppNotificationType.warning => const Duration(seconds: 3),
    _ => const Duration(seconds: 2),
  };

  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: foregroundColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: backgroundColor,
        elevation: 4,
        duration: displayDuration,
        dismissDirection: DismissDirection.down,
        action: action,
      ),
    );
}

void showSuccessNotification({
  required BuildContext context,
  required String message,
}) {
  showAppNotification(
    context: context,
    message: message,
    type: AppNotificationType.success,
  );
}

void showErrorNotification({
  required BuildContext context,
  required String message,
  SnackBarAction? action,
}) {
  showAppNotification(
    context: context,
    message: message,
    type: AppNotificationType.error,
    action: action,
  );
}
