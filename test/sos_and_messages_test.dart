import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safeboard_conductor/data/conductor_repository.dart';
import 'package:safeboard_conductor/models/conductor_message.dart';
import 'package:safeboard_conductor/models/incident_report.dart';
import 'package:safeboard_conductor/providers/journey_stream_provider.dart';
import 'package:safeboard_conductor/providers/notifications_provider.dart';
import 'package:safeboard_conductor/screens/home_shell.dart';
import 'package:safeboard_conductor/screens/incidents_screen.dart';
import 'package:safeboard_conductor/screens/messages_screen.dart';

import 'trip_logic_test.dart' show allocation, journey, pump;
import 'trip_widgets_test.dart' show open, settle;

/// An SOS exactly as the passenger app's JourneyProvider.triggerSOS files it.
Map<String, dynamic> sosDoc(String id, String seat,
        {String status = 'escalated', String journeyId = 'JRN_1', String when = '2026-09-22T10:00:00.000Z'}) =>
    {
      'incident_id': id,
      'journey_id': journeyId,
      'reporter_passenger_id': 'p_28745',
      'incident_type': 'unwanted_contact',
      'incident_datetime': when,
      'seat_location': seat,
      'severity_level': 'high',
      'description': 'SOS triggered by passenger from the Journey tab.',
      'action_taken': 'Conductor notified via FCM · seat and GPS point attached',
      'status': status,
      'resolution_date': null,
    };

Map<String, dynamic> incidentDoc(String id, {String status = 'pending', String severity = 'medium'}) => {
      'incident_id': id,
      'journey_id': 'JRN_1',
      'reporter_passenger_id': 'p_1',
      'incident_type': 'verbal_harassment',
      'incident_datetime': '2026-09-22T09:00:00.000Z',
      'seat_location': '4A',
      'severity_level': severity,
      'description': 'Comments',
      'action_taken': 'Notified Conductor',
      'status': status,
      'resolution_date': null,
    };

Map<String, dynamic> msgDoc(String id, String seat, String text,
        {String bus = 'BUS_1',
        String journeyId = 'JRN_1',
        String status = 'sent',
        String when = '2026-09-22T10:00:00.000Z'}) =>
    {
      'message_id': id,
      'journey_id': journeyId,
      'bus_id': bus,
      'passenger_id': 'p_28745',
      'seat_number': seat,
      'message_text': text,
      'sent_datetime': when,
      'status': status,
    };

Map<String, dynamic> journeyDoc1() => journey('JRN_1');

