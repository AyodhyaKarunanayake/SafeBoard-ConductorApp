import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safeboard_conductor/data/field_compat.dart';
import 'package:safeboard_conductor/models/incident_report.dart';
import 'package:safeboard_conductor/models/journey_instance.dart';
import 'package:safeboard_conductor/models/seat_allocation.dart';
import 'package:safeboard_conductor/models/zone.dart';
import 'package:safeboard_conductor/providers/conductor_provider.dart';
import 'package:safeboard_conductor/screens/incidents_screen.dart';
import 'package:safeboard_conductor/utils/format.dart';

void main() {
  group('Zone.fromSeatNumber', () {
    test('maps rows to zones per the Route 87 seat map', () {
      expect(Zone.fromSeatNumber('1A'), Zone.priority);
      expect(Zone.fromSeatNumber('3E'), Zone.priority);
      expect(Zone.fromSeatNumber('4A'), Zone.general);
      expect(Zone.fromSeatNumber('6D'), Zone.general);
      expect(Zone.fromSeatNumber('7A'), Zone.limited);
      expect(Zone.fromSeatNumber('12C'), Zone.limited);
      expect(Zone.fromSeatNumber('13F'), Zone.limited);
    });

    test('recognises standing and falls back to unknown', () {
      expect(Zone.fromSeatNumber('Standing-3'), Zone.standing);
      expect(Zone.fromSeatNumber(''), Zone.unknown);
      expect(Zone.fromSeatNumber('X9'), Zone.unknown);
      expect(Zone.fromSeatNumber('14A'), Zone.unknown);
    });

    test('capacities match the bus layout', () {
      expect(Zone.priority.capacity, 15);
      expect(Zone.general.capacity, 15);
      expect(Zone.limited.capacity, 34);
      expect(Zone.standing.capacity, 6);
    });
  });

  group('model parsing accepts both schema styles', () {
    test('JourneyInstance from camelCase + Timestamp', () {
      final journey = JourneyInstance.fromMap({
        'journeyId': 'J1',
        'conductorId': 'CND_1',
        'departureDatetime': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 8)),
        'priorityOccupied': 4,
        'standingCount': 2,
      }, 'doc-id');

      expect(journey.journeyId, 'J1');
      expect(journey.conductorId, 'CND_1');
      // Timestamp.toDate() is local time; compare the instant, not the zone.
      expect(
        journey.departureDatetime!.isAtSameMomentAs(DateTime.utc(2026, 9, 1, 8)),
        isTrue,
      );
      expect(journey.priorityOccupied, 4);
      expect(journey.standingCount, 2);
    });

    test('JourneyInstance from snake_case + ISO string, id falls back to doc id', () {
      final journey = JourneyInstance.fromMap({
        'conductor_id': 'CND_1',
        'departure_datetime': '2026-09-01T08:00:00.000Z',
        'limited_occupied': 9,
      }, 'doc-id');

      expect(journey.journeyId, 'doc-id');
      expect(journey.conductorId, 'CND_1');
      expect(journey.departureDatetime, DateTime.utc(2026, 9, 1, 8));
      expect(journey.limitedOccupied, 9);
    });

    test('missing fields become safe defaults, not exceptions', () {
      final journey = JourneyInstance.fromMap({}, 'doc-id');
      expect(journey.departureDatetime, isNull);
      expect(journey.currentOccupancy, 0);
      expect(journey.currentStop, '');
    });

    test('SeatAllocation derives zone and reads risk score (int or double)', () {
      final a = SeatAllocation.fromMap({
        'seat_number': '5B',
        'risk_score': 1,
        'journey_id': 'J1',
      }, 'alloc_1');
      expect(a.allocationId, 'alloc_1');
      expect(a.zone, Zone.general);
      expect(a.riskScore, 1.0);

      final b = SeatAllocation.fromMap({'seatId': '2A', 'riskScore': 0.05}, 'x');
      expect(b.seatNumber, '2A');
      expect(b.zone, Zone.priority);
      expect(b.riskScore, 0.05);
    });

    test('IncidentReport reads snake_case and nullable resolution date', () {
      final i = IncidentReport.fromMap({
        'incident_type': 'verbal_harassment',
        'severity_level': 'high',
        'incident_datetime': '2026-09-01T08:30:00.000Z',
        'resolution_date': null,
      }, 'inc_1');
      expect(i.incidentId, 'inc_1');
      expect(i.incidentType, 'verbal_harassment');
      expect(i.severityLevel, 'high');
      expect(i.resolutionDate, isNull);
    });
  });

  group('sortNewestFirst', () {
    test('orders newest first with undated items last', () {
      final items = <DateTime?>[
        DateTime(2026, 1, 1),
        null,
        DateTime(2026, 3, 1),
        DateTime(2026, 2, 1),
      ];
      sortNewestFirst<DateTime?>(items, (d) => d);
      expect(items, [
        DateTime(2026, 3, 1),
        DateTime(2026, 2, 1),
        DateTime(2026, 1, 1),
        null,
      ]);
    });
  });

  group('presentation helpers', () {
    test('severityColor: low grey, medium orange, high red', () {
      expect(severityColor('low'), Colors.grey.shade600);
      expect(severityColor('medium'), Colors.orange.shade800);
      expect(severityColor('HIGH'), Colors.red.shade700);
      expect(severityColor('something-else'), Colors.grey.shade600);
    });

    test('humanize', () {
      expect(humanize('unwanted_contact'), 'Unwanted contact');
      expect(humanize(''), '—');
    });

    test('FCM topic name', () {
      expect(ConductorProvider.topicFor('CND_882'), 'conductor_CND_882');
    });
  });
}
