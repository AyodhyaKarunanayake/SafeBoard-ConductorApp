import '../data/field_compat.dart';

/// Route 87 (Colombo - Jaffna) stops in Colombo -> Jaffna order. Used only when
/// the `routes/R_87` document can't be read.
const List<String> kRoute87Stops = [
  'Colombo (Pettah)',
  'Kelaniya',
  'Peliyagoda Interchange',
  'Wattala',
  'Kandana Junction',
  'Ja-Ela',
  'Seeduwa',
  'Katunayake Junction',
  'Negombo Bus Stand',
  'Kochchikade',
  'Wennappuwa',
  'Madampe',
  'Marawila Junction',
  'Nattandiya',
  'Chilaw Bus Stand',
  'Battuluoya',
  'Madurankuli',
  'Mundel',
  'Puttalam Main Stand',
  'Anamaduwa',
  'Saliyawewa Junction',
  'Nochchiyagama',
  'Tirappane Junction',
  'Anuradhapura New Town',
  'Medawachchiya Junction',
  'Cheddikulam',
  'Vavuniya Bus Terminal',
  'Omanthai',
  'Puliyankulam',
  'Mankulam Junction',
  'Akkarayankulam',
  'Kilinochchi Central Stand',
  'Elephant Pass',
  'Pallai',
  'Chavakachcheri',
  'Kaithady',
  'Jaffna Main Bus Stand',
];

/// A row of the `routes` collection (read-only reference data).
class RouteInfo {
  const RouteInfo({
    required this.routeId,
    required this.routeName,
    required this.distanceKm,
    required this.stops,
    this.stopDistancesKm = const [],
  });

  final String routeId;
  final String routeName;
  final double distanceKm;

  /// Always in Colombo -> Jaffna order, whichever way a bus is heading.
  final List<String> stops;

  /// Cumulative km from the first stop, same order as [stops]; may be empty.
  final List<double> stopDistancesKm;

  static const RouteInfo route87Fallback = RouteInfo(
    routeId: 'R_87',
    routeName: 'Route 87',
    distanceKm: 396,
    stops: kRoute87Stops,
  );

  factory RouteInfo.fromMap(Map<String, dynamic> map, String docId) {
    final rawStops = map['stops'];
    final rawKm = pick(map, 'stopDistancesKm', 'stop_distances_km');
    return RouteInfo(
      routeId: asString(pick(map, 'routeId', 'route_id'), docId),
      routeName: asString(pick(map, 'routeName', 'route_name'), docId),
      distanceKm: asDouble(pick(map, 'distanceKm', 'distance_km')),
      stops: rawStops is List ? [for (final s in rawStops) '$s'] : const [],
      stopDistancesKm:
          rawKm is List ? [for (final d in rawKm) asDouble(d)] : const [],
    );
  }

  bool get hasStops => stops.isNotEmpty;

  /// The stops in the order a bus starting at [startPoint] travels them: a
  /// Jaffna-start bus runs the list backwards.
  List<String> stopsFrom(String startPoint) {
    if (stops.isEmpty) return stops;
    final start = startPoint.trim().toLowerCase();
    final reversed = start.isNotEmpty && start == stops.last.trim().toLowerCase();
    return reversed ? stops.reversed.toList() : stops;
  }

  /// Km of [stopName] from the first stop (Colombo), or null if unknown.
  double? kmAt(String stopName) {
    final i = stops.indexWhere((s) => s.toLowerCase() == stopName.toLowerCase());
    if (i == -1 || i >= stopDistancesKm.length) return null;
    return stopDistancesKm[i];
  }
}