void main() {
  group('SOS detection', () {
    IncidentReport parse(Map<String, dynamic> m) => IncidentReport.fromMap(m, m['incident_id'] as String);

    test('recognises the passenger app\'s SOS reports, not ordinary incidents', () {
      expect(parse(sosDoc('SOS_1789989505567', '5B')).isSos, isTrue);
      expect(parse(incidentDoc('INC_1789989505567')).isSos, isFalse);
      expect(parse(sosDoc('demo_SOS_live_1', '5B')).isSos, isTrue);
      // Falls back to the description if an id is ever missing.
      expect(IncidentReport.fromMap({'description': 'SOS triggered by passenger from the Journey tab.'}, 'x').isSos,
          isTrue);
      expect(IncidentReport.fromMap({'description': 'Someone was rude'}, 'x').isSos, isFalse);
    });

    test('only an unacknowledged SOS demands attention', () {
      expect(parse(sosDoc('SOS_1', '5B')).isAwaitingAcknowledgement, isTrue);
      expect(parse(sosDoc('SOS_1', '5B', status: 'pending')).isAwaitingAcknowledgement, isTrue);
      expect(parse(sosDoc('SOS_1', '5B', status: 'acknowledged')).isAwaitingAcknowledgement, isFalse);
      expect(parse(sosDoc('SOS_1', '5B', status: 'resolved')).isAwaitingAcknowledgement, isFalse);
      expect(parse(incidentDoc('INC_1', status: 'escalated')).isAwaitingAcknowledgement, isFalse,
          reason: 'not an SOS');
    });

    test('the inbox puts unacknowledged SOS first, even above older high-severity reports', () {
      final sorted = sortIncidentInbox([
        parse(incidentDoc('INC_high', severity: 'high')),
        parse(sosDoc('SOS_new', '5B', when: '2026-09-22T11:00:00.000Z')),
        parse(sosDoc('SOS_done', '2A', status: 'resolved')),
        parse(incidentDoc('INC_low', severity: 'low')),
      ]);
      expect(sorted.map((i) => i.incidentId), ['SOS_new', 'INC_high', 'INC_low', 'SOS_done']);
    });
  });

  group('ConductorMessage', () {
    test('parses the passenger app\'s snake_case document', () {
      final m = ConductorMessage.fromMap(msgDoc('msg_1', '3A', 'Can I get a seat change?'), 'msg_1');
      expect(m.messageId, 'msg_1');
      expect(m.seatNumber, '3A');
      expect(m.text, 'Can I get a seat change?');
      expect(m.busId, 'BUS_1');
      expect(m.sentDatetime, DateTime.utc(2026, 9, 22, 10));
      expect(m.isUnread, isTrue);
    });

    test('a message with no status counts as sent/unread; "read" is read', () {
      expect(ConductorMessage.fromMap({'message_text': 'hi'}, 'x').isUnread, isTrue);
      expect(ConductorMessage.fromMap({'status': 'read'}, 'x').isUnread, isFalse);
    });

    test('missing fields become safe defaults', () {
      final m = ConductorMessage.fromMap({}, 'msg_x');
      expect(m.messageId, 'msg_x');
      expect(m.text, '');
      expect(m.sentDatetime, isNull);
    });
  });

  group('JourneyStreamProvider: SOS and messages', () {
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

    test('an unacknowledged SOS already waiting at load is queued', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '5B'));
      await db.doc('incident_reports/SOS_2').set(sosDoc('SOS_2', '2A', status: 'acknowledged'));
      await db.doc('incident_reports/SOS_3').set(sosDoc('SOS_3', '3A', status: 'resolved'));
      await db.doc('incident_reports/INC_1').set(incidentDoc('INC_1', status: 'escalated'));
      await bind();

      expect(provider.pendingSos.map((i) => i.incidentId), ['SOS_1']);
    });

    test('a new SOS arriving live is queued and raises an SOS alert with its seat', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await bind();
      expect(provider.pendingSos, isEmpty);

      await db.doc('incident_reports/SOS_9').set(sosDoc('SOS_9', '7C'));
      await pump();

      expect(provider.pendingSos.single.seatLocation, '7C');
      expect(notifications.items.first.title, 'SOS alert');
      expect(notifications.items.first.body, contains('7C'));
    });

    test('an ordinary incident is announced as before and never queued as SOS', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await bind();
      await db.doc('incident_reports/INC_9').set(incidentDoc('INC_9'));
      await pump();

      expect(provider.pendingSos, isEmpty);
      expect(notifications.items.first.title, 'New incident reported');
    });

    test('each SOS is shown once per session, whatever the conductor chose', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '5B'));
      await bind();

      provider.markSosHandled(provider.pendingSos.single);
      expect(provider.pendingSos, isEmpty);

      // A snapshot refresh (any change to the collection) must not resurrect it.
      await db.doc('incident_reports/INC_2').set(incidentDoc('INC_2'));
      await pump();
      expect(provider.pendingSos, isEmpty);

      // A different SOS still gets through.
      await db.doc('incident_reports/SOS_2').set(sosDoc('SOS_2', '6A'));
      await pump();
      expect(provider.pendingSos.map((i) => i.incidentId), ['SOS_2']);
    });

    test('several SOS queue oldest first', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('incident_reports/SOS_b').set(sosDoc('SOS_b', '6A', when: '2026-09-22T10:05:00.000Z'));
      await db.doc('incident_reports/SOS_a').set(sosDoc('SOS_a', '5B', when: '2026-09-22T10:00:00.000Z'));
      await bind();
      expect(provider.pendingSos.map((i) => i.incidentId), ['SOS_a', 'SOS_b']);
    });

    test('acknowledging writes only status and action_taken, keeps the passenger\'s data', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '5B'));
      await bind();

      expect(await provider.acknowledgeSos(provider.pendingSos.single), isNull);
      await pump();

      final doc = (await db.doc('incident_reports/SOS_1').get()).data()!;
      expect(doc['status'], 'acknowledged');
      expect(doc['action_taken'], 'Conductor acknowledged the SOS alert');
      expect(doc['resolution_date'], isNull, reason: 'acknowledged is not resolved');
      final original = sosDoc('SOS_1', '5B');
      for (final key in original.keys.toSet()..removeAll({'status', 'action_taken'})) {
        expect(doc[key], original[key], reason: '$key must be unchanged');
      }
      expect(provider.pendingSos, isEmpty);
    });

    test('a failed acknowledgement is reported, and does not pop up again', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '5B'));
      await bind();
      final incident = provider.pendingSos.single;

      await db.doc('incident_reports/SOS_1').delete();
      final error = await provider.acknowledgeSos(incident);

      expect(error, isNotNull);
      expect(provider.pendingSos, isEmpty);
    });

    test('allocationForSeat finds this bus\'s booking for a seat, case-insensitively', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('seat_allocations/a1').set(allocation('a1', '5B'));
      await db.doc('seat_allocations/a2').set(allocation('a2', '6A', bus: 'BUS_2'));
      await bind();

      expect(provider.allocationForSeat('5b')?.allocationId, 'a1');
      expect(provider.allocationForSeat(' 5B ')?.allocationId, 'a1');
      expect(provider.allocationForSeat('6A'), isNull, reason: 'booked on another bus');
      expect(provider.allocationForSeat(''), isNull);
    });

    test('messages: this trip and bus only, newest first, with an unread count', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('conductor_messages/m1').set(msgDoc('m1', '3A', 'older', when: '2026-09-22T10:00:00.000Z'));
      await db.doc('conductor_messages/m2').set(msgDoc('m2', '4B', 'newer', when: '2026-09-22T10:30:00.000Z'));
      await db.doc('conductor_messages/m3').set(msgDoc('m3', '5C', 'read one', status: 'read'));
      await db.doc('conductor_messages/m4').set(msgDoc('m4', '6D', 'other bus', bus: 'BUS_2'));
      await db.doc('conductor_messages/m5').set(msgDoc('m5', '7A', 'other trip', journeyId: 'JRN_OTHER'));
      await db.doc('conductor_messages/m6').set({...msgDoc('m6', '8B', 'no bus id'), 'bus_id': ''});
      await bind();

      expect(provider.messages.map((m) => m.messageId).toSet(), {'m1', 'm2', 'm3', 'm6'});
      expect(provider.messages.first.messageId, 'm2');
      expect(provider.unreadMessageCount, 3);
    });

    test('a trip with no conductor_messages collection yet is simply empty, not an error', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await bind();
      expect(provider.messages, isEmpty);
      expect(provider.unreadMessageCount, 0);
      expect(provider.tripError, isNull);
    });

    test('a message sent while the app is open updates live and raises an alert', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('conductor_messages/old').set(msgDoc('old', '3A', 'already there'));
      await bind();
      expect(notifications.items, isEmpty, reason: 'existing messages are not announced');

      await db.doc('conductor_messages/new').set(msgDoc('new', '4B', 'The bus feels overcrowded right now'));
      await pump();

      expect(provider.messages.length, 2);
      expect(notifications.items.first.title, 'New message');
      expect(notifications.items.first.body, contains('4B'));
      expect(notifications.items.first.body, contains('overcrowded'));
    });

    test('an already-read message raises no alert', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await bind();
      await db.doc('conductor_messages/r').set(msgDoc('r', '4B', 'seen', status: 'read'));
      await pump();
      expect(notifications.items, isEmpty);
    });

    test('marking a message read changes only its status', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      final original = msgDoc('m1', '3A', 'Can I get a seat change?');
      await db.doc('conductor_messages/m1').set(original);
      await bind();

      expect(await provider.markMessageRead(provider.messages.single), isNull);
      await pump();

      final doc = (await db.doc('conductor_messages/m1').get()).data()!;
      expect(doc['status'], 'read');
      for (final key in original.keys.where((k) => k != 'status')) {
        expect(doc[key], original[key], reason: '$key must be unchanged');
      }
      expect(provider.unreadMessageCount, 0);
    });

    test('mark all read clears every unread message', () async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      for (final id in ['a', 'b', 'c']) {
        await db.doc('conductor_messages/$id').set(msgDoc(id, '3A', 'hi $id'));
      }
      await bind();
      expect(provider.unreadMessageCount, 3);

      expect(await provider.markAllMessagesRead(), isNull);
      await pump();
      expect(provider.unreadMessageCount, 0);
    });
  });

  group('SOS pop-up', () {
    Future<void> seedSos(FakeFirebaseFirestore db) async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('seat_allocations/a1').set(allocation('a1', '5B'));
      await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '5B'));
    }

    Finder bigSeat() => find.byKey(const Key('sos-seat'));

    testWidgets('shows a big seat number with the passenger\'s booking', (tester) async {
      await open(tester, const HomeShell(), seed: seedSos);
      await tester.pumpAndSettle();

      expect(find.text('SOS ALERT'), findsOneWidget);
      expect(tester.widget<Text>(bigSeat()).data, '5B');
      expect(tester.widget<Text>(bigSeat()).style!.fontSize, greaterThanOrEqualTo(72),
          reason: 'the seat number must dominate the pop-up');
      expect(find.text('General'), findsWidgets, reason: 'zone of seat 5B');
      expect(find.textContaining('Jaffna Main Bus Stand'), findsWidgets);
    });

    testWidgets('says so when the seat has no booking on this bus', (tester) async {
      await open(tester, const HomeShell(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc1());
        await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '11C'));
      });
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(bigSeat()).data, '11C');
      expect(find.text('No booking found for this seat on your bus.'), findsOneWidget,
          reason: 'still raised: a missed SOS is worse than a false alarm');
    });

    testWidgets('appears live, over whichever tab is open', (tester) async {
      final h = await open(tester, const HomeShell(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      });
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Cash')));
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsNothing);

      await tester.runAsync(() => h.db.doc('incident_reports/SOS_live').set(sosDoc('SOS_live', '9E')));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('SOS ALERT'), findsOneWidget);
      expect(tester.widget<Text>(bigSeat()).data, '9E');
    });

    testWidgets('I\'m on my way acknowledges it in Firestore and closes the pop-up', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedSos);
      await tester.pumpAndSettle();

      await tester.tap(find.text('I\'m on my way'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() async => (await h.db.doc('incident_reports/SOS_1').get()).data()!);
      expect(doc!['status'], 'acknowledged');
      expect(doc['action_taken'], 'Conductor acknowledged the SOS alert');
      expect(find.text('SOS ALERT'), findsNothing);
      expect(find.text('SOS acknowledged.'), findsOneWidget);
    });

    testWidgets('Later closes it without changing the incident, and it does not come back', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedSos);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsNothing);

      // Force plenty of rebuilds / new data: it must stay dismissed.
      await tester.runAsync(() => h.db.doc('incident_reports/INC_9').set(incidentDoc('INC_9')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsNothing);

      final doc = await tester.runAsync(() async => (await h.db.doc('incident_reports/SOS_1').get()).data()!);
      expect(doc!['status'], 'escalated', reason: 'still unacknowledged, still on the Incidents tab');
    });

    testWidgets('View incident closes it and opens the Incidents tab', (tester) async {
      await open(tester, const HomeShell(), seed: seedSos);
      await tester.pumpAndSettle();

      await tester.tap(find.text('View incident'));
      await tester.pumpAndSettle();

      expect(find.text('SOS ALERT'), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Incidents')), findsOneWidget);
    });

    testWidgets('cannot be dismissed by tapping outside it', (tester) async {
      await open(tester, const HomeShell(), seed: seedSos);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsOneWidget);
    });

    testWidgets('several SOS are shown one after another', (tester) async {
      await open(tester, const HomeShell(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc1());
        await db.doc('incident_reports/SOS_a').set(sosDoc('SOS_a', '5B', when: '2026-09-22T10:00:00.000Z'));
        await db.doc('incident_reports/SOS_b').set(sosDoc('SOS_b', '6A', when: '2026-09-22T10:05:00.000Z'));
      });
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(bigSeat()).data, '5B');
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(bigSeat()).data, '6A');
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsNothing);
    });

    testWidgets('an ordinary incident does not pop up', (tester) async {
      await open(tester, const HomeShell(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc1());
        await db.doc('incident_reports/INC_1').set(incidentDoc('INC_1', status: 'escalated', severity: 'high'));
      });
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsNothing);
    });

    testWidgets('an already-acknowledged SOS does not pop up', (tester) async {
      await open(tester, const HomeShell(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc1());
        await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '5B', status: 'acknowledged'));
      });
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsNothing);
    });
  });

  group('Incidents tab and SOS', () {
    testWidgets('an SOS is badged, sorted first, and defaults to Acknowledged when updated',
        (tester) async {
      await open(tester, const IncidentsScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc1());
        await db.doc('incident_reports/INC_1').set(incidentDoc('INC_1', severity: 'high'));
        await db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '5B'));
      });

      expect(find.text('SOS'), findsOneWidget);
      final sosTop = tester.getTopLeft(find.text('SOS')).dy;
      final normalTop = tester.getTopLeft(find.text('Verbal harassment')).dy;
      expect(sosTop, lessThan(normalTop), reason: 'the SOS card is above the ordinary one');
      expect(find.text('Escalated'), findsOneWidget);

      await tester.tap(find.text('SOS'));
      await tester.pumpAndSettle();
      final picker = tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(picker.selected, {'acknowledged'},
          reason: 'saving must not silently reset an escalated SOS to pending');
    });
  });

  group('Messages page', () {
    Future<void> seedMessages(FakeFirebaseFirestore db) async {
      await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      await db.doc('conductor_messages/m1').set(msgDoc('m1', '3A', 'Can I get a seat change?',
          when: '2026-09-22T10:00:00.000Z'));
      await db.doc('conductor_messages/m2').set(msgDoc('m2', '4B', 'The bus feels overcrowded right now',
          when: '2026-09-22T10:30:00.000Z'));
      await db.doc('conductor_messages/m3').set(msgDoc('m3', '5C', 'Thank you, all good',
          status: 'read', when: '2026-09-22T09:00:00.000Z'));
    }

    testWidgets('lists messages newest first, with seat and text, and marks the new ones', (tester) async {
      await open(tester, const MessagesScreen(), seed: seedMessages);

      expect(find.text('2 new'), findsOneWidget);
      expect(find.text('Seat 4B'), findsOneWidget);
      expect(find.text('The bus feels overcrowded right now'), findsOneWidget);
      expect(find.text('Seat 3A'), findsOneWidget);
      expect(find.text('Seat 5C'), findsOneWidget);
      expect(find.text('New'), findsNWidgets(2), reason: 'the read message has no New pill');

      final newest = tester.getTopLeft(find.text('Seat 4B')).dy;
      final middle = tester.getTopLeft(find.text('Seat 3A')).dy;
      final oldest = tester.getTopLeft(find.text('Seat 5C')).dy;
      expect(newest, lessThan(middle));
      expect(middle, lessThan(oldest));
    });

    testWidgets('tapping a message marks it read in Firestore', (tester) async {
      final h = await open(tester, const MessagesScreen(), seed: seedMessages);

      await tester.tap(find.text('The bus feels overcrowded right now'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() async => (await h.db.doc('conductor_messages/m2').get()).data()!);
      expect(doc!['status'], 'read');
      expect(find.text('1 new'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('Mark all as read clears them', (tester) async {
      await open(tester, const MessagesScreen(), seed: seedMessages);

      await tester.tap(find.byTooltip('Mark all as read'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('All caught up'), findsOneWidget);
      expect(find.text('New'), findsNothing);
      expect(find.byTooltip('Mark all as read'), findsNothing);
    });

    testWidgets('a message sent while the page is open appears without reloading', (tester) async {
      final h = await open(tester, const MessagesScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(journeyDoc1());
      });
      expect(find.text('No messages yet'), findsOneWidget);

      await tester.runAsync(() => h.db.doc('conductor_messages/live').set(
          msgDoc('live', '2C', 'How many stops to my destination?')));
      await settle(tester);

      expect(find.text('No messages yet'), findsNothing);
      expect(find.text('Seat 2C'), findsOneWidget);
      expect(find.text('How many stops to my destination?'), findsOneWidget);
    });

    testWidgets('without a trip it says so', (tester) async {
      await open(tester, const MessagesScreen());
      expect(find.text('No active trip'), findsOneWidget);
    });

    testWidgets('the app bar shows the unread count and opens the page', (tester) async {
      await open(tester, const HomeShell(), seed: seedMessages);

      expect(find.descendant(of: find.byTooltip('Messages'), matching: find.text('2')), findsOneWidget);

      await tester.tap(find.byTooltip('Messages'));
      await tester.pumpAndSettle();
      expect(find.text('Seat 4B'), findsOneWidget);
      expect(find.text('The bus feels overcrowded right now'), findsOneWidget);
    });
  });
}
