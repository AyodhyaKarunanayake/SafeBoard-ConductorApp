import 'seat_allocation.dart';
import 'zone.dart';

/// A passenger on this bus ended their journey, so their seat (or standing
/// place) is free again.
class SeatFreedEvent {
  const SeatFreedEvent({required this.id, required this.allocation, required this.at});

  /// Unique per event (the allocation id plus when it was noticed).
  final String id;

  /// The passenger's allocation as it was while they were on board.
  final SeatAllocation allocation;
  final DateTime at;

  String get seat => allocation.seatNumber;

  /// A real seat was freed (not a standing place), so it can be offered to a
  /// standing passenger.
  bool get wasSeated => allocation.zone != Zone.standing && allocation.zone != Zone.unknown;
}
