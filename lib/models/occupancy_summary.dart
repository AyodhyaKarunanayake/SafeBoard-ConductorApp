import 'seat_allocation.dart';
import 'zone.dart';

/// Live occupancy of a trip, counted from its active seat allocations (the
/// source of truth in the passenger app's data model).
class OccupancySummary {
  const OccupancySummary({
    this.priority = 0,
    this.general = 0,
    this.limited = 0,
    this.standing = 0,
    this.unclassified = 0,
  });

  final int priority;
  final int general;
  final int limited;
  final int standing;

  /// Allocations whose seat number matches no zone; still counted in [total].
  final int unclassified;

  static const OccupancySummary empty = OccupancySummary();

  /// 64 seats + 6 standing.
  static int get capacity =>
      Zone.priority.capacity +
      Zone.general.capacity +
      Zone.limited.capacity +
      Zone.standing.capacity;

  int get total => priority + general + limited + standing + unclassified;

  int countFor(Zone zone) {
    switch (zone) {
      case Zone.priority:
        return priority;
      case Zone.general:
        return general;
      case Zone.limited:
        return limited;
      case Zone.standing:
        return standing;
      case Zone.unknown:
        return unclassified;
    }
  }

  factory OccupancySummary.fromAllocations(Iterable<SeatAllocation> allocations) {
    var priority = 0, general = 0, limited = 0, standing = 0, other = 0;
    for (final allocation in allocations) {
      switch (allocation.zone) {
        case Zone.priority:
          priority++;
        case Zone.general:
          general++;
        case Zone.limited:
          limited++;
        case Zone.standing:
          standing++;
        case Zone.unknown:
          other++;
      }
    }
    return OccupancySummary(
      priority: priority,
      general: general,
      limited: limited,
      standing: standing,
      unclassified: other,
    );
  }

  /// low / moderate / high / critical, by share of total capacity. The four
  /// labels are the passenger app's; the thresholds are this app's own.
  String get crowdingLevel {
    final ratio = total / capacity;
    if (ratio < 0.4) return 'low';
    if (ratio < 0.7) return 'moderate';
    if (ratio < 0.9) return 'high';
    return 'critical';
  }

  /// The journey_instances fields the conductor app keeps in step with the
  /// allocations. `current_occupancy` is deliberately absent: the passenger
  /// app increments it per booking, so overwriting it here could double count.
  Map<String, Object?> toJourneyCounters() => {
        'priority_occupied': priority,
        'general_occupied': general,
        'limited_occupied': limited,
        'standing_count': standing,
        'crowding_level': crowdingLevel,
      };
}
