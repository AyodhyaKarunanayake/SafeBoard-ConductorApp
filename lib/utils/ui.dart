import 'package:flutter/material.dart';

/// Runs a write that returns null on success or an error message, and shows
/// the failure (or [success]) in a SnackBar. Conductor actions are operator
/// actions, so a failure must never pass silently.
Future<bool> runAction(
  BuildContext context,
  Future<String?> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;
  final error = await action();

  messenger.hideCurrentSnackBar();
  if (error != null) {
    messenger.showSnackBar(SnackBar(
      content: Text(error),
      backgroundColor: errorColor,
      duration: const Duration(seconds: 6),
    ));
    return false;
  }
  if (success != null) {
    messenger.showSnackBar(SnackBar(content: Text(success)));
  }
  return true;
}

/// Yes/no confirmation dialog; true only if the user confirms.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
