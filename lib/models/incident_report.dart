import '../data/field_compat.dart';

/// Values of incident_reports.status. The passenger app creates 'pending' for a
/// normal report and 'escalated' for an SOS, and shows whatever status it finds
/// as plain text, so the conductor's 'acknowledged' and 'resolved' are safe.
class IncidentStatus {
  const IncidentStatus._();

  static const String pending = 'pending';
  static const String escalated = 'escalated';
  static const String acknowledged = 'acknowledged';
  static const String resolved = 'resolved';

  /// The statuses a conductor can set. 'escalated' is only ever set by the
  /// passenger app's SOS button.
  static const List<String> all = [pending, acknowledged, resolved];
}

class IncidentReport {
  const IncidentReport({
    required this.incidentId,
    required this.journeyId,
    required this.reporterPassengerId,
    required this.incidentType,
    required this.incidentDatetime,
    required this.seatLocation,
    required this.severityLevel,
    required this.description,
    required this.actionTaken,
    required this.status,
    required this.resolutionDate,
  });

  final String incidentId;
  final String journeyId;
  final String reporterPassengerId;
  final String incidentType;
  final DateTime? incidentDatetime;
  final String seatLocation;
  final String severityLevel;
  final String description;
  final String actionTaken;
  final String status;
  final DateTime? resolutionDate;

  bool get isResolved => status.trim().toLowerCase() == IncidentStatus.resolved;

  /// True for a report raised by the passenger app's SOS button. The passenger
  /// app numbers those `SOS_<millis>` (ordinary reports are `INC_<millis>`) and
  /// describes them "SOS triggered by passenger...".
  bool get isSos =>
      incidentId.toUpperCase().contains('SOS_') ||
      description.trim().toLowerCase().startsWith('sos triggered');

  /// An SOS nobody has acknowledged yet: the passenger app files it as
  /// 'escalated'. These are what the conductor must see immediately.
  bool get isAwaitingAcknowledgement {
    final s = status.trim().toLowerCase();
    return isSos && (s == IncidentStatus.escalated || s == IncidentStatus.pending);
  }

  /// 0 = high, 1 = medium, 2 = low/unknown; for sorting the inbox.
  int get severityRank {
    switch (severityLevel.trim().toLowerCase()) {
      case 'high':
        return 0;
      case 'medium':
        return 1;
      default:
        return 2;
    }
  }

  factory IncidentReport.fromMap(Map<String, dynamic> map, String docId) {
    return IncidentReport(
      incidentId: asString(pick(map, 'incidentId', 'incident_id'), docId),
      journeyId: asString(pick(map, 'journeyId', 'journey_id')),
      reporterPassengerId: asString(
        pick(map, 'reporterPassengerId', 'reporter_passenger_id'),
      ),
      incidentType: asString(pick(map, 'incidentType', 'incident_type')),
      incidentDatetime:
          asDateTime(pick(map, 'incidentDatetime', 'incident_datetime')),
      seatLocation: asString(pick(map, 'seatLocation', 'seat_location')),
      severityLevel: asString(pick(map, 'severityLevel', 'severity_level')),
      description: asString(map['description']),
      actionTaken: asString(pick(map, 'actionTaken', 'action_taken')),
      status: asString(map['status']),
      resolutionDate:
          asDateTime(pick(map, 'resolutionDate', 'resolution_date')),
    );
  }
}
