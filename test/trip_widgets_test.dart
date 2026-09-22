import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safeboard_conductor/data/conductor_repository.dart';
import 'package:safeboard_conductor/models/conductor.dart';
import 'package:safeboard_conductor/providers/conductor_provider.dart';
import 'package:safeboard_conductor/providers/journey_stream_provider.dart';
import 'package:safeboard_conductor/providers/notifications_provider.dart';
import 'package:safeboard_conductor/providers/reference_data_provider.dart';
import 'package:safeboard_conductor/screens/cash_screen.dart';
import 'package:safeboard_conductor/screens/home_shell.dart';
import 'package:safeboard_conductor/screens/incidents_screen.dart';
import 'package:safeboard_conductor/screens/seat_map_screen.dart';
import 'package:safeboard_conductor/screens/trip_screen.dart';
import 'package:safeboard_conductor/utils/ui.dart';

/// Lets fake-Firestore streams deliver, then rebuilds. Streams and futures
/// need real time, which testWidgets' fake clock doesn't advance on its own.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  await tester.pump();
}

Map<String, dynamic> journeyDoc({String status = 'in_transit', String stop = 'Colombo (Pettah)'}) => {
      'journey_id': 'JRN_1',
      'bus_id': 'BUS_1',
      'route_id': 'R_87',
      'conductor_id': 'CND_T',
      'departure_datetime': '2026-09-21T09:00:00.000Z',
      'arrival_datetime': '2026-09-21T17:00:00.000Z',
      'current_occupancy': 0,
      'standing_count': 0,
      'current_stop': stop,
      'crowding_level': 'low',
      'status': status,
      'priority_occupied': 0,
      'general_occupied': 0,
      'limited_occupied': 0,
    };

Map<String, dynamic> allocationDoc(String id, String seat, {bool reserved = false}) => {
      'allocation_id': id,
      'seat_number': seat,
      'seat_id': seat,
      'bus_id': 'BUS_1',
      'journey_id': 'JRN_1',
      'allocation_datetime': '2026-09-21T10:00:00.000Z',
      'boarding_stop': 'Colombo (Pettah)',
      'alighting_stop': 'Jaffna Main Bus Stand',
      'allocation_type': 'auto',
      'risk_score': 0.25,
      'status': 'active',
      'priority_reserved': reserved,
    };

class Harness {
  Harness(this.db, this.repo, this.conductor, this.notifications, this.reference, this.journeys);

  final FakeFirebaseFirestore db;
  final ConductorRepository repo;
  final ConductorProvider conductor;
  final NotificationsProvider notifications;
  final ReferenceDataProvider reference;
  final JourneyStreamProvider journeys;

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ConductorProvider>.value(value: conductor),
          ChangeNotifierProvider<NotificationsProvider>.value(value: notifications),
          ChangeNotifierProvider<ReferenceDataProvider>.value(value: reference),
          ChangeNotifierProvider<JourneyStreamProvider>.value(value: journeys),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Future<Map<String, dynamic>> read(String path) async => (await db.doc(path).get()).data()!;
}

