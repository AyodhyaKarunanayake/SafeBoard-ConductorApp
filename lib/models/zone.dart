/// Seating zones of the Route 87 bus, with their fixed capacities.
enum Zone {
  priority('Priority', 15),
  general('General', 15),
  limited('Limited', 34),
  standing('Standing', 6),
  unknown('Unknown', 0);

  const Zone(this.label, this.capacity);

  final String label;
  final int capacity;

  /// Derives the zone from a seat number, using the same physical seat map
  /// as the passenger app's allocateSeat function: rows 1-3 are Priority,
  /// 4-6 General, 7-13 Limited (e.g. "2A", "11C"); "Standing-N" is Standing.
  static Zone fromSeatNumber(String seatNumber) {
    final seat = seatNumber.trim();
    if (seat.toLowerCase().startsWith('standing')) return Zone.standing;

    final match = RegExp(r'^(\d+)').firstMatch(seat);
    if (match == null) return Zone.unknown;

    final row = int.parse(match.group(1)!);
    if (row >= 1 && row <= 3) return Zone.priority;
    if (row >= 4 && row <= 6) return Zone.general;
    if (row >= 7 && row <= 13) return Zone.limited;
    return Zone.unknown;
  }
}
