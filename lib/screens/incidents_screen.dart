import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/incident_report.dart';
import '../providers/journey_stream_provider.dart';
import '../utils/format.dart';
import '../widgets/status_message.dart';
import '../widgets/status_pill.dart';
import '../widgets/trip_gate.dart';

/// low = grey, medium = orange, high = red. Anything else falls back to grey.
Color severityColor(String severityLevel) {
  switch (severityLevel.trim().toLowerCase()) {
    case 'high':
      return Colors.red.shade700;
    case 'medium':
      return Colors.orange.shade800;
    default:
      return Colors.grey.shade600;
  }
}

/// Unacknowledged SOS alerts first, then other open incidents (worst severity,
/// then newest), resolved ones last.
List<IncidentReport> sortIncidentInbox(List<IncidentReport> incidents) {
  final sorted = [...incidents];
  int time(IncidentReport i) =>
      i.incidentDatetime?.millisecondsSinceEpoch ?? 0;
  sorted.sort((a, b) {
    if (a.isResolved != b.isResolved) return a.isResolved ? 1 : -1;
    if (a.isAwaitingAcknowledgement != b.isAwaitingAcknowledgement) {
      return a.isAwaitingAcknowledgement ? -1 : 1;
    }
    final severity = a.severityRank.compareTo(b.severityRank);
    if (severity != 0) return severity;
    return time(b).compareTo(time(a));
  });
  return sorted;
}

/// Incident inbox for the active trip. The conductor can acknowledge or
/// resolve a report and record the action taken.
class IncidentsScreen extends StatelessWidget {
  const IncidentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TripGate(
      noTripDetail: 'Incident reports appear here once you have started a trip.',
      builder: (context, journey) {
        final trip = context.watch<JourneyStreamProvider>();
        if (trip.tripError != null && trip.incidents.isEmpty) {
          return StatusMessage(
            icon: Icons.error_outline,
            message: 'Could not load incidents',
            detail: '${trip.tripError}',
          );
        }

        final items = sortIncidentInbox(trip.incidents);
        if (items.isEmpty) {
          return const StatusMessage(
            icon: Icons.verified_user_outlined,
            message: 'No incidents reported on this trip',
          );
        }

        final open = items.where((i) => !i.isResolved).length;
        return ListView(
          padding: kPagePadding,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                '$open open  ·  ${items.length - open} resolved',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            for (final incident in items) ...[
              _IncidentCard(incident: incident),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident});

  final IncidentReport incident;

  Color get _statusColor {
    if (incident.isResolved) return kSuccess;
    if (incident.status == IncidentStatus.escalated) return Colors.red.shade700;
    if (incident.status == IncidentStatus.acknowledged) return kWarning;
    return kMuted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final severity = severityColor(incident.severityLevel);

    Widget meta(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text(text, style: muted),
          ],
        );

    return Card(
      child: InkWell(
        onTap: () => _showUpdateSheet(context, incident),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Severity stripe: the card's colour-coding at a glance.
              Container(width: 5, color: severity),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(humanize(incident.incidentType),
                                style: theme.textTheme.titleMedium),
                          ),
                          const SizedBox(width: 8),
                          if (incident.isSos) ...[
                            StatusPill(
                              label: 'SOS',
                              color: Colors.red.shade700,
                              icon: Icons.shield_rounded,
                            ),
                            const SizedBox(width: 6),
                          ],
                          StatusPill(
                            label: humanize(incident.severityLevel),
                            color: severity,
                          ),
                        ],
                      ),
                      if (incident.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(incident.description,
                            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(
                            label: humanize(incident.status),
                            color: _statusColor,
                            icon: incident.isResolved
                                ? Icons.check_circle_rounded
                                : Icons.schedule_rounded,
                          ),
                          if (incident.seatLocation.isNotEmpty)
                            meta(Icons.event_seat_outlined, incident.seatLocation),
                          meta(Icons.access_time_rounded,
                              formatDateTime(incident.incidentDatetime)),
                        ],
                      ),
                      if (incident.actionTaken.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('Action: ${incident.actionTaken}', style: muted),
                      ],
                      if (incident.resolutionDate != null) ...[
                        const SizedBox(height: 2),
                        Text('Resolved ${formatDateTime(incident.resolutionDate)}',
                            style: muted),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Tap to update',
                                style: muted?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600)),
                            Icon(Icons.chevron_right_rounded,
                                size: 18, color: theme.colorScheme.primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showUpdateSheet(BuildContext context, IncidentReport incident) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      // Keep the form above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _UpdateIncidentForm(incident: incident),
    ),
  );
}

class _UpdateIncidentForm extends StatefulWidget {
  const _UpdateIncidentForm({required this.incident});

  final IncidentReport incident;

  @override
  State<_UpdateIncidentForm> createState() => _UpdateIncidentFormState();
}

class _UpdateIncidentFormState extends State<_UpdateIncidentForm> {
  // An SOS arrives as 'escalated', which isn't one of the choices below;
  // opening it should default to the natural next step, not reset it to pending.
  late String _status = IncidentStatus.all.contains(widget.incident.status)
      ? widget.incident.status
      : widget.incident.status == IncidentStatus.escalated
          ? IncidentStatus.acknowledged
          : IncidentStatus.pending;
  late final TextEditingController _action =
      TextEditingController(text: widget.incident.actionTaken);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await context.read<JourneyStreamProvider>().updateIncident(
          widget.incident,
          status: _status,
          actionTaken: _action.text,
        );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Update incident', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${humanize(widget.incident.incidentType)}  ·  '
              'seat ${widget.incident.seatLocation.isEmpty ? '—' : widget.incident.seatLocation}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                for (final status in IncidentStatus.all)
                  ButtonSegment(value: status, label: Text(humanize(status))),
              ],
              selected: {_status},
              onSelectionChanged:
                  _saving ? null : (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _action,
              enabled: !_saving,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Action taken',
                hintText: 'e.g. Moved passenger to seat 2C and warned the other passenger',
              ),
            ),
            if (_status == IncidentStatus.resolved) ...[
              const SizedBox(height: 8),
              Text('Saving as resolved records the current time as the resolution date.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
