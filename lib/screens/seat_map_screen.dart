import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/occupancy_summary.dart';
import '../models/seat_allocation.dart';
import '../models/seat_map_layout.dart';
import '../models/zone.dart';
import '../providers/journey_stream_provider.dart';
import '../utils/format.dart';
import '../widgets/trip_gate.dart';

/// Read-only live seat map of the active trip, built from its active seat
/// allocations and laid out like the passenger app's 64-seat bus.
class SeatMapScreen extends StatelessWidget {
  const SeatMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TripGate(
      noTripDetail: 'Start a trip on the Trip tab to see its seat map.',
      builder: (context, journey) {
        final trip = context.watch<JourneyStreamProvider>();
        return _SeatMap(allocations: trip.allocations, summary: trip.occupancy);
      },
    );
  }
}

class _SeatMap extends StatelessWidget {
  const _SeatMap({required this.allocations, required this.summary});

  final List<SeatAllocation> allocations;
  final OccupancySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layoutSeats = SeatMapLayout.allSeats.toSet();

    final bySeat = <String, SeatAllocation>{
      for (final a in allocations)
        if (a.zone != Zone.standing) a.seatNumber.trim().toUpperCase(): a,
    };
    final standing = [
      for (final a in allocations)
        if (a.zone == Zone.standing) a,
    ];
    final unplaced = bySeat.keys.where((s) => !layoutSeats.contains(s)).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final zone in const [
              Zone.priority,
              Zone.general,
              Zone.limited,
              Zone.standing,
            ])
              _LegendChip(zone: zone, occupied: summary.countFor(zone)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Filled seats are occupied. An orange dot marks a passenger moved from '
          'Priority to General because the last Priority seats were held back. Tap a seat for details.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Six seats and an aisle gap across the available width.
                final aisle = 20.0;
                final cell = ((constraints.maxWidth - aisle - 5 * 6) / 6)
                    .clamp(28.0, 52.0);
                return Column(
                  children: [
                    _BusEnd(label: 'FRONT', icon: Icons.airline_seat_recline_normal),
                    const SizedBox(height: 12),
                    for (final row in SeatMapLayout.rows)
                      _SeatRow(
                        row: row,
                        size: cell,
                        aisle: aisle,
                        bySeat: bySeat,
                      ),
                    const SizedBox(height: 4),
                    const _BusEnd(label: 'REAR', icon: Icons.sensor_door_outlined),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Standing  ${standing.length} / ${SeatMapLayout.standingSlots}',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < SeatMapLayout.standingSlots; i++)
                      _StandingSlot(
                        index: i + 1,
                        allocation: i < standing.length ? standing[i] : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (unplaced > 0) ...[
          const SizedBox(height: 12),
          Text(
            '$unplaced allocation(s) have a seat number that is not on the map. '
            'They are still counted in the totals and listed on the Trip tab.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.zone, required this.occupied});

  final Zone zone;
  final int occupied;

  @override
  Widget build(BuildContext context) {
    final color = zoneColor(zone);
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text('${zone.label} $occupied/${zone.capacity}'),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}

class _BusEnd extends StatelessWidget {
  const _BusEnd({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, letterSpacing: 2, color: color)),
      ],
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.row,
    required this.size,
    required this.aisle,
    required this.bySeat,
  });

  final SeatRowLayout row;
  final double size;
  final double aisle;
  final Map<String, SeatAllocation> bySeat;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final children = <Widget>[];

    for (var i = 0; i < row.cells.length; i++) {
      // Row 12: the first two cells are one block, the rear door.
      if (row.rearDoor && i == 1) continue;
      if (i > 0) children.add(const SizedBox(width: 6));

      final seat = row.cells[i];
      if (seat != null) {
        children.add(_SeatCell(seat: seat, size: size, allocation: bySeat[seat]));
      } else if (row.rearDoor && i == 0) {
        children.add(SizedBox(
          width: size * 2 + 6,
          height: size,
          child: Icon(Icons.sensor_door_outlined, color: outline),
        ));
      } else {
        children.add(SizedBox(width: aisle));
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
    );
  }
}

class _SeatCell extends StatelessWidget {
  const _SeatCell({required this.seat, required this.size, required this.allocation});

  final String seat;
  final double size;
  final SeatAllocation? allocation;

  @override
  Widget build(BuildContext context) {
    final zone = Zone.fromSeatNumber(seat);
    final color = zoneColor(zone);
    final occupied = allocation != null;

    final box = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: occupied ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: occupied ? 1 : 0.45)),
      ),
      child: Text(
        seat,
        style: TextStyle(
          fontSize: size < 36 ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: occupied ? Colors.white : color,
        ),
      ),
    );

    final marked = Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        if (allocation?.priorityReserved ?? false)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );

    if (!occupied) return marked;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showAllocationDetails(context, allocation!),
      child: marked,
    );
  }
}

class _StandingSlot extends StatelessWidget {
  const _StandingSlot({required this.index, required this.allocation});

  final int index;
  final SeatAllocation? allocation;

  @override
  Widget build(BuildContext context) {
    final color = zoneColor(Zone.standing);
    final occupied = allocation != null;
    final slot = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: occupied ? color : color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: occupied ? 1 : 0.45)),
      ),
      child: Icon(Icons.accessibility_new,
          size: 22, color: occupied ? Colors.white : color),
    );
    if (!occupied) return slot;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => showAllocationDetails(context, allocation!),
      child: slot,
    );
  }
}

/// Bottom sheet with everything the conductor needs to check a passenger.
void showAllocationDetails(BuildContext context, SeatAllocation a) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      Widget row(String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(label,
                      style: TextStyle(color: theme.colorScheme.outline)),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          );

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Seat ${a.seatNumber}  ·  ${a.zone.label}',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              row('Reference', a.referenceCode),
              row('Boards', a.boardingStop.isEmpty ? '—' : a.boardingStop),
              row('Alights', a.alightingStop.isEmpty ? '—' : a.alightingStop),
              row('Risk score', a.riskScore.toStringAsFixed(2)),
              row('Allocation', humanize(a.allocationType)),
              row('Status', humanize(a.status)),
              row('Priority reserved',
                  a.priorityReserved ? 'Yes: moved from Priority to General' : 'No'),
              row('Booked', formatDateTime(a.allocationDatetime)),
            ],
          ),
        ),
      );
    },
  );
}
