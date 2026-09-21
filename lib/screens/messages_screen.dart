import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/conductor_message.dart';
import '../providers/journey_stream_provider.dart';
import '../utils/format.dart';
import '../utils/ui.dart';
import '../widgets/reply_composer.dart';
import '../widgets/status_message.dart';
import '../widgets/status_pill.dart';
import '../widgets/trip_gate.dart';

/// Messages passengers send with "Text the conductor" in the SafeBoard app,
/// newest first, updating live, each with the conductor's replies. Messages
/// stay here after their pop-up; tapping one marks it read, and Reply answers it.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final trip = context.watch<JourneyStreamProvider>();
    final unread = trip.unreadMessageCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          if (unread > 0)
            IconButton(
              tooltip: 'Mark all as read',
              icon: const Icon(Icons.done_all_rounded),
              onPressed: () => runAction(context, trip.markAllMessagesRead),
            ),
        ],
      ),
      body: TripGate(
        noTripDetail: 'Passenger messages appear here once you have started a trip.',
        builder: (context, journey) {
          final theme = Theme.of(context);
          // Messages are matched on journey id, so say which one this page is
          // listening to: a passenger's message only shows up if the conductor
          // is running the journey that passenger booked.
          final listening = Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Icon(Icons.sensors_rounded, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Listening on journey ${journey.journeyId} · bus ${journey.busId}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ],
            ),
          );

          if (trip.tripError != null && trip.messages.isEmpty) {
            return StatusMessage(
              icon: Icons.error_outline_rounded,
              message: 'Could not load messages',
              detail: '${trip.tripError}',
            );
          }
          final messages = trip.messages;
          if (messages.isEmpty) {
            return ListView(
              padding: kPagePadding,
              children: [
                listening,
                const SizedBox(height: 40),
                const StatusMessage(
                  icon: Icons.chat_bubble_outline_rounded,
                  message: 'No messages yet',
                  detail:
                      'When a passenger uses "Text conductor" in the SafeBoard app, it appears here. '
                      'Passengers message the journey they booked (JRN_87_001 today), so start your trip with that journey ID.',
                ),
              ],
            );
          }
          return ListView(
            padding: kPagePadding,
            children: [
              listening,
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  unread == 0 ? 'All caught up' : '$unread new',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              for (final message in messages) ...[
                _MessageCard(message: message),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Bottom sheet to reply to [message] from the Messages page.
void showReplySheet(BuildContext context, ConductorMessage message) {
  final trip = context.read<JourneyStreamProvider>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      // Keep the reply box above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reply to ${message.seatNumber.isEmpty ? 'passenger' : 'seat ${message.seatNumber}'}',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('"${message.text}"',
                  style: Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(sheetContext).colorScheme.outline)),
              const SizedBox(height: 16),
              ReplyComposer(
                onSend: (text) => trip.replyToMessage(message, text),
                onSent: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final ConductorMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = message.isUnread;
    final color = theme.colorScheme.primary;

    return Card(
      color: unread ? color.withValues(alpha: 0.06) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: unread ? color.withValues(alpha: 0.35) : kHairline),
      ),
      child: InkWell(
        onTap: unread
            ? () => runAction(
                  context,
                  () => context.read<JourneyStreamProvider>().markMessageRead(message),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.chat_bubble_rounded, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              message.seatNumber.isEmpty
                                  ? 'A passenger'
                                  : 'Seat ${message.seatNumber}',
                              style: theme.textTheme.titleSmall,
                            ),
                            if (unread) StatusPill(label: 'New', color: color),
                            if (message.hasReply)
                              const StatusPill(
                                label: 'Replied',
                                color: kSuccess,
                                icon: Icons.reply_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(message.text,
                            style: theme.textTheme.bodyLarge?.copyWith(height: 1.35)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 14, color: theme.colorScheme.outline),
                            const SizedBox(width: 4),
                            Text(formatDateTime(message.sentDatetime),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.outline)),
                            if (unread) ...[
                              const Spacer(),
                              Text('Tap to mark read',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: color, fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // The conductor's replies, shown as a thread under the message.
              for (final reply in message.replies)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, left: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(reply.text,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer)),
                        const SizedBox(height: 2),
                        Text('You · ${formatDateTime(reply.sentDatetime)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => showReplySheet(context, message),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  icon: const Icon(Icons.reply_rounded, size: 18),
                  label: Text(message.hasReply ? 'Reply again' : 'Reply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
