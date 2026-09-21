import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/incident_report.dart';
import '../models/seat_allocation.dart';
import '../utils/format.dart';
import '../widgets/status_pill.dart';

/// What the conductor chose to do about an SOS pop-up.
enum SosResponse { acknowledge, view, later }

const Color _sosRed = Color(0xFFC62828);

/// Full-attention pop-up for a passenger's SOS: the seat number is by far the
/// biggest thing on screen. It can't be dismissed by tapping outside or with
/// the back button, so it always ends in an explicit choice.
Future<SosResponse> showSosAlert(
  BuildContext context, {
  required IncidentReport incident,
  SeatAllocation? allocation,
}) async {
  _raiseAlarm();
  final response = await showDialog<SosResponse>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: SosAlertDialog(incident: incident, allocation: allocation),
    ),
  );
  return response ?? SosResponse.later;
}

/// A strong vibration and the system alert sound, where the device has them.
void _raiseAlarm() {
  try {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  } catch (_) {
    // Not available on this platform; the pop-up itself is the alert.
  }
}

class SosAlertDialog extends StatelessWidget {
  const SosAlertDialog({super.key, required this.incident, this.allocation});

  final IncidentReport incident;

  /// The booking on this bus for the SOS seat, if there is one.
  final SeatAllocation? allocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seat = incident.seatLocation.trim();
    final a = allocation;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: _sosRed,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'SOS ALERT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  children: [
                    Text('A passenger needs help at seat',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(height: 4),
                    // The point of the pop-up: readable from across the aisle.
                    Text(
                      seat.isEmpty ? '?' : seat,
                      key: const Key('sos-seat'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _sosRed,
                        fontSize: 88,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (a != null)
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          StatusPill(label: a.zone.label, color: zoneColor(a.zone)),
                          Text(
                            [a.boardingStop, a.alightingStop]
                                .where((s) => s.isNotEmpty)
                                .join('  →  '),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      )
                    else
                      Text(
                        seat.isEmpty
                            ? 'The passenger\'s seat was not included.'
                            : 'No booking found for this seat on your bus.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Raised ${formatDateTime(incident.incidentDatetime)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(SosResponse.acknowledge),
                      style: FilledButton.styleFrom(
                        backgroundColor: _sosRed,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('I\'m on my way'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(SosResponse.view),
                            child: const Text('View incident'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(SosResponse.later),
                            child: const Text('Later'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
