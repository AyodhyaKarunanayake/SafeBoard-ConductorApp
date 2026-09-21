import 'zone.dart';

/// One row of the bus as drawn on the seat map. [cells] is left to right;
/// null is the aisle gap (or, in row 12, the space taken by the rear door).
class SeatRowLayout {
  const SeatRowLayout(this.row, this.cells, {this.rearDoor = false});

  final int row;
  final List<String?> cells;

  /// Row 12 has no left pair: the rear door occupies that space.
  final bool rearDoor;

  Iterable<String> get seats => cells.whereType<String>();
}

/// Physical seat map of the Route 87 bus, identical to the one the passenger
/// app allocates from: 64 seats plus a separate standing allowance.
///
///  * rows 1-11: A,B | aisle | C,D,E  (5 seats each = 55)
///  * row 12:    rear door | aisle | C,D,E            (3)
///  * row 13:    one unbroken bench A-F               (6)
class SeatMapLayout {
  const SeatMapLayout._();

  static const int standingSlots = 6;

  static final List<SeatRowLayout> rows = List.unmodifiable([
    for (var row = 1; row <= 11; row++)
      SeatRowLayout(row, ['${row}A', '${row}B', null, '${row}C', '${row}D', '${row}E']),
    const SeatRowLayout(12, [null, null, null, '12C', '12D', '12E'], rearDoor: true),
    const SeatRowLayout(13, ['13A', '13B', '13C', '13D', '13E', '13F']),
  ]);

  static List<String> get allSeats =>
      [for (final row in rows) ...row.seats];

  static int get totalSeats => allSeats.length;

  static int seatsInZone(Zone zone) =>
      allSeats.where((s) => Zone.fromSeatNumber(s) == zone).length;
}