/// Builds the providers against a fake Firestore, seeded by [seed], signed in
/// as conductor CND_T, and pumps [screen].
Future<Harness> open(
  WidgetTester tester,
  Widget screen, {
  Future<void> Function(FakeFirebaseFirestore db)? seed,
}) async {
  tester.view.physicalSize = const Size(600, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = FakeFirebaseFirestore();
  final repo = ConductorRepository(db);

  await tester.runAsync(() async {
    await db.doc('buses/BUS_1').set({
      'bus_id': 'BUS_1', 'bus_number': 'NB-1 (Test Express)', 'route_id': 'R_87',
      'departure_hour': 5, 'departure_minute': 30, 'duration_minutes': 540,
      'start_point': 'Colombo (Pettah)', 'end_point': 'Jaffna Main Bus Stand',
      'conductor_id': 'CND_T', 'fare_lkr': 1450.0,
    });
    await db.doc('buses/BUS_2').set({
      'bus_id': 'BUS_2', 'bus_number': 'NB-2 (Other)', 'route_id': 'R_87',
      'departure_hour': 7, 'departure_minute': 0, 'duration_minutes': 540,
      'start_point': 'Jaffna Main Bus Stand', 'end_point': 'Colombo (Pettah)',
      'conductor_id': 'CND_X',
    });
    if (seed != null) await seed(db);
  });

  final notifications = NotificationsProvider();
  final conductor = ConductorProvider();
  await tester.runAsync(() => conductor.login(const Conductor(
        conductorId: 'CND_T', name: 'Test Conductor', phoneNumber: '', rating: 5,
      )));
  final reference = ReferenceDataProvider(repository: repo)..ensureLoaded();
  final journeys = JourneyStreamProvider(repository: repo)
    ..bind('CND_T', notifications: notifications);

  final harness = Harness(db, repo, conductor, notifications, reference, journeys);
  addTearDown(() {
    journeys.dispose();
    reference.dispose();
    notifications.dispose();
  });

  await tester.pumpWidget(harness.wrap(screen));
  await settle(tester);
  return harness;
}

void main() {
  group('Trip tab', () {
    testWidgets('with no active trip, starting one creates the journey for the conductor\'s own bus',
        (tester) async {
      final h = await open(tester, const TripScreen());

      expect(find.text('Start a trip'), findsOneWidget);
      expect(find.textContaining('NB-1 (Test Express)'), findsWidgets,
          reason: 'the conductor\'s own bus is preselected');

      await tester.tap(find.text('Start trip'));
      await settle(tester);

      final doc = await tester.runAsync(() => h.read('journey_instances/JRN_87_001'));
      expect(doc!['conductor_id'], 'CND_T');
      expect(doc['bus_id'], 'BUS_1');
      expect(doc['current_stop'], 'Colombo (Pettah)');
      expect(doc['status'], 'in_transit');
      // The live stream then swaps the form for the trip view.
      expect(find.text('Start a trip'), findsNothing);
      expect(find.text('Trip controls'), findsOneWidget);
    });

    testWidgets('an active trip shows occupancy derived from allocations', (tester) async {
      await open(tester, const TripScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '1A'));
        await db.doc('seat_allocations/a2').set(allocationDoc('a2', '2C'));
        await db.doc('seat_allocations/a3').set(allocationDoc('a3', '4B', reserved: true));
      });

      expect(find.text('3 / 70'), findsOneWidget);
      expect(find.text('2 / 15'), findsOneWidget); // priority
      expect(find.text('1 / 15'), findsOneWidget); // general
      expect(find.text('0 / 34'), findsOneWidget); // limited
      expect(find.text('Seat allocations (3)'), findsOneWidget);
      expect(find.textContaining('Seat 4B'), findsOneWidget);
      expect(find.textContaining('SB-'), findsWidgets, reason: 'booking reference shown');
      expect(find.textContaining('priority full, moved to General'), findsOneWidget);
    });

    testWidgets('Next stop moves the bus along the route', (tester) async {
      final h = await open(tester, const TripScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
      });

      await tester.tap(find.text('Next stop: Kelaniya'));
      await settle(tester);

      final doc = await tester.runAsync(() => h.read('journey_instances/JRN_1'));
      expect(doc!['current_stop'], 'Kelaniya');
      expect(find.text('Next stop: Peliyagoda Interchange'), findsOneWidget);
      expect(find.textContaining('Stop 2 of 37'), findsOneWidget);
    });

    testWidgets('ending the trip completes it and offers a fresh start', (tester) async {
      final h = await open(tester, const TripScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
      });

      // (OutlinedButton.icon is a private subclass, so match on the label.)
      await tester.tap(find.text('End trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('End trip')));
      await settle(tester);

      final doc = await tester.runAsync(() => h.read('journey_instances/JRN_1'));
      expect(doc!['status'], 'completed');
      expect(find.text('Start a trip'), findsOneWidget);
    });

    testWidgets('a bus starting in Jaffna travels the stops in reverse', (tester) async {
      await open(tester, const TripScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set({
          ...journeyDoc(stop: 'Jaffna Main Bus Stand'),
          'bus_id': 'BUS_2',
        });
      });
      expect(find.text('Next stop: Kaithady'), findsOneWidget);
    });
  });

  group('Seat map', () {
    testWidgets('draws the 64-seat bus and marks occupied seats from live allocations',
        (tester) async {
      await open(tester, const SeatMapScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '1A'));
        await db.doc('seat_allocations/a2').set(allocationDoc('a2', '12D'));
        await db.doc('seat_allocations/a3').set(allocationDoc('a3', 'Standing-1'));
      });

      for (final seat in ['1A', '1B', '11E', '12C', '12D', '12E', '13A', '13F']) {
        expect(find.text(seat), findsOneWidget, reason: 'seat $seat drawn');
      }
      expect(find.text('12A'), findsNothing, reason: 'no left pair in row 12');
      expect(find.text('Priority 1/15'), findsOneWidget);
      expect(find.text('Limited 1/34'), findsOneWidget);
      expect(find.text('Standing 1/6'), findsOneWidget);
      expect(find.text('Standing  1 / 6'), findsOneWidget);
    });

    testWidgets('tapping an occupied seat shows the booking reference', (tester) async {
      await open(tester, const SeatMapScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '4B', reserved: true));
      });

      await tester.tap(find.text('4B'));
      await tester.pumpAndSettle();

      expect(find.text('Seat 4B  ·  General'), findsOneWidget);
      expect(find.text('Reference'), findsOneWidget);
      expect(find.textContaining('SB-'), findsOneWidget);
      expect(find.text('0.25'), findsOneWidget);
      // (The legend under the map mentions this too, so look inside the sheet.)
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.textContaining('moved from Priority to General'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a new booking appears on the map without reloading', (tester) async {
      final h = await open(tester, const SeatMapScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
      });
      expect(find.text('Priority 0/15'), findsOneWidget);

      await tester.runAsync(() => h.db.doc('seat_allocations/a1').set(allocationDoc('a1', '2A')));
      await settle(tester);

      expect(find.text('Priority 1/15'), findsOneWidget);
    });

    testWidgets('without a trip it says so', (tester) async {
      await open(tester, const SeatMapScreen());
      expect(find.text('No active trip'), findsOneWidget);
    });
  });

  group('Incidents tab', () {
    Future<void> seedIncidents(FakeFirebaseFirestore db) async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc());
      await db.doc('incident_reports/i_low').set({
        'incident_id': 'i_low', 'journey_id': 'JRN_1', 'incident_type': 'unsafe_crowding',
        'incident_datetime': '2026-09-21T09:30:00.000Z', 'severity_level': 'low',
        'description': 'Crowded aisle', 'status': 'resolved', 'action_taken': 'Asked to move back',
        'seat_location': 'Standing-1', 'resolution_date': '2026-09-21T09:40:00.000Z',
      });
      await db.doc('incident_reports/i_high').set({
        'incident_id': 'i_high', 'journey_id': 'JRN_1', 'incident_type': 'unwanted_contact',
        'incident_datetime': '2026-09-21T10:00:00.000Z', 'severity_level': 'high',
        'description': 'Unwanted contact', 'status': 'pending', 'action_taken': 'Notified Conductor',
        'seat_location': '5B', 'resolution_date': null,
      });
    }

    testWidgets('lists open incidents first and counts them', (tester) async {
      await open(tester, const IncidentsScreen(), seed: seedIncidents);

      expect(find.text('1 open  ·  1 resolved'), findsOneWidget);
      final high = tester.getTopLeft(find.text('Unwanted contact').first).dy;
      final low = tester.getTopLeft(find.text('Unsafe crowding')).dy;
      expect(high, lessThan(low));
    });

    testWidgets('resolving an incident records the action and an ISO resolution date',
        (tester) async {
      final h = await open(tester, const IncidentsScreen(), seed: seedIncidents);

      await tester.tap(find.text('Unwanted contact').first);
      await tester.pumpAndSettle();
      expect(find.text('Update incident'), findsOneWidget);

      await tester.tap(find.text('Resolved').last);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Action taken'), 'Moved passenger to 2C');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() => h.read('incident_reports/i_high'));
      expect(doc!['status'], 'resolved');
      expect(doc['action_taken'], 'Moved passenger to 2C');
      expect(doc['resolution_date'], isA<String>());
      expect(doc['description'], 'Unwanted contact', reason: 'passenger\'s text untouched');
      expect(find.text('Update incident'), findsNothing, reason: 'sheet closed on success');
      expect(find.text('0 open  ·  2 resolved'), findsOneWidget);
    });
  });

  group('Cash tab', () {
    testWidgets('tapping a fare opens its details, then Code to Confirm shows the boarding code and collects it',
        (tester) async {
      final h = await open(tester, const CashScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '5D'));
        await db.doc('payments/p1').set({
          'payment_id': 'p1', 'allocation_id': 'a1', 'journey_id': 'JRN_1', 'method': 'conductor',
          'amount_lkr': 1450.0, 'status': 'pay_on_board', 'timestamp': '2026-09-21T10:00:00.000Z',
          'reference': 'Pay to conductor onboard',
        });
      });

      expect(find.text('To collect (1)'), findsOneWidget);
      expect(find.text('LKR 1,450'), findsWidgets);

      await tester.tap(find.text('Tap to collect'));
      await tester.pumpAndSettle();

      // The passenger's details, identified by seat (the schema carries no name).
      expect(find.widgetWithText(AppBar, 'Collect payment'), findsOneWidget);
      expect(find.text('Seat 5D'), findsOneWidget);
      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.text('Colombo (Pettah)'), findsOneWidget);
      expect(find.text('Cash (pay on board)'), findsOneWidget);

      // (FilledButton.icon is a private subclass, so match on the label.)
      await tester.tap(find.text('Code to Confirm'));
      await settle(tester);
      await tester.pumpAndSettle();

      // The payment is already written by the time the code appears.
      var doc = await tester.runAsync(() => h.read('payments/p1'));
      expect(doc!['status'], 'completed');
      expect(doc['amount_lkr'], 1450.0);

      expect(find.text('BOARDING CODE'), findsOneWidget);
      expect(find.textContaining('seat 5D'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('boarding-otp'))).data, '1  2  3  4');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Back on the Cash tab, now showing as collected.
      expect(find.widgetWithText(AppBar, 'Collect payment'), findsNothing);
      expect(find.text('To collect (0)'), findsOneWidget);
      expect(find.text('Collected (1)'), findsOneWidget);
      doc = await tester.runAsync(() => h.read('payments/p1'));
      expect(doc!['status'], 'completed');
    });

    testWidgets('backing out of the details screen without confirming changes nothing', (tester) async {
      final h = await open(tester, const CashScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '5D'));
        await db.doc('payments/p1').set({
          'payment_id': 'p1', 'allocation_id': 'a1', 'journey_id': 'JRN_1', 'method': 'conductor',
          'amount_lkr': 900.0, 'status': 'pay_on_board', 'timestamp': '2026-09-21T10:00:00.000Z',
        });
      });

      await tester.tap(find.text('Tap to collect'));
      await tester.pumpAndSettle();
      expect(find.text('Code to Confirm'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect((await tester.runAsync(() => h.read('payments/p1')))!['status'], 'pay_on_board');
      expect(find.text('To collect (1)'), findsOneWidget);
    });

    testWidgets('a collected fare can be reopened to show the boarding code again', (tester) async {
      await open(tester, const CashScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '5D'));
        await db.doc('payments/p1').set({
          'payment_id': 'p1', 'allocation_id': 'a1', 'journey_id': 'JRN_1', 'method': 'conductor',
          'amount_lkr': 900.0, 'status': 'completed', 'timestamp': '2026-09-21T10:00:00.000Z',
        });
      });

      await tester.tap(find.text('Tap to view'));
      await tester.pumpAndSettle();

      expect(find.text('Payment collected'), findsOneWidget);
      expect(find.text('Code to Confirm'), findsNothing);

      await tester.tap(find.text('Show boarding code again'));
      await tester.pumpAndSettle();
      expect(find.text('BOARDING CODE'), findsOneWidget);
    });

    testWidgets('an empty queue explains itself', (tester) async {
      await open(tester, const CashScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
      });
      expect(find.text('No pay-on-board fares on this trip'), findsOneWidget);
    });
  });

  group('Home shell', () {
    testWidgets('has the five tabs, with badges for open incidents and cash due', (tester) async {
      await open(tester, const HomeShell(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '5D'));
        await db.doc('incident_reports/i1').set({
          'incident_id': 'i1', 'journey_id': 'JRN_1', 'status': 'pending',
          'incident_datetime': '2026-09-21T10:00:00.000Z',
        });
        await db.doc('payments/p1').set({
          'payment_id': 'p1', 'allocation_id': 'a1', 'journey_id': 'JRN_1', 'method': 'conductor',
          'amount_lkr': 900.0, 'status': 'pay_on_board', 'timestamp': '2026-09-21T10:00:00.000Z',
        });
      });

      for (final label in ['Trip', 'Seats', 'Incidents', 'Cash', 'Alerts']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      // One open incident and one fare to collect.
      expect(find.widgetWithText(Badge, '1'), findsNWidgets(2));
    });
  });

  group('runAction', () {
    testWidgets('shows a failure in a SnackBar and returns false', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        })),
      ));

      late bool ok;
      final future = runAction(context, () async => 'Firestore refused this change');
      await tester.pump();
      ok = await future;
      await tester.pump();

      expect(ok, isFalse);
      expect(find.text('Firestore refused this change'), findsOneWidget);
    });

    testWidgets('success returns true and shows the success message', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        })),
      ));

      final ok = await runAction(context, () async => null, success: 'Done');
      await tester.pump();

      expect(ok, isTrue);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
