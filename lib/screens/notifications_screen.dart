import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/conductor_provider.dart';
import '../providers/notifications_provider.dart';
import '../utils/format.dart';
import '../widgets/status_message.dart';

/// Foreground FCM messages received this session, newest first. Each one is
/// sent by the allocateSeat Cloud Function when a seat is allocated on the
/// conductor's journey.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _liveAlerts =
      'Live alerts for new bookings, incidents and cash payments still appear here while the app is open.';
  static const _webNote =
      'Push notifications require the Android/iOS app; this web build cannot receive them. $_liveAlerts';
  static const _unsupportedNote =
      'Push notifications require the Android/iOS app; this build cannot receive them. $_liveAlerts';

  /// Icon and colour for the alerts the app itself raises, keyed on their
  /// title; anything else (e.g. a push message) gets the generic bell.
  static (IconData, Color) _look(String title, ColorScheme scheme) {
    switch (title) {
      case 'New passenger allocated':
        return (Icons.person_add_alt_1_rounded, scheme.primary);
      case 'Cash to collect':
        return (Icons.payments_rounded, kSuccess);
      case 'New incident reported':
        return (Icons.report_rounded, scheme.error);
      case 'Passenger left':
        return (Icons.event_seat_rounded, scheme.primary);
      case 'SOS alert':
        return (Icons.shield_rounded, Colors.red.shade700);
      case 'New message':
        return (Icons.chat_bubble_rounded, scheme.primary);
      default:
        return (Icons.notifications_active_rounded, scheme.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<NotificationsProvider>().items;
    final topic = context.select<ConductorProvider, String?>((p) => p.subscribedTopic);
    final topicError = context.select<ConductorProvider, String?>((p) => p.topicError);
    final theme = Theme.of(context);

    final pushSupported = ConductorProvider.pushSupported;

    Widget banner({
      required IconData icon,
      required String text,
      required Color background,
      required Color foreground,
    }) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(kRadiusSmall),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(text,
                      style: TextStyle(color: foreground, height: 1.4, fontSize: 13)),
                ),
              ],
            ),
          ),
        );

    return Column(
      children: [
        if (!pushSupported)
          banner(
            icon: Icons.info_outline_rounded,
            text: kIsWeb ? _webNote : _unsupportedNote,
            background: theme.colorScheme.primaryContainer,
            foreground: theme.colorScheme.onPrimaryContainer,
          )
        else if (topicError != null)
          banner(
            icon: Icons.error_outline_rounded,
            text: 'Push notifications are not active on this device: $topicError',
            background: theme.colorScheme.errorContainer,
            foreground: theme.colorScheme.onErrorContainer,
          )
        else if (topic != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: kSuccess),
                const SizedBox(width: 6),
                Text('Listening on $topic', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? const StatusMessage(
                  icon: Icons.notifications_none_rounded,
                  message: 'No alerts yet',
                  detail:
                      'New passenger allocations, incident reports and cash payments on your trip will show up here while the app is open.',
                )
              : ListView.separated(
                  padding: kPagePadding,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final (icon, color) = _look(item.title, theme.colorScheme);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: color, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, style: theme.textTheme.titleSmall),
                                  if (item.body.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(item.body,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.outline,
                                            height: 1.35)),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(formatDateTime(item.receivedAt),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.outline)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
