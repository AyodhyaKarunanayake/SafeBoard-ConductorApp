import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/conductor_message.dart';
import '../providers/journey_stream_provider.dart';
import '../utils/format.dart';
import '../widgets/reply_composer.dart';

/// What the conductor did with a message pop-up.
enum MessageAlertResult { replied, later }

/// Pop-up for a message a passenger has just sent: the seat and the text are
/// large, and the conductor can reply on the spot. Unlike an SOS it can be
/// dismissed by tapping outside; either way the message stays on the Messages
/// page (unread until it is opened or answered).
Future<MessageAlertResult> showMessageAlert(
  BuildContext context, {
  required ConductorMessage message,
}) async {
  _chime();
  final result = await showDialog<MessageAlertResult>(
    context: context,
    builder: (context) => MessageAlertDialog(message: message),
  );
  return result ?? MessageAlertResult.later;
}

void _chime() {
  try {
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.alert);
  } catch (_) {
    // Not available on this platform; the pop-up itself is the alert.
  }
}

class MessageAlertDialog extends StatelessWidget {
  const MessageAlertDialog({super.key, required this.message});

  final ConductorMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seat = message.seatNumber.trim();

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: scheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'NEW MESSAGE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Column(
                  children: [
                    Text(
                      seat.isEmpty ? 'A passenger' : 'Seat $seat',
                      key: const Key('message-seat'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(color: scheme.primary, fontSize: 40),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '"${message.text}"',
                      key: const Key('message-text'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Text(formatDateTime(message.sentDatetime),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.outline)),
                  ],
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: ReplyComposer(
                  onSend: (text) => context
                      .read<JourneyStreamProvider>()
                      .replyToMessage(message, text),
                  onSent: () =>
                      Navigator.of(context).pop(MessageAlertResult.replied),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(MessageAlertResult.later),
                  child: const Text('Later'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
