import '../data/field_compat.dart';

/// A row of the `buses` collection: one recurring scheduled trip template
/// (read-only reference data).
class BusInfo {
  const BusInfo({
    required this.busId,
    required this.busNumber,
    required this.routeId,
    required this.busType,
    required this.departureHour,
    required this.departureMinute,
    required this.durationMinutes,
    required this.startPoint,
    required this.endPoint,
    required this.fareLkr,
    required this.conductorId,
  });

  final String busId;
  final String busNumber;
  final String routeId;
  final String busType;
  final int departureHour;
  final int departureMinute;
  final int durationMinutes;
  final String startPoint;
  final String endPoint;
  final double fareLkr;
  final String conductorId;

  String get scheduledTime =>
      '${departureHour.toString().padLeft(2, '0')}:${departureMinute.toString().padLeft(2, '0')}';

  factory BusInfo.fromMap(Map<String, dynamic> map, String docId) {
    final duration = asInt(pick(map, 'durationMinutes', 'duration_minutes'));
    return BusInfo(
      busId: asString(pick(map, 'busId', 'bus_id'), docId),
      busNumber: asString(pick(map, 'busNumber', 'bus_number'), docId),
      routeId: asString(pick(map, 'routeId', 'route_id')),
      busType: asString(pick(map, 'busType', 'bus_type')),
      departureHour: asInt(pick(map, 'departureHour', 'departure_hour')),
      departureMinute: asInt(pick(map, 'departureMinute', 'departure_minute')),
      durationMinutes: duration > 0 ? duration : 480,
      startPoint: asString(pick(map, 'startPoint', 'start_point')),
      endPoint: asString(pick(map, 'endPoint', 'end_point')),
      fareLkr: asDouble(pick(map, 'fareLkr', 'fare_lkr')),
      conductorId: asString(pick(map, 'conductorId', 'conductor_id')),
    );
  }
}
