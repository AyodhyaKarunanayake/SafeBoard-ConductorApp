import 'package:cloud_firestore/cloud_firestore.dart' show TransactionHandler;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safeboard_conductor/data/conductor_repository.dart';
import 'package:safeboard_conductor/models/route_info.dart';
import 'package:safeboard_conductor/models/seat_allocation.dart';
import 'package:safeboard_conductor/models/standing_ranking.dart';
import 'package:safeboard_conductor/providers/journey_stream_provider.dart';
import 'package:safeboard_conductor/providers/notifications_provider.dart';
import 'package:safeboard_conductor/screens/home_shell.dart';
import 'package:safeboard_conductor/screens/seat_map_screen.dart';

import 'trip_logic_test.dart' show allocation, journey, pump;
import 'trip_widgets_test.dart' show Harness, allocationDoc, journeyDoc, open, settle;

SeatAllocation standingTo(String id, String alighting, {String when = '2026-09-22T10:00:00.000Z'}) =>
    SeatAllocation.fromMap({
      ...allocation(id, 'Standing-$id'),
      'alighting_stop': alighting,
      'allocation_datetime': when,
    }, id);

const forwardStops = kRoute87Stops;

/// A route with distances, for the km checks: A B C D E at 0/100/150/300/310 km.
const kmRoute = RouteInfo(
  routeId: 'R_T',
  routeName: 'Test',
  distanceKm: 310,
  stops: ['A', 'B', 'C', 'D', 'E'],
  stopDistancesKm: [0, 100, 150, 300, 310],
);

