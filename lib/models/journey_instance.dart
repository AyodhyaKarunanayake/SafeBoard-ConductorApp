import '../data/field_compat.dart';

/// Values of journey_instances.status used by the conductor app.
class TripStatus {
  const TripStatus._();

  static const String scheduled = 'scheduled';
  static const String inTransit = 'in_transit';
  static const String completed = 'completed';
}

class JourneyInstance {
  const JourneyInstance({
    required this.journeyId,
    required this.busId,
    required this.routeId,
    required this.conductorId,
    required this.departureDatetime,
    required this.arrivalDatetime,
    required this.currentOccupancy,
    required this.standingCount,
    required this.currentStop,
    required this.crowdingLevel,
    required this.status,
    required this.priorityOccupied,
    required this.generalOccupied,
    required this.limitedOccupied,
  });

  final String journeyId;
  final String busId;
  final String routeId;
  final String conductorId;
  final DateTime? departureDatetime;
  final DateTime? arrivalDatetime;
  final int currentOccupancy;
  final int standingCount;
  final String currentStop;
  final String crowdingLevel;
  final String status;
  final int priorityOccupied;
  final int generalOccupied;
  final int limitedOccupied;

  bool get isCompleted => status.trim().toLowerCase() == TripStatus.completed;

  factory JourneyInstance.fromMap(Map<String, dynamic> map, String docId) {
    return JourneyInstance(
      journeyId: asString(pick(map, 'journeyId', 'journey_id'), docId),
      busId: asString(pick(map, 'busId', 'bus_id')),
      routeId: asString(pick(map, 'routeId', 'route_id')),
      conductorId: asString(pick(map, 'conductorId', 'conductor_id')),
      departureDatetime:
          asDateTime(pick(map, 'departureDatetime', 'departure_datetime')),
      arrivalDatetime:
          asDateTime(pick(map, 'arrivalDatetime', 'arrival_datetime')),
      currentOccupancy: asInt(pick(map, 'currentOccupancy', 'current_occupancy')),
      standingCount: asInt(pick(map, 'standingCount', 'standing_count')),
      currentStop: asString(pick(map, 'currentStop', 'current_stop')),
      crowdingLevel: asString(pick(map, 'crowdingLevel', 'crowding_level')),
      status: asString(map['status']),
      priorityOccupied:
          asInt(pick(map, 'priorityOccupied', 'priority_occupied')),
      generalOccupied: asInt(pick(map, 'generalOccupied', 'general_occupied')),
      limitedOccupied: asInt(pick(map, 'limitedOccupied', 'limited_occupied')),
    );
  }
}
