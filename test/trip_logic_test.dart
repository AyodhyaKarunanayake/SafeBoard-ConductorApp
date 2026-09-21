import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';

import 'package:safeboard_conductor/data/conductor_repository.dart';
import 'package:safeboard_conductor/models/bus_info.dart';
import 'package:safeboard_conductor/models/incident_report.dart';
import 'package:safeboard_conductor/models/occupancy_summary.dart';
import 'package:safeboard_conductor/models/payment.dart';
import 'package:safeboard_conductor/models/route_info.dart';
import 'package:safeboard_conductor/models/seat_allocation.dart';
import 'package:safeboard_conductor/models/seat_map_layout.dart';
import 'package:safeboard_conductor/models/zone.dart';
import 'package:safeboard_conductor/providers/journey_stream_provider.dart';
import 'package:safeboard_conductor/providers/notifications_provider.dart';
import 'package:safeboard_conductor/screens/incidents_screen.dart';

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

Map<String, dynamic> allocation(String id, String seat,
        {String bus = 'BUS_1',
        String journey = 'JRN_1',
        String status = 'active',
        bool reserved = false}) =>
    {
      'allocation_id': id,
      'booking_id': 'bk_$id',
      'seat_id': seat,
      'seat_number': seat,
      'bus_id': bus,
      'journey_id': journey,
      'allocation_datetime': '2026-09-21T10:00:00.000Z',
      'boarding_stop': 'Colombo (Pettah)',
      'alighting_stop': 'Jaffna Main Bus Stand',
      'allocation_type': 'auto',
      'risk_score': 0.1,
      'status': status,
      'qr_code': 'SB-$journey-$seat-$id',
      'priority_reserved': reserved,
    };

Map<String, dynamic> journey(String id,
        {String conductor = 'CND_T',
        String bus = 'BUS_1',
        String status = 'in_transit',
        String departure = '2026-09-21T09:00:00.000Z'}) =>
    {
      'journey_id': id,
      'bus_id': bus,
      'route_id': 'R_87',
      'conductor_id': conductor,
      'departure_datetime': departure,
      'arrival_datetime': '2026-09-21T17:00:00.000Z',
      'current_occupancy': 0,
      'standing_count': 0,
      'current_stop': 'Colombo (Pettah)',
      'crowding_level': 'low',
      'status': status,
      'priority_occupied': 0,
      'general_occupied': 0,
      'limited_occupied': 0,
    };

