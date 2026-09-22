import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/standing_ranking.dart';
import '../models/zone.dart';
import '../providers/journey_stream_provider.dart';
import '../widgets/status_pill.dart';

/// Offers an empty seat to the standing passengers, furthest-travelling first.
/// Only ever opened on demand — by the conductor tapping an empty seat on the
/// map (see SeatMapScreen.offerEmptySeat) — never automatically: deciding who
/// sits there is the conductor's own call, made in person, not the app's.
/// Resolves to true if the conductor gave the seat to someone. Handles there
/// being nobody standing gracefully, with a plain message instead of an empty
/// list.
Future<bool> showEmptySeatPrompt(
  BuildContext context, {
  required String seat,
  required Zone zone,
  required List<StandingCandidate> candidates,
}) async {
  final assigned = await showDialog<bool>(
    context: context,
    builder: (context) =>
        EmptySeatDialog(seat: seat, zone: zone, candidates: candidates),
  );
  return assigned ?? false;
}

class EmptySeatDialog extends StatefulWidget {
  const EmptySeatDialog({
    super.key,
    required this.seat,
    required this.zone,
    required this.candidates,
  });

  final String seat;
  final Zone zone;

  /// Standing passengers, best candidate first.
  final List<StandingCandidate> candidates;

  @override
  State<EmptySeatDialog> createState() => _EmptySeatDialogState();
}

class _EmptySeatDialogState extends State<EmptySeatDialog> {
  String? _assigningId;
  String? _error;

  Future<void> _assign(StandingCandidate candidate) async {
    setState(() {
      _assigningId = candidate.allocation.allocationId;
      _error = null;
    });
    final error = await context
        .read<JourneyStreamProvider>()
        .assignStandingToSeat(candidate.allocation, widget.seat);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _assigningId = null;
        _error = error;
      });
    }
  }

  String _distanceText(StandingCandidate c) {
    if (!c.destinationKnown) return 'Destination not known';
    if (c.remainingStops == 0) return 'At or past their stop';
    final stops = '${c.remainingStops} stop${c.remainingStops == 1 ? '' : 's'}';
    final km = c.remainingKm;
    return km == null ? '$stops to go' : '$stops · ${km.round()} km to go';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = _assigningId != null;
    final count = widget.candidates.length;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: scheme.primary,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              child: Column(
                children: [
                  const Icon(Icons.event_seat_rounded, color: Colors.white, size: 28),
                  const SizedBox(height: 6),
                  Text(
                    'Seat ${widget.seat} is empty',
                    key: const Key('empty-seat-title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    count == 0
                        ? 'Nobody is standing right now — check back once someone is.'
                        : '$count passenger${count == 1 ? ' is' : 's are'} standing. '
                            'Give the seat to the one with the furthest to travel?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                  ),
                ],
              ),
            ),
            if (widget.candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Column(
                  children: [
                    Icon(Icons.accessibility_new_rounded,
                        size: 36, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text('No standing passengers to move here at the moment.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (var i = 0; i < widget.candidates.length; i++)
                      _CandidateRow(
                        candidate: widget.candidates[i],
                        best: i == 0,
                        seat: widget.seat,
                        distance: _distanceText(widget.candidates[i]),
                        busy: busy,
                        assigning:
                            _assigningId == widget.candidates[i].allocation.allocationId,
                        onAssign: () => _assign(widget.candidates[i]),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_error!, style: TextStyle(color: scheme.error)),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 8),
              child: TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(false),
                child: Text(count == 0 ? 'Close' : 'Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.best,
    required this.seat,
    required this.distance,
    required this.busy,
    required this.assigning,
    required this.onAssign,
  });

  final StandingCandidate candidate;
  final bool best;
  final String seat;
  final String distance;
  final bool busy;
  final bool assigning;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = candidate.allocation;
    final route = [a.boardingStop, a.alightingStop].where((s) => s.isNotEmpty).join('  →  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: best ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45) : Colors.white,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(
          color: best ? theme.colorScheme.primary.withValues(alpha: 0.5) : kHairline,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(a.seatNumber, style: theme.textTheme.titleSmall),
                    if (best)
                      const StatusPill(
                        label: 'Travels furthest',
                        color: kSuccess,
                        icon: Icons.trending_flat_rounded,
                      ),
                  ],
                ),
                if (route.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(route, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 2),
                Text(distance,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          best
              ? FilledButton(
                  onPressed: busy ? null : onAssign,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: assigning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Assign to $seat'),
                )
              : OutlinedButton(
                  onPressed: busy ? null : onAssign,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: assigning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Assign'),
                ),
        ],
      ),
    );
  }
}
