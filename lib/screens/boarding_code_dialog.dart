import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../utils/boarding_code.dart';

/// Shows the boarding code for the conductor to read out to the passenger,
/// large enough to be legible at a glance. Unlike the SOS pop-up this is a
/// routine action, so it can be dismissed freely (tapping outside, back, or
/// Done) — showing it again later does no harm, since it is always the same
/// fixed pilot code.
Future<void> showBoardingCodeDialog(
  BuildContext context, {
  required String seat,
}) {
  try {
    HapticFeedback.mediumImpact();
  } catch (_) {
    // Not available on this platform; the pop-up itself is enough.
  }
  return showDialog<void>(
    context: context,
    builder: (context) => BoardingCodeDialog(seat: seat),
  );
}

class BoardingCodeDialog extends StatelessWidget {
  const BoardingCodeDialog({super.key, required this.seat});

  final String seat;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: kBoardingOtp));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: scheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.vpn_key_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'BOARDING CODE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Column(
                children: [
                  Text(
                    'Tell this code to the passenger in seat $seat',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => _copy(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(kRadius),
                      ),
                      child: Column(
                        children: [
                          Text(
                            kBoardingOtp.split('').join('  '),
                            key: const Key('boarding-otp'),
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.copy_rounded,
                                  size: 14,
                                  color: scheme.primary.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Text(
                                'Tap to copy',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The passenger enters this code in the SafeBoard app to start their journey.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline, height: 1.4),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