void main() {
  group('reference models', () {
    test('seat map has the passenger app\'s 64 seats: 15 / 15 / 34', () {
      expect(SeatMapLayout.totalSeats, 64);
      expect(SeatMapLayout.seatsInZone(Zone.priority), 15);
      expect(SeatMapLayout.seatsInZone(Zone.general), 15);
      expect(SeatMapLayout.seatsInZone(Zone.limited), 34);
      expect(SeatMapLayout.allSeats.toSet().length, 64, reason: 'no duplicates');
      expect(SeatMapLayout.allSeats, containsAll(['12C', '12D', '12E', '13A', '13F']));
      expect(SeatMapLayout.allSeats, isNot(contains('12A')),
          reason: 'row 12 has no left pair (rear door)');
    });

    test('Route 87 fallback has the 37 stops in order', () {
      expect(kRoute87Stops.length, 37);
      expect(kRoute87Stops.first, 'Colombo (Pettah)');
      expect(kRoute87Stops[18], 'Puttalam Main Stand');
      expect(kRoute87Stops.last, 'Jaffna Main Bus Stand');
    });

    test('RouteInfo reverses stops for a bus starting in Jaffna', () {
      const route = RouteInfo.route87Fallback;
      expect(route.stopsFrom('Colombo (Pettah)').first, 'Colombo (Pettah)');
      final back = route.stopsFrom('Jaffna Main Bus Stand');
      expect(back.first, 'Jaffna Main Bus Stand');
      expect(back.last, 'Colombo (Pettah)');
      expect(back.length, 37);
    });

    test('RouteInfo parses a routes document and looks up km', () {
      final route = RouteInfo.fromMap({
        'route_id': 'R_87',
        'route_name': 'Route 87',
        'distance_km': 396.0,
        'stops': ['A', 'B', 'C'],
        'stop_distances_km': [0, 10.5, 20],
      }, 'R_87');
      expect(route.stops, ['A', 'B', 'C']);
      expect(route.kmAt('b'), 10.5);
      expect(route.kmAt('Z'), isNull);
    });

    test('BusInfo parses and defaults a missing duration', () {
      final bus = BusInfo.fromMap({
        'bus_number': 'NB-8710',
        'departure_hour': 5,
        'departure_minute': 30,
        'conductor_id': 'CND_NB_8710',
      }, 'BUS_NB_8710');
      expect(bus.busId, 'BUS_NB_8710');
      expect(bus.scheduledTime, '05:30');
      expect(bus.durationMinutes, 480);
    });

    test('Payment parses the passenger app\'s document', () {
      final p = Payment.fromMap({
        'payment_id': 'pay_1',
        'allocation_id': 'alloc_1',
        'journey_id': 'JRN_1',
        'method': 'conductor',
        'amount_lkr': 1450.0,
        'status': 'pay_on_board',
        'timestamp': '2026-09-21T10:00:00.000Z',
        'reference': 'Pay to conductor onboard',
      }, 'pay_1');
      expect(p.isPayOnBoard, isTrue);
      expect(p.isPaid, isFalse);
      expect(p.amountLkr, 1450.0);
      expect(p.timestamp, DateTime.utc(2026, 9, 21, 10));
    });

    test('SeatAllocation: isActive and the SB-XXXXXX reference format', () {
      final a = SeatAllocation.fromMap(allocation('alloc_123_0', '3A'), 'x');
      expect(a.isActive, isTrue);
      expect(a.referenceCode, matches(RegExp(r'^SB-[0-9A-Z]{6}$')));
      expect(a.referenceCode, SeatAllocation.fromMap(allocation('alloc_123_0', '3A'), 'y').referenceCode,
          reason: 'stable for the same allocation id');
      expect(SeatAllocation.fromMap(allocation('a', '3A', status: 'released'), 'x').isActive, isFalse);
      expect(SeatAllocation.fromMap({'seat_number': '3A'}, 'x').isActive, isTrue,
          reason: 'no status counts as active');
    });

    test('OccupancySummary counts zones and picks a crowding level', () {
      final list = [
        for (final s in ['1A', '2C', '4B', '7A', '7B', '7C', 'Standing-1'])
          SeatAllocation.fromMap(allocation('a_$s', s), s),
      ];
      final summary = OccupancySummary.fromAllocations(list);
      expect(summary.priority, 2);
      expect(summary.general, 1);
      expect(summary.limited, 3);
      expect(summary.standing, 1);
      expect(summary.total, 7);
      expect(summary.crowdingLevel, 'low');

      OccupancySummary of(int seats) => OccupancySummary(limited: seats);
      expect(of(27).crowdingLevel, 'low'); // 27/70 = 0.386
      expect(of(28).crowdingLevel, 'moderate'); // 0.4
      expect(of(49).crowdingLevel, 'high'); // 0.7
      expect(of(63).crowdingLevel, 'critical'); // 0.9
    });

    test('counters written by the conductor never include current_occupancy', () {
      final counters = const OccupancySummary(priority: 6, general: 9).toJourneyCounters();
      expect(counters.keys, containsAll([
        'priority_occupied', 'general_occupied', 'limited_occupied',
        'standing_count', 'crowding_level',
      ]));
      expect(counters.containsKey('current_occupancy'), isFalse,
          reason: 'the passenger app increments this; overwriting could double count');
    });

    test('incident inbox: open first, then worst severity, then newest', () {
      IncidentReport inc(String id, String sev, String status, String when) =>
          IncidentReport.fromMap({
            'incident_id': id,
            'severity_level': sev,
            'status': status,
            'incident_datetime': when,
          }, id);
      final sorted = sortIncidentInbox([
        inc('resolved_high', 'high', 'resolved', '2026-09-21T12:00:00Z'),
        inc('open_low_new', 'low', 'pending', '2026-09-21T11:00:00Z'),
        inc('open_high_old', 'high', 'pending', '2026-09-21T08:00:00Z'),
        inc('open_medium', 'medium', 'acknowledged', '2026-09-21T10:00:00Z'),
        inc('open_high_new', 'high', 'pending', '2026-09-21T09:00:00Z'),
      ]);
      expect(sorted.map((i) => i.incidentId), [
        'open_high_new', 'open_high_old', 'open_medium', 'open_low_new', 'resolved_high',
      ]);
    });
  });

  group('ConductorRepository writes (compatibility with the passenger app)', () {
    late FakeFirebaseFirestore db;
    late ConductorRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = ConductorRepository(db);
    });

    Future<Map<String, dynamic>> read(String path) async =>
        (await db.doc(path).get()).data()!;

    test('createJourney writes snake_case fields with ISO-string dates', () async {
      await repo.createJourney(
        journeyId: 'JRN_87_001',
        busId: 'BUS_NB_8710',
        routeId: 'R_87',
        conductorId: 'CND_T',
        departure: DateTime.utc(2026, 9, 21, 9),
        arrival: DateTime.utc(2026, 9, 21, 17),
        currentStop: 'Colombo (Pettah)',
        occupancy: const OccupancySummary(priority: 2, general: 3, limited: 1, standing: 1),
      );

      final doc = await read('journey_instances/JRN_87_001');
      // Exactly the fields the passenger app's JourneyInstance model defines.
      expect(doc.keys.toSet(), {
        'journey_id', 'bus_id', 'route_id', 'conductor_id', 'departure_datetime',
        'arrival_datetime', 'current_occupancy', 'standing_count', 'current_stop',
        'crowding_level', 'status', 'priority_occupied', 'general_occupied',
        'limited_occupied',
      });
      // ISO strings, NOT Timestamps: the passenger app calls DateTime.parse.
      expect(doc['departure_datetime'], isA<String>());
      expect(doc['departure_datetime'], isNot(isA<Timestamp>()));
      expect(DateTime.parse(doc['departure_datetime'] as String), DateTime.utc(2026, 9, 21, 9));
      expect(DateTime.parse(doc['arrival_datetime'] as String), DateTime.utc(2026, 9, 21, 17));
      expect(doc['status'], 'in_transit');
      expect(doc['current_occupancy'], 7);
      expect(doc['priority_occupied'], 2);
      expect(doc['standing_count'], 1);
    });

    test('createJourney refuses to take over another conductor\'s active trip', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1', conductor: 'CND_OTHER'));

      await expectLater(
        repo.createJourney(
          journeyId: 'JRN_1', busId: 'BUS_1', routeId: 'R_87', conductorId: 'CND_T',
          departure: DateTime.utc(2026), arrival: DateTime.utc(2026),
          currentStop: 'x', occupancy: OccupancySummary.empty,
        ),
        throwsA(isA<TripConflictException>()),
      );
      expect((await read('journey_instances/JRN_1'))['conductor_id'], 'CND_OTHER',
          reason: 'the other conductor\'s trip must be untouched');
    });

    test('createJourney may reuse an id that is completed, mine, or ownerless', () async {
      Future<void> create() => repo.createJourney(
            journeyId: 'JRN_1', busId: 'BUS_1', routeId: 'R_87', conductorId: 'CND_T',
            departure: DateTime.utc(2026), arrival: DateTime.utc(2026),
            currentStop: 'x', occupancy: OccupancySummary.empty,
          );

      await db.doc('journey_instances/JRN_1').set(journey('JRN_1', conductor: 'CND_OTHER', status: 'completed'));
      await create();
      expect((await read('journey_instances/JRN_1'))['conductor_id'], 'CND_T');

      await db.doc('journey_instances/JRN_1').set(journey('JRN_1', conductor: 'CND_T'));
      await create();

      // e.g. a document the passenger app or old function created with only a counter.
      await db.doc('journey_instances/JRN_1').set({'current_occupancy': 3});
      await create();
      expect((await read('journey_instances/JRN_1'))['conductor_id'], 'CND_T');
    });

    test('updateIncident resolves with an ISO string and touches only its 3 fields', () async {
      final original = {
        'incident_id': 'inc_1',
        'journey_id': 'JRN_1',
        'reporter_passenger_id': 'p_1',
        'incident_type': 'unwanted_contact',
        'incident_datetime': '2026-09-21T10:00:00.000Z',
        'seat_location': '5B',
        'severity_level': 'high',
        'description': 'Original description',
        'action_taken': 'Notified Conductor',
        'status': 'pending',
        'resolution_date': null,
      };
      await db.doc('incident_reports/inc_1').set(original);

      await repo.updateIncident('inc_1',
          status: 'resolved', actionTaken: 'Moved passenger', resolvedAt: DateTime.utc(2026, 9, 21, 11));

      final doc = await read('incident_reports/inc_1');
      expect(doc['status'], 'resolved');
      expect(doc['action_taken'], 'Moved passenger');
      expect(doc['resolution_date'], isA<String>());
      expect(DateTime.parse(doc['resolution_date'] as String), DateTime.utc(2026, 9, 21, 11));
      for (final key in original.keys.toSet()..removeAll({'status', 'action_taken', 'resolution_date'})) {
        expect(doc[key], original[key], reason: '$key must be unchanged');
      }
    });

    test('un-resolving an incident clears resolution_date back to null', () async {
      await db.doc('incident_reports/inc_1').set({
        'incident_id': 'inc_1', 'status': 'resolved', 'resolution_date': '2026-09-21T11:00:00.000Z',
      });
      await repo.updateIncident('inc_1', status: 'acknowledged', actionTaken: 'Reopened');
      final doc = await read('incident_reports/inc_1');
      expect(doc['status'], 'acknowledged');
      expect(doc['resolution_date'], isNull);
    });

    test('completePayment changes only status', () async {
      final original = {
        'payment_id': 'pay_1', 'allocation_id': 'alloc_1', 'journey_id': 'JRN_1',
        'method': 'conductor', 'amount_lkr': 1450.0, 'status': 'pay_on_board',
        'timestamp': '2026-09-21T10:00:00.000Z', 'reference': 'Pay to conductor onboard',
      };
      await db.doc('payments/pay_1').set(original);
      await repo.completePayment('pay_1');

      final doc = await read('payments/pay_1');
      expect(doc['status'], 'completed');
      for (final key in original.keys.where((k) => k != 'status')) {
        expect(doc[key], original[key], reason: '$key must be unchanged');
      }
    });

    test('updating a missing record fails instead of creating it', () async {
      await expectLater(repo.completePayment('nope'), throwsA(isA<FirebaseException>()));
      await expectLater(
        repo.updateIncident('nope', status: 'resolved', actionTaken: ''),
        throwsA(isA<FirebaseException>()),
      );
      await expectLater(repo.updateJourney('nope', {'current_stop': 'x'}), throwsA(isA<FirebaseException>()));
      expect((await db.collection('payments').get()).docs, isEmpty);
    });

    test('fetchTripAllocations keeps this bus\'s active seats only', () async {
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A'));
      await db.doc('seat_allocations/a2').set(allocation('a2', '1B', bus: 'BUS_2'));
      await db.doc('seat_allocations/a3').set(allocation('a3', '1C', status: 'released'));
      await db.doc('seat_allocations/a4').set(allocation('a4', '1D', journey: 'JRN_OTHER'));

      final result = await repo.fetchTripAllocations('JRN_1', 'BUS_1');
      expect(result.map((a) => a.allocationId), ['a1']);
    });
  });

  group('JourneyStreamProvider', () {
    late FakeFirebaseFirestore db;
    late ConductorRepository repo;
    late NotificationsProvider notifications;
    late JourneyStreamProvider provider;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = ConductorRepository(db);
      notifications = NotificationsProvider();
      provider = JourneyStreamProvider(repository: repo);
    });

    tearDown(() {
      provider.dispose();
      notifications.dispose();
    });

    Future<void> bind([String id = 'CND_T']) async {
      provider.bind(id, notifications: notifications);
      await pump();
      await pump();
    }

    test('picks the latest non-completed journey', () async {
      await db.doc('journey_instances/OLD').set(journey('OLD', departure: '2026-09-20T09:00:00.000Z'));
      await db.doc('journey_instances/NEW').set(journey('NEW', departure: '2026-09-21T09:00:00.000Z'));
      await db.doc('journey_instances/DONE').set(journey('DONE', status: 'completed', departure: '2026-09-22T09:00:00.000Z'));
      await db.doc('journey_instances/THEIRS').set(journey('THEIRS', conductor: 'CND_OTHER', departure: '2026-09-23T09:00:00.000Z'));

      await bind();
      expect(provider.journey?.journeyId, 'NEW');
      expect(provider.isLoading, isFalse);
    });

    test('no journey for the conductor means no active trip', () async {
      await db.doc('journey_instances/THEIRS').set(journey('THEIRS', conductor: 'CND_OTHER'));
      await bind();
      expect(provider.journey, isNull);
      expect(provider.allocations, isEmpty);
    });

    test('allocations are limited to this bus and active seats; occupancy is derived', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1'));
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A'));
      await db.doc('seat_allocations/a2').set(allocation('a2', '4B'));
      await db.doc('seat_allocations/a3').set(allocation('a3', '7C', bus: 'BUS_2'));
      await db.doc('seat_allocations/a4').set(allocation('a4', '8A', status: 'released'));
      await db.doc('seat_allocations/a5').set(allocation('a5', 'Standing-1'));

      await bind();
      expect(provider.allocations.map((a) => a.allocationId).toSet(), {'a1', 'a2', 'a5'});
      final o = provider.occupancy;
      expect((o.priority, o.general, o.limited, o.standing), (1, 1, 0, 1));
    });

    test('existing data does not raise alerts, new data does', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1'));
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A'));
      await db.doc('incident_reports/i1').set({
        'incident_id': 'i1', 'journey_id': 'JRN_1', 'incident_type': 'other',
        'incident_datetime': '2026-09-21T10:00:00.000Z', 'severity_level': 'low', 'status': 'pending',
      });
      await bind();
      expect(notifications.items, isEmpty, reason: 'nothing was new');

      await db.doc('seat_allocations/a2').set(allocation('a2', '4B'));
      await pump();
      expect(notifications.items.length, 1);
      expect(notifications.items.first.title, 'New passenger allocated');
      expect(notifications.items.first.body, contains('4B'));

      await db.doc('incident_reports/i2').set({
        'incident_id': 'i2', 'journey_id': 'JRN_1', 'incident_type': 'unwanted_contact',
        'seat_location': '5B', 'incident_datetime': '2026-09-21T11:00:00.000Z',
        'severity_level': 'high', 'status': 'pending',
      });
      await pump();
      expect(notifications.items.first.title, 'New incident reported');
      expect(notifications.items.first.body, contains('Unwanted contact'));
    });

    test('a seat booked on another bus raises no alert', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1'));
      await bind();
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A', bus: 'BUS_2'));
      await pump();
      expect(notifications.items, isEmpty);
      expect(provider.allocations, isEmpty);
    });

    test('cash queue joins payments to this bus\'s allocations and splits by status', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1'));
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A'));
      await db.doc('seat_allocations/a2').set(allocation('a2', '2A'));
      await db.doc('seat_allocations/a3').set(allocation('a3', '3A', bus: 'BUS_2'));

      Map<String, dynamic> pay(String id, String alloc, String method, String status) => {
            'payment_id': id, 'allocation_id': alloc, 'journey_id': 'JRN_1',
            'method': method, 'amount_lkr': 1000.0, 'status': status,
            'timestamp': '2026-09-21T10:00:00.000Z', 'reference': '',
          };
      await db.doc('payments/p1').set(pay('p1', 'a1', 'conductor', 'pay_on_board'));
      await db.doc('payments/p2').set(pay('p2', 'a2', 'conductor', 'completed'));
      await db.doc('payments/p3').set(pay('p3', 'a3', 'conductor', 'pay_on_board')); // other bus
      await db.doc('payments/p4').set(pay('p4', 'a1', 'card', 'completed')); // not cash

      await bind();
      expect(provider.cashToCollect.map((c) => c.payment.paymentId), ['p1']);
      expect(provider.cashCollected.map((c) => c.payment.paymentId), ['p2']);
      expect(provider.cashToCollect.single.allocation.seatNumber, '1A');
    });

    test('startTrip creates the journey, starting occupancy from existing bookings', () async {
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A', journey: 'JRN_87_001'));
      await db.doc('seat_allocations/a2').set(allocation('a2', '4B', journey: 'JRN_87_001'));
      await bind();

      final error = await provider.startTrip(
        bus: const BusInfo(
          busId: 'BUS_1', busNumber: 'NB-1', routeId: 'R_87', busType: 'Normal',
          departureHour: 5, departureMinute: 30, durationMinutes: 540,
          startPoint: 'Colombo (Pettah)', endPoint: 'Jaffna Main Bus Stand',
          fareLkr: 1000, conductorId: 'CND_T',
        ),
        journeyId: ' JRN_87_001 ',
        stops: kRoute87Stops,
      );
      expect(error, isNull);

      final doc = (await db.doc('journey_instances/JRN_87_001').get()).data()!;
      expect(doc['conductor_id'], 'CND_T');
      expect(doc['bus_id'], 'BUS_1');
      expect(doc['current_stop'], 'Colombo (Pettah)');
      expect(doc['current_occupancy'], 2);
      expect(doc['priority_occupied'], 1);
      expect(doc['general_occupied'], 1);

      await pump();
      expect(provider.journey?.journeyId, 'JRN_87_001', reason: 'the live stream picks it up');
    });

    test('startTrip reports a conflict as a readable message', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1', conductor: 'CND_OTHER'));
      await bind();
      final error = await provider.startTrip(
        bus: const BusInfo(
          busId: 'BUS_1', busNumber: 'NB-1', routeId: 'R_87', busType: '',
          departureHour: 0, departureMinute: 0, durationMinutes: 480,
          startPoint: '', endPoint: '', fareLkr: 0, conductorId: '',
        ),
        journeyId: 'JRN_1',
        stops: const [],
      );
      expect(error, contains('CND_OTHER'));
      expect(await provider.startTrip(
        bus: const BusInfo(
          busId: 'B', busNumber: 'B', routeId: '', busType: '', departureHour: 0,
          departureMinute: 0, durationMinutes: 480, startPoint: '', endPoint: '',
          fareLkr: 0, conductorId: ''),
        journeyId: '   ', stops: const []), 'Enter a journey ID.');
    });

    test('setCurrentStop syncs zone counters but never current_occupancy', () async {
      await db.doc('journey_instances/JRN_1').set({...journey('JRN_1'), 'current_occupancy': 40});
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A'));
      await db.doc('seat_allocations/a2').set(allocation('a2', '5A'));
      await db.doc('seat_allocations/a3').set(allocation('a3', '9A'));
      await bind();

      expect(await provider.setCurrentStop('Negombo Bus Stand'), isNull);

      final doc = (await db.doc('journey_instances/JRN_1').get()).data()!;
      expect(doc['current_stop'], 'Negombo Bus Stand');
      expect(doc['priority_occupied'], 1);
      expect(doc['general_occupied'], 1);
      expect(doc['limited_occupied'], 1);
      expect(doc['current_occupancy'], 40, reason: 'owned by the passenger app');
      expect(doc['conductor_id'], 'CND_T');
    });

    test('completing a trip removes it from the active list', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1'));
      await bind();
      expect(provider.journey, isNotNull);

      expect(await provider.setStatus('completed'), isNull);
      await pump();
      expect(provider.journey, isNull);
      expect((await db.doc('journey_instances/JRN_1').get()).data()!['status'], 'completed');
    });

    test('actions with no trip, or a missing record, return a message instead of throwing', () async {
      await bind();
      expect(await provider.setCurrentStop('x'), 'There is no active trip.');
      expect(await provider.collectPayment(
        const Payment(paymentId: 'nope', allocationId: '', journeyId: '', method: 'conductor',
            amountLkr: 0, status: 'pay_on_board', timestamp: null, reference: '')),
        isNotNull);
    });

    test('updateIncident and collectPayment go through to Firestore', () async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1'));
      await db.doc('seat_allocations/a1').set(allocation('a1', '1A'));
      await db.doc('incident_reports/i1').set({
        'incident_id': 'i1', 'journey_id': 'JRN_1', 'status': 'pending',
        'incident_datetime': '2026-09-21T10:00:00.000Z', 'action_taken': 'Notified Conductor',
      });
      await db.doc('payments/p1').set({
        'payment_id': 'p1', 'allocation_id': 'a1', 'journey_id': 'JRN_1', 'method': 'conductor',
        'amount_lkr': 900.0, 'status': 'pay_on_board', 'timestamp': '2026-09-21T10:00:00.000Z',
      });
      await bind();

      expect(await provider.updateIncident(provider.incidents.single,
          status: 'resolved', actionTaken: '  Seat changed  '), isNull);
      expect(await provider.collectPayment(provider.cashToCollect.single.payment), isNull);
      await pump();

      final incident = (await db.doc('incident_reports/i1').get()).data()!;
      expect(incident['status'], 'resolved');
      expect(incident['action_taken'], 'Seat changed');
      expect(incident['resolution_date'], isA<String>());
      expect((await db.doc('payments/p1').get()).data()!['status'], 'completed');
      expect(provider.cashToCollect, isEmpty);
      expect(provider.cashCollected.length, 1);
    });
  });

  group('Start trip error handling', () {
    const bus = BusInfo(
      busId: 'BUS_1', busNumber: 'NB-1', routeId: 'R_87', busType: 'Normal',
      departureHour: 5, departureMinute: 30, durationMinutes: 540,
      startPoint: 'Colombo (Pettah)', endPoint: 'Jaffna Main Bus Stand',
      fareLkr: 1000, conductorId: 'CND_T',
    );

    Future<void> create(ConductorRepository repo, {String conductor = 'CND_T'}) =>
        repo.createJourney(
          journeyId: 'JRN_87_001', busId: 'BUS_1', routeId: 'R_87', conductorId: conductor,
          departure: DateTime.utc(2026, 9, 22, 9), arrival: DateTime.utc(2026, 9, 22, 18),
          currentStop: 'Colombo (Pettah)', occupancy: OccupancySummary.empty,
        );

    // On Flutter web the Firestore JS SDK boxes a Dart exception thrown inside a
    // transaction callback into "Dart exception thrown from converted Future",
    // hiding the real message. That can't be reproduced on the VM, so assert on
    // the cause: the callback must finish normally in every case.
    test('a conflict never throws inside the transaction callback', () async {
      final db = _SpyFirestore();
      await db.doc('journey_instances/JRN_87_001').set(journey('JRN_87_001', conductor: 'CND_OTHER'));

      await expectLater(
        create(ConductorRepository(db)),
        throwsA(isA<TripConflictException>()
            .having((e) => e.ownerConductorId, 'owner', 'CND_OTHER')),
      );
      expect(db.transactionsRun, 1);
      expect(db.handlerThrew, isFalse,
          reason: 'throwing inside the callback gets boxed into an opaque error on web');
    });

    test('creating a journey that does not exist yet also completes normally', () async {
      final db = _SpyFirestore();
      await create(ConductorRepository(db));

      expect(db.handlerThrew, isFalse);
      final doc = (await db.doc('journey_instances/JRN_87_001').get()).data()!;
      expect(doc['conductor_id'], 'CND_T');
      expect(doc['status'], 'in_transit');
    });

    test('a document with only a current_occupancy field (no owner) is taken over', () async {
      final db = _SpyFirestore();
      await db.doc('journey_instances/JRN_87_001').set({'current_occupancy': 3});
      await create(ConductorRepository(db));

      expect(db.handlerThrew, isFalse);
      expect((await db.doc('journey_instances/JRN_87_001').get()).data()!['conductor_id'], 'CND_T');
    });

    late List<String> logs;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      logs = [];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    });

    tearDown(() => debugPrint = originalDebugPrint);

    Future<(JourneyStreamProvider, FakeFirebaseFirestore)> providerWith(
      FakeFirebaseFirestore db, {
      Object? createError,
      Object? fetchError,
    }) async {
      final provider = JourneyStreamProvider(
        repository: _FailingRepository(db, createError: createError, fetchError: fetchError),
      )..bind('CND_T');
      addTearDown(provider.dispose);
      await pump();
      return (provider, db);
    }

    test('an unexpected failure is logged with its type and stack, and shown with its type',
        () async {
      final (provider, _) =
          await providerWith(FakeFirebaseFirestore(), createError: StateError('boom'));

      final message = await provider.startTrip(bus: bus, journeyId: 'JRN_87_001', stops: kRoute87Stops);

      expect(message, contains('StateError'));
      expect(message, contains('boom'));
      final log = logs.firstWhere((l) => l.contains('[startTrip] failed'), orElse: () => '');
      expect(log, contains('StateError'));
      expect(log, contains('boom'));
      expect(log, contains('#0'), reason: 'the stack trace is printed too');
    });

    test('a conflict is logged and shown as a readable message', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('journey_instances/JRN_87_001').set(journey('JRN_87_001', conductor: 'CND_OTHER'));
      final (provider, _) = await providerWith(db);

      final message = await provider.startTrip(bus: bus, journeyId: 'JRN_87_001', stops: kRoute87Stops);

      expect(message, allOf(contains('JRN_87_001'), contains('CND_OTHER')));
      expect(logs.any((l) => l.contains('TripConflictException')), isTrue);
    });

    test('the start attempt itself is logged with its inputs', () async {
      final (provider, _) = await providerWith(FakeFirebaseFirestore());
      await provider.startTrip(bus: bus, journeyId: ' JRN_87_001 ', stops: kRoute87Stops);
      expect(logs, contains('[startTrip] journey=JRN_87_001 bus=BUS_1 conductor=CND_T'));
    });

    test('failing to count existing bookings does not stop the trip from starting', () async {
      final (provider, db) =
          await providerWith(FakeFirebaseFirestore(), fetchError: StateError('no read access'));

      final message = await provider.startTrip(bus: bus, journeyId: 'JRN_87_001', stops: kRoute87Stops);

      expect(message, isNull);
      expect((await db.doc('journey_instances/JRN_87_001').get()).data()!['current_occupancy'], 0);
      expect(logs.any((l) => l.contains('could not count existing bookings') && l.contains('no read access')),
          isTrue);
    });

    test('other actions log their real error too', () async {
      final (provider, _) = await providerWith(FakeFirebaseFirestore());
      // No active trip and a missing payment: both must fail softly and be logged.
      await provider.collectPayment(const Payment(
        paymentId: 'missing', allocationId: '', journeyId: '', method: 'conductor',
        amountLkr: 0, status: 'pay_on_board', timestamp: null, reference: '',
      ));
      expect(logs.any((l) => l.contains('[collectPayment] failed')), isTrue);
    });
  });
}

