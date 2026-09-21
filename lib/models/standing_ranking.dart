import 'route_info.dart';
import 'seat_allocation.dart';

/// A standing passenger who could be given a freed seat, with how much of the
/// journey they still have to travel.
class StandingCandidate {
  const StandingCandidate({
    required this.allocation,
    required this.remainingStops,
    required this.remainingKm,
    required this.destinationKnown,
  });

  final SeatAllocation allocation;

  /// Stops from the bus's current stop to the passenger's alighting stop
  /// (0 if they have already passed it or it is unknown).
  final int remainingStops;

  /// Kilometres left to the alighting stop, when the route has distances.
  final double? remainingKm;

  /// False when the alighting stop isn't on the route, so nothing is known
  /// about how far they are going.
  final bool destinationKnown;
}

/// Ranks [standing] passengers by how far each still has to travel, furthest
/// first: the person with the longest standing journey ahead benefits most from
/// a seat.
///
/// [stopsInTravelOrder] is the route in the direction the bus is heading
/// (Jaffna-start buses run it backwards), and [currentStop] is where the bus is
/// now. Distance is measured along the route from there to each passenger's
/// alighting stop; kilometres are used when the route has them for every
/// candidate, otherwise the number of stops. Ties go to whoever has been
/// standing longest (earliest booking). Passengers who have passed their stop,
/// or whose destination is unknown, rank last.
List<StandingCandidate> rankStandingPassengers({
  required Iterable<SeatAllocation> standing,
  required List<String> stopsInTravelOrder,
  required String currentStop,
  RouteInfo? route,
}) {
  int indexOf(String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return -1;
    return stopsInTravelOrder.indexWhere((s) => s.trim().toLowerCase() == wanted);
  }

  // If the bus's position isn't on the route, count from the start.
  final rawCurrent = indexOf(currentStop);
  final current = rawCurrent == -1 ? 0 : rawCurrent;

  final candidates = <StandingCandidate>[];
  for (final a in standing) {
    final to = indexOf(a.alightingStop);
    final known = to != -1;
    final stops = known && to > current ? to - current : 0;

    double? km;
    if (known && to > current && route != null) {
      final from = route.kmAt(currentStop);
      final target = route.kmAt(a.alightingStop);
      if (from != null && target != null) km = (target - from).abs();
    }
    candidates.add(StandingCandidate(
      allocation: a,
      remainingStops: stops,
      remainingKm: km,
      destinationKnown: known,
    ));
  }

  // Kilometres only if every candidate that has somewhere to go has them, so the
  // comparison is never between unlike measures.
  final useKm = candidates.isNotEmpty &&
      candidates.where((c) => c.remainingStops > 0).every((c) => c.remainingKm != null);

  int byDistance(StandingCandidate a, StandingCandidate b) {
    final primary = useKm
        ? (b.remainingKm ?? 0).compareTo(a.remainingKm ?? 0)
        : b.remainingStops.compareTo(a.remainingStops);
    if (primary != 0) return primary;
    final ta = a.allocation.allocationDatetime?.millisecondsSinceEpoch;
    final tb = b.allocation.allocationDatetime?.millisecondsSinceEpoch;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  }

  candidates.sort(byDistance);
  return candidates;
}