void main() {
  group('rankStandingPassengers', () {
    test('furthest remaining journey first, measured from where the bus is now', () {
      final ranked = rankStandingPassengers(
        standing: [
          standingTo('near', 'Anuradhapura New Town'), // 5 stops ahead of Puttalam
          standingTo('far', 'Jaffna Main Bus Stand'), //  18
          standingTo('mid', 'Vavuniya Bus Terminal'), //   8
        ],
        stopsInTravelOrder: forwardStops,
        currentStop: 'Puttalam Main Stand',
      );

      expect(ranked.map((c) => c.allocation.allocationId), ['far', 'mid', 'near']);
      expect(ranked.map((c) => c.remainingStops), [18, 8, 5]);
    });

    test('uses kilometres when the route has them, for the actual distance left', () {
      final ranked = rankStandingPassengers(
        standing: [standingTo('toC', 'C'), standingTo('toE', 'E'), standingTo('toD', 'D')],
        stopsInTravelOrder: kmRoute.stops,
        currentStop: 'B',
        route: kmRoute,
      );
      expect(ranked.map((c) => c.allocation.allocationId), ['toE', 'toD', 'toC']);
      expect(ranked.map((c) => c.remainingKm), [210, 200, 50]);
      expect(ranked.map((c) => c.remainingStops), [3, 2, 1]);
    });

    test('a Jaffna-start bus (route reversed): distance is counted the way it travels', () {
      final reversed = kmRoute.stops.reversed.toList(); // E D C B A
      final ranked = rankStandingPassengers(
        standing: [standingTo('toB', 'B'), standingTo('toA', 'A')],
        stopsInTravelOrder: reversed,
        currentStop: 'D',
        route: kmRoute,
      );
      expect(ranked.first.allocation.allocationId, 'toA');
      expect(ranked.first.remainingStops, 3);
      expect(ranked.first.remainingKm, 300, reason: 'D (300 km) back to A (0 km)');
      expect(ranked.last.remainingKm, 200, reason: 'D (300 km) back to B (100 km)');
    });

    test('someone at or past their stop, or with an unknown destination, ranks last', () {
      final ranked = rankStandingPassengers(
        standing: [
          standingTo('gone', 'Colombo (Pettah)'), // already behind the bus
          standingTo('unknown', 'Nowhere At All'),
          standingTo('ahead', 'Anuradhapura New Town'),
        ],
        stopsInTravelOrder: forwardStops,
        currentStop: 'Puttalam Main Stand',
      );
      expect(ranked.first.allocation.allocationId, 'ahead');
      expect(ranked.firstWhere((c) => c.allocation.allocationId == 'gone').remainingStops, 0);
      final unknown = ranked.firstWhere((c) => c.allocation.allocationId == 'unknown');
      expect(unknown.destinationKnown, isFalse);
      expect(unknown.remainingStops, 0);
    });

    test('a tie goes to whoever has been standing longest', () {
      final ranked = rankStandingPassengers(
        standing: [
          standingTo('later', 'Jaffna Main Bus Stand', when: '2026-09-22T10:30:00.000Z'),
          standingTo('earlier', 'Jaffna Main Bus Stand', when: '2026-09-22T09:00:00.000Z'),
        ],
        stopsInTravelOrder: forwardStops,
        currentStop: 'Puttalam Main Stand',
      );
      expect(ranked.map((c) => c.allocation.allocationId), ['earlier', 'later']);
    });

    test('a bus position that is not on the route counts from the start; no one standing gives nothing', () {
      final ranked = rankStandingPassengers(
        standing: [standingTo('a', 'Kelaniya')],
        stopsInTravelOrder: forwardStops,
        currentStop: 'Somewhere Unlisted',
      );
      expect(ranked.single.remainingStops, 1);
      expect(
        rankStandingPassengers(standing: const [], stopsInTravelOrder: forwardStops, currentStop: 'Kelaniya'),
        isEmpty,
      );
    });
  });

  group('ConductorRepository.assignStandingPassengerToSeat', () {
    late FakeFirebaseFirestore db;
    late ConductorRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = ConductorRepository(db);
    });

    Future<void> assign(String id, String seat, {String bus = 'BUS_1'}) => repo.assignStandingPassengerToSeat(
        allocationId: id, journeyId: 'JRN_1', busId: bus, seat: seat);

    test('moves the passenger to the seat, marks a manual override, and changes nothing else', () async {
      final original = allocation('s1', 'Standing-1');
      await db.doc('seat_allocations/s1').set(original);

      await assign('s1', '5B');

      final doc = (await db.doc('seat_allocations/s1').get()).data()!;
      expect(doc['seat_number'], '5B');
      expect(doc['seat_id'], '5B');
      expect(doc['allocation_type'], 'manual_override');
      for (final key in original.keys.toSet()..removeAll({'seat_number', 'seat_id', 'allocation_type'})) {
        expect(doc[key], original[key], reason: '$key must be unchanged');
      }
    });

    test('refuses a seat that someone else holds on this bus, and writes nothing', () async {
      await db.doc('seat_allocations/s1').set(allocation('s1', 'Standing-1'));
      await db.doc('seat_allocations/other').set(allocation('other', '5B'));

      await expectLater(
        assign('s1', '5B'),
        throwsA(isA<SeatAssignException>().having((e) => e.message, 'message', contains('just been taken'))),
      );
      expect((await db.doc('seat_allocations/s1').get()).data()!['seat_number'], 'Standing-1');
    });

    test('a seat held only by a released booking, or by another bus, is free to give', () async {
      await db.doc('seat_allocations/s1').set(allocation('s1', 'Standing-1'));
      await db.doc('seat_allocations/old').set(allocation('old', '5B', status: 'released'));
      await db.doc('seat_allocations/elsewhere').set(allocation('elsewhere', '5B', bus: 'BUS_2'));

      await assign('s1', '5B');
      expect((await db.doc('seat_allocations/s1').get()).data()!['seat_number'], '5B');
    });

    test('refuses a passenger who has left, who does not exist, or who already has a seat', () async {
      await db.doc('seat_allocations/left').set(allocation('left', 'Standing-1', status: 'released'));
      await db.doc('seat_allocations/seated').set(allocation('seated', '2A'));

      await expectLater(assign('left', '5B'),
          throwsA(isA<SeatAssignException>().having((e) => e.message, 'm', contains('already left'))));
      await expectLater(assign('missing', '5B'),
          throwsA(isA<SeatAssignException>().having((e) => e.message, 'm', contains('no longer exists'))));
      await expectLater(assign('seated', '5B'),
          throwsA(isA<SeatAssignException>().having((e) => e.message, 'm', contains('already has a seat'))));
      expect((await db.doc('seat_allocations/seated').get()).data()!['seat_number'], '2A');
      expect((await db.doc('seat_allocations/left').get()).data()!['seat_number'], 'Standing-1');
    });

    test('a refusal never throws inside the transaction callback (web would box it)', () async {
      final spy = _SpyFirestore();
      await spy.doc('seat_allocations/left').set(allocation('left', 'Standing-1', status: 'released'));

      await expectLater(
        ConductorRepository(spy).assignStandingPassengerToSeat(
            allocationId: 'left', journeyId: 'JRN_1', busId: 'BUS_1', seat: '5B'),
        throwsA(isA<SeatAssignException>()),
      );
      expect(spy.transactionsRun, 1);
      expect(spy.handlerThrew, isFalse);
    });
  });

  group('JourneyStreamProvider: passengers who leave', () {
    late FakeFirebaseFirestore db;
    late NotificationsProvider notifications;
    late JourneyStreamProvider provider;

    setUp(() {
      db = FakeFirebaseFirestore();
      notifications = NotificationsProvider();
      provider = JourneyStreamProvider(repository: ConductorRepository(db));
    });

    tearDown(() {
      provider.dispose();
      notifications.dispose();
    });

    Future<void> bind() async {
      provider.bind('CND_T', notifications: notifications);
      await pump();
      await pump();
    }

    Future<void> seedTrip() async {
      await db.doc('journey_instances/JRN_1').set(journey('JRN_1'));
    }

    Future<void> release(String id) async {
      await db.doc('seat_allocations/$id').update({'status': 'released'});
      await pump();
    }

    test('a seated passenger ending their journey frees the seat and raises an alert', () async {
      await seedTrip();
      await db.doc('seat_allocations/a1').set(allocation('a1', '5B'));
      await bind();
      expect(provider.allocationForSeat('5B'), isNotNull);

      await release('a1');

      expect(provider.allocationForSeat('5B'), isNull, reason: 'the seat is empty again');
      final event = provider.unannouncedSeatFreed.single;
      expect(event.seat, '5B');
      expect(event.wasSeated, isTrue);
      expect(provider.unpromptedSeatFreed.single.id, event.id);
      expect(notifications.items.first.title, 'Passenger left');
      expect(notifications.items.first.body, 'Seat 5B is empty again.');
    });

    test('a standing passenger leaving is announced but never offered a seat', () async {
      await seedTrip();
      await db.doc('seat_allocations/s1').set(allocation('s1', 'Standing-1'));
      await bind();
      await release('s1');

      expect(provider.unannouncedSeatFreed.single.wasSeated, isFalse);
      expect(provider.unpromptedSeatFreed, isEmpty);
      expect(notifications.items.first.body, contains('standing passenger'));
    });

    test('a deleted booking counts as leaving too', () async {
      await seedTrip();
      await db.doc('seat_allocations/a1').set(allocation('a1', '5B'));
      await bind();
      await db.doc('seat_allocations/a1').delete();
      await pump();
      expect(provider.unannouncedSeatFreed.single.seat, '5B');
    });

    test('bookings already released when the app opens are not "leaving"', () async {
      await seedTrip();
      await db.doc('seat_allocations/old').set(allocation('old', '5B', status: 'released'));
      await bind();
      expect(provider.unannouncedSeatFreed, isEmpty);
      expect(notifications.items, isEmpty);
    });

    test('a passenger on another bus leaving is not this bus\'s business', () async {
      await seedTrip();
      await db.doc('seat_allocations/x').set(allocation('x', '5B', bus: 'BUS_2'));
      await bind();
      await release('x');
      expect(provider.unannouncedSeatFreed, isEmpty);
    });

    test('moving a standing passenger to a seat is not mistaken for someone leaving', () async {
      await seedTrip();
      await db.doc('seat_allocations/s1').set(allocation('s1', 'Standing-1'));
      await bind();

      await db.doc('seat_allocations/s1').update({'seat_number': '5B', 'seat_id': '5B'});
      await pump();

      expect(provider.unannouncedSeatFreed, isEmpty);
      expect(provider.allocationForSeat('5B')?.allocationId, 's1');
      expect(provider.standingPassengers, isEmpty);
    });

    test('announced and prompted are tracked separately, per event', () async {
      await seedTrip();
      await db.doc('seat_allocations/a1').set(allocation('a1', '5B'));
      await db.doc('seat_allocations/a2').set(allocation('a2', '6A'));
      await bind();
      await release('a1');
      await release('a2');
      expect(provider.unannouncedSeatFreed, hasLength(2));

      provider.markSeatFreedAnnounced(provider.unannouncedSeatFreed.first);
      expect(provider.unannouncedSeatFreed, hasLength(1));
      expect(provider.unpromptedSeatFreed, hasLength(2), reason: 'announcing does not consume the prompt');

      provider.markSeatFreedPrompted(provider.unpromptedSeatFreed.first);
      expect(provider.unpromptedSeatFreed, hasLength(1));
    });

    test('assigning through the provider updates the live lists', () async {
      await seedTrip();
      await db.doc('seat_allocations/s1').set(allocation('s1', 'Standing-1'));
      await bind();

      expect(await provider.assignStandingToSeat(provider.standingPassengers.single, '5B'), isNull);
      await pump();

      expect(provider.allocationForSeat('5B')?.allocationId, 's1');
      expect(provider.standingPassengers, isEmpty);
      expect(provider.occupancy.general, 1);
      expect(provider.occupancy.standing, 0);
    });

    test('a seat taken in the meantime is reported in plain words', () async {
      await seedTrip();
      await db.doc('seat_allocations/s1').set(allocation('s1', 'Standing-1'));
      await bind();
      final standing = provider.standingPassengers.single;

      await db.doc('seat_allocations/late').set(allocation('late', '5B'));
      await pump();

      expect(await provider.assignStandingToSeat(standing, '5B'), 'Seat 5B has just been taken.');
    });
  });

  group('Seat map', () {
    Color? cellColor(WidgetTester tester, String seat) {
      final container = find.ancestor(of: find.text(seat), matching: find.byType(Container)).first;
      return ((tester.widget<Container>(container)).decoration as BoxDecoration).color;
    }

    testWidgets('a seat whose passenger leaves goes back to exactly the colour of a seat never taken',
        (tester) async {
      final h = await open(tester, const SeatMapScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc());
        await db.doc('seat_allocations/a1').set(allocationDoc('a1', '5B'));
      });
      final untouched = cellColor(tester, '5A'); // same zone, never booked
      final occupied = cellColor(tester, '5B');
      expect(occupied, isNot(untouched), reason: 'a booked seat is drawn differently');

      await tester.runAsync(() => h.db.doc('seat_allocations/a1').update({'status': 'released'}));
      await settle(tester);

      expect(cellColor(tester, '5B'), untouched);
      expect(find.text('General 0/15'), findsOneWidget);
    });
  });

  group('Passenger left: pop-up and seat offer', () {
    Future<void> seedBus(FakeFirebaseFirestore db, {bool standing = true}) async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc(stop: 'Puttalam Main Stand'));
      await db.doc('seat_allocations/a1').set(allocationDoc('a1', '5B'));
      if (standing) {
        await db.doc('seat_allocations/s1').set({...allocationDoc('s1', 'Standing-1'), 'alighting_stop': 'Anuradhapura New Town'});
        await db.doc('seat_allocations/s2').set({...allocationDoc('s2', 'Standing-2'), 'alighting_stop': 'Jaffna Main Bus Stand'});
        await db.doc('seat_allocations/s3').set({...allocationDoc('s3', 'Standing-3'), 'alighting_stop': 'Vavuniya Bus Terminal'});
      }
    }

    Future<void> leave(Harness h, WidgetTester tester, String id) async {
      await tester.runAsync(() => h.db.doc('seat_allocations/$id').update({'status': 'released'}));
      await settle(tester);
    }

    testWidgets('the "seat is empty" alert shows for 3 seconds, then vanishes on its own', (tester) async {
      final h = await open(tester, const HomeShell(), seed: (db) => seedBus(db, standing: false));

      await leave(h, tester, 'a1');
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Seat 5B is empty'), findsOneWidget);
      expect(find.text('The passenger ended their journey.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Seat 5B is empty'), findsOneWidget, reason: 'still up part-way through');

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Seat 5B is empty'), findsNothing, reason: 'gone after about 3 seconds');
    });

    testWidgets('a standing passenger leaving gets the alert too, but no seat offer', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedBus);
      await leave(h, tester, 's1');
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('A standing passenger left'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-seat-title')), findsNothing);
    });

    testWidgets('with nobody standing there is only the alert, no question', (tester) async {
      final h = await open(tester, const HomeShell(), seed: (db) => seedBus(db, standing: false));
      await leave(h, tester, 'a1');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-seat-title')), findsNothing);
    });

    testWidgets('with standing passengers, asks who should get the seat: furthest-travelling first',
        (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedBus);
      await leave(h, tester, 'a1');
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(const Key('empty-seat-title'))).data, 'Seat 5B is empty');
      expect(find.textContaining('3 passengers are standing'), findsOneWidget);

      final far = tester.getTopLeft(find.text('Standing-2')).dy; // to Jaffna
      final mid = tester.getTopLeft(find.text('Standing-3')).dy; // to Vavuniya
      final near = tester.getTopLeft(find.text('Standing-1')).dy; // to Anuradhapura
      expect(far, lessThan(mid));
      expect(mid, lessThan(near));
      expect(find.text('Travels furthest'), findsOneWidget);
      expect(find.text('Assign to 5B'), findsOneWidget);
      expect(find.textContaining('18 stops'), findsOneWidget, reason: 'Puttalam to Jaffna');
    });

    testWidgets('Assign to 5B moves the furthest-travelling passenger into the seat, and everything updates',
        (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedBus);
      await leave(h, tester, 'a1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assign to 5B'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() async => (await h.db.doc('seat_allocations/s2').get()).data()!);
      expect(doc!['seat_number'], '5B');
      expect(doc['allocation_type'], 'manual_override');
      expect(find.byKey(const Key('empty-seat-title')), findsNothing, reason: 'dialog closed');
      expect(h.journeys.allocationForSeat('5B')?.allocationId, 's2');
      expect(h.journeys.standingPassengers.map((a) => a.allocationId).toSet(), {'s1', 's3'});
    });

    testWidgets('the conductor can pick a different standing passenger instead', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedBus);
      await leave(h, tester, 'a1');
      await tester.pumpAndSettle();

      // The second row's button is a plain "Assign".
      await tester.tap(find.widgetWithText(OutlinedButton, 'Assign').first);
      await settle(tester);
      await tester.pumpAndSettle();

      expect(h.journeys.allocationForSeat('5B')?.allocationId, 's3', reason: 'the second-furthest');
    });

    testWidgets('Not now leaves everything as it is', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedBus);
      await leave(h, tester, 'a1');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty-seat-title')), findsNothing);
      expect(h.journeys.allocationForSeat('5B'), isNull);
      expect(h.journeys.standingPassengers, hasLength(3));
    });

    testWidgets('if the seat is taken while the question is open, it says so and stays open',
        (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedBus);
      await leave(h, tester, 'a1');
      await tester.pumpAndSettle();

      await tester.runAsync(() => h.db.doc('seat_allocations/late').set(allocationDoc('late', '5B')));
      await settle(tester);

      await tester.tap(find.text('Assign to 5B'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('Seat 5B has just been taken.'), findsOneWidget);
      expect(find.byKey(const Key('empty-seat-title')), findsOneWidget);
    });

    testWidgets('two seats freed one after the other are asked about one at a time', (tester) async {
      final h = await open(tester, const HomeShell(), seed: (db) async {
        await seedBus(db);
        await db.doc('seat_allocations/a2').set(allocationDoc('a2', '6A'));
      });
      await tester.runAsync(() async {
        await h.db.doc('seat_allocations/a1').update({'status': 'released'});
        await h.db.doc('seat_allocations/a2').update({'status': 'released'});
      });
      await settle(tester);
      await tester.pumpAndSettle();

      final first = tester.widget<Text>(find.byKey(const Key('empty-seat-title'))).data;
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      final second = tester.widget<Text>(find.byKey(const Key('empty-seat-title'))).data;

      expect({first, second}, {'Seat 5B is empty', 'Seat 6A is empty'});
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('empty-seat-title')), findsNothing);
    });

    testWidgets('the alert also lands in the Alerts list', (tester) async {
      final h = await open(tester, const HomeShell(), seed: (db) => seedBus(db, standing: false));
      await leave(h, tester, 'a1');
      // Let the 3-second alert finish first. Its timer starts only after the
      // entrance animation, and isn't a frame, so pumpAndSettle alone won't wait.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Alerts')));
      await tester.pumpAndSettle();
      expect(find.text('Passenger left'), findsOneWidget);
      expect(find.text('Seat 5B is empty again.'), findsOneWidget);
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