/// Records whether a transaction callback threw, without changing behaviour.
class _SpyFirestore extends FakeFirebaseFirestore {
  bool handlerThrew = false;
  int transactionsRun = 0;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    transactionsRun++;
    return super.runTransaction<T>(
      (transaction) async {
        try {
          return await transactionHandler(transaction);
        } catch (_) {
          handlerThrew = true;
          rethrow;
        }
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

/// A repository whose journey write / booking count can be made to fail.
class _FailingRepository extends ConductorRepository {
  _FailingRepository(super.db, {this.createError, this.fetchError});

  final Object? createError;
  final Object? fetchError;

  @override
  Future<void> createJourney({
    required String journeyId,
    required String busId,
    required String routeId,
    required String conductorId,
    required DateTime departure,
    required DateTime arrival,
    required String currentStop,
    required OccupancySummary occupancy,
  }) async {
    final error = createError;
    if (error != null) throw error;
    return super.createJourney(
      journeyId: journeyId, busId: busId, routeId: routeId, conductorId: conductorId,
      departure: departure, arrival: arrival, currentStop: currentStop, occupancy: occupancy,
    );
  }

  @override
  Future<List<SeatAllocation>> fetchTripAllocations(String journeyId, String busId) async {
    final error = fetchError;
    if (error != null) throw error;
    return super.fetchTripAllocations(journeyId, busId);
  }
}
