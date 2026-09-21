import 'package:flutter_test/flutter_test.dart';

import 'package:safeboard_conductor/models/incident_report.dart';
import 'package:safeboard_conductor/models/journey_instance.dart';
import 'package:safeboard_conductor/models/seat_allocation.dart';
import 'package:safeboard_conductor/models/seat_map_layout.dart';
import 'package:safeboard_conductor/models/zone.dart';

// Mirrors the documents written by tool/seed_demo_journey.ps1: snake_case
// keys, ISO-8601 "Z" strings with milliseconds, ints and doubles.
void main() {
  test('demo journey document parses with the expected counters', () {
    final journey = JourneyInstance.fromMap({
      'journey_id': 'JRN_DEMO_001',
      'bus_id': 'BUS_NB_8710',
      'route_id': 'R_87',
      'conductor_id': 'CND_TEST',
      'departure_datetime': '2026-09-21T12:00:00.000Z',
      'arrival_datetime': '2026-09-21T19:45:00.000Z',
      'current_occupancy': 31,
      'standing_count': 2,
      'current_stop': 'Kurunegala',
      'crowding_level': 'moderate',
      'status': 'in_transit',
      'priority_occupied': 6,
      'general_occupied': 9,
      'limited_occupied': 14,
    }, 'JRN_DEMO_001');

    expect(journey.conductorId, 'CND_TEST');
    expect(journey.departureDatetime, DateTime.utc(2026, 9, 21, 12));
    expect(journey.arrivalDatetime, DateTime.utc(2026, 9, 21, 19, 45));
    expect(
      journey.priorityOccupied + journey.generalOccupied +
          journey.limitedOccupied + journey.standingCount,
      journey.currentOccupancy,
      reason: 'zone counters should add up to current_occupancy',
    );
    expect(journey.priorityOccupied, lessThanOrEqualTo(Zone.priority.capacity));
    expect(journey.generalOccupied, lessThanOrEqualTo(Zone.general.capacity));
    expect(journey.limitedOccupied, lessThanOrEqualTo(Zone.limited.capacity));
    expect(journey.standingCount, lessThanOrEqualTo(Zone.standing.capacity));
  });

  test('every demo seat maps to the zone the seeder labels it with', () {
    const seats = {
      // sample allocations
      '1A': Zone.priority, '2C': Zone.priority,
      '4B': Zone.general, '5D': Zone.general, '6A': Zone.general,
      '7C': Zone.limited, '9A': Zone.limited, '12D': Zone.limited,
      // live pool (-AddAllocation)
      '1B': Zone.priority, '2A': Zone.priority, '3D': Zone.priority,
      '4D': Zone.general, '5A': Zone.general, '6C': Zone.general,
      '7A': Zone.limited, '8B': Zone.limited, '10E': Zone.limited,
      '11A': Zone.limited,
    };
    seats.forEach((seat, zone) {
      expect(SeatAllocation.fromMap({'seat_number': seat}, 'x').zone, zone,
          reason: 'seat $seat');
    });
  });

  test('the 31-passenger demo plan fits the bus and each zone\'s capacity', () {
    // Mirrors $seatPlan in tool/seed_demo_journey.ps1.
    const plan = {
      Zone.priority: ['1A', '1B', '2A', '2C', '3D', '3E'],
      Zone.general: ['4A', '4B', '5C', '5D', '5E', '6A', '6B', '6D', '6E'],
      Zone.limited: [
        '7A', '7C', '8B', '8D', '9A', '9E', '10B', '10C', '11A', '11D', '12D',
        '13A', '13C', '13F',
      ],
      Zone.standing: ['Standing-1', 'Standing-2'],
    };
    var total = 0;
    plan.forEach((zone, seats) {
      expect(seats.length, lessThanOrEqualTo(zone.capacity), reason: '$zone');
      expect(seats.toSet().length, seats.length, reason: 'no duplicate seats');
      for (final seat in seats) {
        expect(Zone.fromSeatNumber(seat), zone, reason: 'seat $seat');
      }
      total += seats.length;
    });
    expect(total, 31);

    // Every non-standing demo seat exists on the real seat map.
    final onMap = SeatMapLayout.allSeats.toSet();
    for (final seat in [
      ...plan[Zone.priority]!, ...plan[Zone.general]!, ...plan[Zone.limited]!,
    ]) {
      expect(onMap, contains(seat));
    }
  });

  test('demo allocation and incident documents parse', () {
    final allocation = SeatAllocation.fromMap({
      'allocation_id': 'demo_alloc_01',
      'seat_number': '1A',
      'journey_id': 'JRN_DEMO_001',
      'allocation_datetime': '2026-09-21T12:03:00.000Z',
      'risk_score': 0.05,
      'status': 'active',
      'priority_reserved': false,
    }, 'demo_alloc_01');
    expect(allocation.riskScore, 0.05);
    expect(allocation.allocationDatetime, DateTime.utc(2026, 9, 21, 12, 3));

    final open = IncidentReport.fromMap({
      'incident_type': 'unwanted_contact',
      'severity_level': 'high',
      'incident_datetime': '2026-09-21T12:30:00.000Z',
      'resolution_date': null,
    }, 'demo_inc_01');
    expect(open.severityLevel, 'high');
    expect(open.resolutionDate, isNull);

    final resolved = IncidentReport.fromMap({
      'incident_datetime': '2026-09-21T12:40:00.000Z',
      'resolution_date': '2026-09-21T12:35:00.000Z',
    }, 'demo_inc_03');
    expect(resolved.resolutionDate, isNotNull);
  });
}
