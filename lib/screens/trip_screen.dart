import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/bus_info.dart';
import '../models/journey_instance.dart';
import '../models/occupancy_summary.dart';
import '../models/route_info.dart';
import '../models/seat_allocation.dart';
import '../models/zone.dart';
import '../providers/conductor_provider.dart';
import '../providers/journey_stream_provider.dart';
import '../providers/reference_data_provider.dart';
import '../utils/format.dart';
import '../utils/ui.dart';
import '../widgets/card_header.dart';
import '../widgets/status_message.dart';
import '../widgets/status_pill.dart';
import '../widgets/trip_gate.dart';
import 'route_screen.dart';

/// The passenger app books every ticket into this journey id today.
const String kDefaultJourneyId = 'JRN_87_001';

class TripScreen extends StatelessWidget {
  const TripScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TripGate(
      noTripBuilder: (_) => const _StartTripView(),
      builder: (context, journey) => _ActiveTripView(journey: journey),
    );
  }
}

// --- no active trip: start one ------------------------------------------------

class _StartTripView extends StatefulWidget {
  const _StartTripView();

  @override
  State<_StartTripView> createState() => _StartTripViewState();
}

class _StartTripViewState extends State<_StartTripView> {
  final _journeyId = TextEditingController(text: kDefaultJourneyId);
  String? _busId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _journeyId.dispose();
    super.dispose();
  }

  Future<void> _start(BusInfo bus, List<String> stops) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await context.read<JourneyStreamProvider>().startTrip(
            bus: bus,
            journeyId: _journeyId.text,
            stops: stops,
          );
    } catch (e, stack) {
      // startTrip reports its own failures as a message; this only guards
      // against something unexpected escaping, and logs the real error.
      debugPrint('[Start trip button] unexpected ${e.runtimeType}: $e\n$stack');
      error = 'Could not start the trip (${e.runtimeType}): $e';
    }
    if (!mounted) return;
    // On success the live journey stream swaps this screen for the trip view.
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceDataProvider>();
    final conductorId =
        context.select<ConductorProvider, String?>((p) => p.conductorId) ?? '';
    final theme = Theme.of(context);

    if (reference.isLoading) return const LoadingIndicator();
    if (reference.buses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusMessage(
              icon: Icons.directions_bus_outlined,
              message: 'No buses available',
              detail: reference.error,
            ),
            FilledButton.tonal(
              onPressed: reference.reload,
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    final buses = reference.buses;
    final own = reference.busesFor(conductorId);
    final selected = buses.firstWhere(
      (b) => b.busId == _busId,
      orElse: () => own.isNotEmpty ? own.first : buses.first,
    );
    final stops = reference.stopsForBus(selected);

    return ListView(
      padding: kPagePadding,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CardHeader(icon: Icons.play_circle_outline_rounded, title: 'Start a trip'),
                const SizedBox(height: 12),
                Text(
                  'You have no active trip. Choose your bus and start: this creates '
                  'the trip record that the passenger app updates as seats are booked.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline, height: 1.4),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  value: selected.busId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Bus'),
                  items: [
                    for (final bus in buses)
                      DropdownMenuItem(
                        value: bus.busId,
                        child: Text(
                          '${bus.busNumber}  ·  ${bus.scheduledTime}'
                          '${bus.conductorId == conductorId ? '  (yours)' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy ? null : (id) => setState(() => _busId = id),
                ),
                const SizedBox(height: 6),
                Text('${selected.startPoint} to ${selected.endPoint}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 16),
                TextField(
                  controller: _journeyId,
                  enabled: !_busy,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Journey ID',
                    helperText:
                        'The passenger app currently books every ticket into $kDefaultJourneyId.',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(kRadiusSmall),
                    ),
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _start(selected, stops),
                  icon: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start trip'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- active trip ----------------------------------------------------------------

class _ActiveTripView extends StatelessWidget {
  const _ActiveTripView({required this.journey});

  final JourneyInstance journey;

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceDataProvider>();
    final trip = context.watch<JourneyStreamProvider>();
    final bus = reference.busById(journey.busId);
    final stops = reference.stopsForBus(bus);

    return ListView(
      padding: kPagePadding,
      children: [
        _JourneyCard(journey: journey, bus: bus, occupancy: trip.occupancy),
        const SizedBox(height: kGap),
        _ControlsCard(journey: journey, stops: stops),
        const SizedBox(height: kGap),
        _OccupancyCard(summary: trip.occupancy),
        const SizedBox(height: kGap),
        _RouteProgressCard(
          journey: journey,
          stops: stops,
          route: reference.route,
          forward: stops.isEmpty || stops.first == reference.route.stops.first,
        ),
        const SizedBox(height: 24),
        _AllocationsSection(allocations: trip.allocations, error: trip.tripError),
      ],
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case TripStatus.inTransit:
      return kSuccess;
    case TripStatus.scheduled:
      return kWarning;
    default:
      return kMuted;
  }
}

Color _crowdingColor(String level) {
  switch (level) {
    case 'low':
      return kSuccess;
    case 'moderate':
      return kWarning;
    case 'high':
      return Colors.deepOrange.shade700;
    case 'critical':
      return Colors.red.shade700;
    default:
      return kMuted;
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.journey,
    required this.bus,
    required this.occupancy,
  });

  final JourneyInstance journey;
  final BusInfo? bus;
  final OccupancySummary occupancy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.directions_bus_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bus?.busNumber ?? journey.busId,
                          style: theme.textTheme.titleMedium),
                      Text('Journey ${journey.journeyId}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
                StatusPill(
                  label: humanize(journey.status),
                  color: _statusColor(journey.status),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(kRadiusSmall),
              ),
              child: Column(
                children: [
                  _InfoRow('Route', journey.routeId.isEmpty ? '—' : journey.routeId),
                  _InfoRow('Current stop',
                      journey.currentStop.isEmpty ? '—' : journey.currentStop,
                      emphasis: true),
                  _InfoRow('Crowding', humanize(occupancy.crowdingLevel),
                      color: _crowdingColor(occupancy.crowdingLevel)),
                  _InfoRow('Departed', formatDateTime(journey.departureDatetime)),
                  _InfoRow('Arrives (est.)', formatDateTime(journey.arrivalDatetime)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.emphasis = false, this.color});

  final String label;
  final String value;
  final bool emphasis;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasis || color != null ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.journey, required this.stops});

  final JourneyInstance journey;
  final List<String> stops;

  int get _currentIndex => stops.indexWhere(
      (s) => s.toLowerCase() == journey.currentStop.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final trip = context.read<JourneyStreamProvider>();
    final theme = Theme.of(context);
    final index = _currentIndex;
    final hasNext = stops.isNotEmpty && index < stops.length - 1;
    final status = journey.status == TripStatus.scheduled
        ? TripStatus.scheduled
        : TripStatus.inTransit;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CardHeader(icon: Icons.tune_rounded, title: 'Trip controls'),
            const SizedBox(height: 16),
            if (stops.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: index == -1 ? null : stops[index],
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Current stop'),
                items: [
                  for (final stop in stops)
                    DropdownMenuItem(value: stop, child: Text(stop)),
                ],
                onChanged: (stop) {
                  if (stop == null || stop == journey.currentStop) return;
                  runAction(context, () => trip.setCurrentStop(stop));
                },
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: hasNext
                    ? () => runAction(
                          context,
                          () => trip.setCurrentStop(stops[index + 1]),
                        )
                    : null,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(hasNext ? 'Next stop: ${stops[index + 1]}' : 'At the last stop'),
              ),
              const SizedBox(height: 20),
            ],
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: TripStatus.scheduled, label: Text('Scheduled')),
                ButtonSegment(value: TripStatus.inTransit, label: Text('In transit')),
              ],
              selected: {status},
              onSelectionChanged: (s) {
                if (s.first != journey.status) {
                  runAction(context, () => trip.setStatus(s.first));
                }
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'End this trip?',
                  message:
                      'The trip is marked completed and leaves your active list. You can start a new one afterwards.',
                  confirmLabel: 'End trip',
                );
                if (ok && context.mounted) {
                  await runAction(
                    context,
                    () => trip.setStatus(TripStatus.completed),
                    success: 'Trip ended.',
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.35)),
              ),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('End trip'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OccupancyCard extends StatelessWidget {
  const _OccupancyCard({required this.summary});

  final OccupancySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader(
              icon: Icons.groups_rounded,
              title: 'Occupancy',
              trailing: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${summary.total}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                    TextSpan(
                      text: ' / ${OccupancySummary.capacity}',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (final zone in const [
              Zone.priority,
              Zone.general,
              Zone.limited,
              Zone.standing,
            ])
              _ZoneBar(zone: zone, occupied: summary.countFor(zone)),
            if (summary.unclassified > 0)
              Text('+ ${summary.unclassified} allocation(s) with an unrecognised seat number',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _ZoneBar extends StatelessWidget {
  const _ZoneBar({required this.zone, required this.occupied});

  final Zone zone;
  final int occupied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = zone.capacity == 0
        ? 0.0
        : (occupied / zone.capacity).clamp(0.0, 1.0).toDouble();
    final color = ratio >= 1 ? scheme.error : zoneColor(zone);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(zone.label, style: theme.textTheme.bodyMedium)),
              Text('$occupied / ${zone.capacity}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}

class _RouteProgressCard extends StatelessWidget {
  const _RouteProgressCard({
    required this.journey,
    required this.stops,
    required this.route,
    required this.forward,
  });

  final JourneyInstance journey;
  final List<String> stops;
  final RouteInfo route;
  final bool forward;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final index = stops.indexWhere(
        (s) => s.toLowerCase() == journey.currentStop.trim().toLowerCase());

    final km = route.kmAt(journey.currentStop);
    final travelled = km == null ? null : (forward ? km : route.distanceKm - km);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardHeader(
              icon: Icons.route_rounded,
              title: 'Route progress',
              trailing: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RouteScreen()),
                ),
                child: const Text('All stops'),
              ),
            ),
            const SizedBox(height: 16),
            if (index == -1)
              Text('Set the current stop to track progress.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline))
            else ...[
              LinearProgressIndicator(
                value: (index + 1) / stops.length,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                'Stop ${index + 1} of ${stops.length}'
                '${travelled == null ? '' : '  ·  ${travelled.round()} of ${route.distanceKm.round()} km'}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllocationsSection extends StatelessWidget {
  const _AllocationsSection({required this.allocations, required this.error});

  final List<SeatAllocation> allocations;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text('Seat allocations (${allocations.length})',
              style: theme.textTheme.titleMedium),
        ),
        if (error != null)
          Text('Could not load seat allocations: $error',
              style: TextStyle(color: theme.colorScheme.error))
        else if (allocations.isEmpty)
          Text('No seats allocated on this trip yet.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline))
        else
          for (final allocation in allocations) _AllocationTile(allocation: allocation),
      ],
    );
  }
}

class _AllocationTile extends StatelessWidget {
  const _AllocationTile({required this.allocation});

  final SeatAllocation allocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final color = zoneColor(allocation.zone);
    final hasStops =
        allocation.boardingStop.isNotEmpty || allocation.alightingStop.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
              child: Icon(Icons.event_seat_rounded, color: color, size: 22),
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
                        allocation.seatNumber.isEmpty
                            ? '(no seat number)'
                            : 'Seat ${allocation.seatNumber}',
                        style: theme.textTheme.titleSmall,
                      ),
                      StatusPill(label: allocation.zone.label, color: color),
                    ],
                  ),
                  if (hasStops) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(allocation.boardingStop, style: theme.textTheme.bodySmall),
                        Icon(Icons.arrow_right_alt_rounded,
                            size: 18, color: theme.colorScheme.outline),
                        Text(allocation.alightingStop, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(allocation.referenceCode, style: muted),
                      if (allocation.allocationType.isNotEmpty &&
                          allocation.allocationType != 'auto')
                        Text(humanize(allocation.allocationType), style: muted),
                      if (allocation.priorityReserved)
                        const StatusPill(
                          label: 'priority full, moved to General',
                          color: kWarning,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text('Risk', style: theme.textTheme.labelSmall?.copyWith(color: kMuted)),
                  Text(allocation.riskScore.toStringAsFixed(2),
                      style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
