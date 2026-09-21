import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safeboard_conductor/data/conductor_repository.dart';
import 'package:safeboard_conductor/models/conductor_message.dart';
import 'package:safeboard_conductor/providers/journey_stream_provider.dart';
import 'package:safeboard_conductor/providers/notifications_provider.dart';
import 'package:safeboard_conductor/screens/home_shell.dart';
import 'package:safeboard_conductor/screens/messages_screen.dart';

import 'sos_and_messages_test.dart' show msgDoc, sosDoc;
import 'trip_logic_test.dart' show journey, pump;
import 'trip_widgets_test.dart' show open, settle;

Map<String, dynamic> trip() => journey('JRN_1');

void main() {
  group('ConductorMessage replies', () {
    test('parses the replies array; a replied message no longer counts as unread', () {
      final m = ConductorMessage.fromMap({
        ...msgDoc('m1', '4B', 'Can I get a seat change?', status: 'replied'),
        'replies': [
          {'text': 'On my way', 'sent_datetime': '2026-09-22T10:05:00.000Z', 'conductor_id': 'CND_T'},
          {'text': 'Seat 2C is free', 'sent_datetime': '2026-09-22T10:06:00.000Z', 'conductor_id': 'CND_T'},
        ],
      }, 'm1');

      expect(m.hasReply, isTrue);
      expect(m.replies.map((r) => r.text), ['On my way', 'Seat 2C is free']);
      expect(m.replies.first.sentDatetime, DateTime.utc(2026, 9, 22, 10, 5));
      expect(m.replies.first.conductorId, 'CND_T');
      expect(m.isUnread, isFalse);
    });

    test('no replies field means no replies; sent is unread, read and replied are not', () {
      final m = ConductorMessage.fromMap(msgDoc('m1', '4B', 'hi'), 'm1');
      expect(m.replies, isEmpty);
      expect(m.hasReply, isFalse);
      expect(m.isUnread, isTrue);
      expect(ConductorMessage.fromMap(msgDoc('m', '4B', 'hi', status: 'read'), 'm').isUnread, isFalse);
      expect(ConductorMessage.fromMap(msgDoc('m', '4B', 'hi', status: 'replied'), 'm').isUnread, isFalse);
    });

    test('malformed reply entries are ignored, not fatal', () {
      final m = ConductorMessage.fromMap({
        ...msgDoc('m1', '4B', 'hi'),
        'replies': ['just a string', 42, {'text': 'ok'}],
      }, 'm1');
      expect(m.replies.map((r) => r.text), ['ok']);
    });
  });

  group('ConductorRepository.replyToMessage', () {
    late FakeFirebaseFirestore db;
    late ConductorRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = ConductorRepository(db);
    });

    test('appends the reply with an ISO date, sets status, and touches nothing else', () async {
      final original = msgDoc('m1', '4B', 'Can I get a seat change?');
      await db.doc('conductor_messages/m1').set(original);

      await repo.replyToMessage('m1',
          text: 'On my way', conductorId: 'CND_T', sentAt: DateTime.utc(2026, 9, 22, 10, 5));

      final doc = (await db.doc('conductor_messages/m1').get()).data()!;
      expect(doc['status'], 'replied');
      final replies = doc['replies'] as List;
      expect(replies.length, 1);
      final reply = replies.single as Map;
      expect(reply['text'], 'On my way');
      expect(reply['conductor_id'], 'CND_T');
      expect(reply['sent_datetime'], isA<String>(), reason: 'ISO string, never a Timestamp');
      expect(DateTime.parse(reply['sent_datetime'] as String), DateTime.utc(2026, 9, 22, 10, 5));
      for (final key in original.keys.where((k) => k != 'status')) {
        expect(doc[key], original[key], reason: '$key must be unchanged');
      }
    });

    test('a second reply is added after the first, never replacing it', () async {
      await db.doc('conductor_messages/m1').set(msgDoc('m1', '4B', 'hi'));
      await repo.replyToMessage('m1', text: 'first', conductorId: 'CND_T', sentAt: DateTime.utc(2026, 9, 22, 10, 5));
      await repo.replyToMessage('m1', text: 'second', conductorId: 'CND_T', sentAt: DateTime.utc(2026, 9, 22, 10, 6));

      final replies = (await db.doc('conductor_messages/m1').get()).data()!['replies'] as List;
      expect(replies.map((r) => (r as Map)['text']), ['first', 'second']);
    });

    test('replying to a message that does not exist fails instead of creating it', () async {
      await expectLater(
        repo.replyToMessage('nope', text: 'x', conductorId: 'CND_T', sentAt: DateTime.utc(2026)),
        throwsA(anything),
      );
      expect((await db.collection('conductor_messages').get()).docs, isEmpty);
    });
  });

  group('JourneyStreamProvider: message pop-ups and replies', () {
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

    test('a message sent while the app is open is queued for a pop-up', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await bind();
      expect(provider.pendingMessagePopups, isEmpty);

      await db.doc('conductor_messages/new').set(msgDoc('new', '4B', 'The bus feels overcrowded right now'));
      await pump();

      expect(provider.pendingMessagePopups.single.text, 'The bus feels overcrowded right now');
      expect(provider.pendingMessagePopups.single.seatNumber, '4B');
    });

    test('messages already waiting at load only raise the badge, they do not pop up', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await db.doc('conductor_messages/old').set(msgDoc('old', '3A', 'sent earlier'));
      await bind();

      expect(provider.pendingMessagePopups, isEmpty);
      expect(provider.unreadMessageCount, 1);
    });

    test('a message that arrives already read or answered does not pop up', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await bind();
      await db.doc('conductor_messages/r').set(msgDoc('r', '4B', 'seen', status: 'read'));
      await db.doc('conductor_messages/p').set(msgDoc('p', '5C', 'answered', status: 'replied'));
      await pump();
      expect(provider.pendingMessagePopups, isEmpty);
    });

    test('several arrivals queue oldest first', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await bind();
      await db.doc('conductor_messages/a').set(msgDoc('a', '3A', 'first'));
      await pump();
      await db.doc('conductor_messages/b').set(msgDoc('b', '4B', 'second'));
      await pump();
      expect(provider.pendingMessagePopups.map((m) => m.messageId), ['a', 'b']);
    });

    test('once handled, a message does not pop up again but stays in the list', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await bind();
      await db.doc('conductor_messages/a').set(msgDoc('a', '3A', 'hello'));
      await pump();

      provider.markMessagePopupHandled(provider.pendingMessagePopups.single);
      expect(provider.pendingMessagePopups, isEmpty);

      // More traffic in the collection must not resurrect it.
      await db.doc('conductor_messages/b').set(msgDoc('b', '4B', 'another', status: 'read'));
      await pump();
      expect(provider.pendingMessagePopups, isEmpty);
      expect(provider.messages.map((m) => m.messageId).toSet(), {'a', 'b'});
      expect(provider.unreadMessageCount, 1, reason: 'still unread until opened or answered');
    });

    test('a message read elsewhere drops out of the pop-up queue', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await bind();
      await db.doc('conductor_messages/a').set(msgDoc('a', '3A', 'hello'));
      await pump();
      expect(provider.pendingMessagePopups, hasLength(1));

      await provider.markMessageRead(provider.messages.single);
      await pump();
      expect(provider.pendingMessagePopups, isEmpty);
    });

    test('replying stores the reply, marks it replied, handles the pop-up, and keeps the message',
        () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await bind();
      await db.doc('conductor_messages/a').set(msgDoc('a', '4B', 'Can I get a seat change?'));
      await pump();

      expect(await provider.replyToMessage(provider.pendingMessagePopups.single, '  On my way  '), isNull);
      await pump();

      final doc = (await db.doc('conductor_messages/a').get()).data()!;
      expect(doc['status'], 'replied');
      expect(((doc['replies'] as List).single as Map)['text'], 'On my way', reason: 'trimmed');
      expect(((doc['replies'] as List).single as Map)['conductor_id'], 'CND_T');

      expect(provider.pendingMessagePopups, isEmpty);
      expect(provider.messages.single.hasReply, isTrue, reason: 'still on the Messages page');
      expect(provider.messages.single.replies.single.text, 'On my way');
      expect(provider.unreadMessageCount, 0);
    });

    test('an empty reply is refused and writes nothing', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await db.doc('conductor_messages/a').set(msgDoc('a', '4B', 'hi'));
      await bind();

      expect(await provider.replyToMessage(provider.messages.single, '   '), 'Type a reply first.');
      final doc = (await db.doc('conductor_messages/a').get()).data()!;
      expect(doc['status'], 'sent');
      expect(doc.containsKey('replies'), isFalse);
    });

    test('when signed out, replying says so', () async {
      final message = ConductorMessage.fromMap(msgDoc('a', '4B', 'hi'), 'a');
      expect(await provider.replyToMessage(message, 'hello'), 'You are not signed in.');
    });

    test('a failed reply reports the error and leaves the pop-up pending', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await bind();
      await db.doc('conductor_messages/a').set(msgDoc('a', '4B', 'hi'));
      await pump();
      final message = provider.pendingMessagePopups.single;

      await db.doc('conductor_messages/a').delete();
      final error = await provider.replyToMessage(message, 'On my way');

      expect(error, isNotNull);
    });

    test('marking a replied message read never downgrades it', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await db.doc('conductor_messages/a').set(msgDoc('a', '4B', 'hi', status: 'replied'));
      await bind();

      expect(await provider.markMessageRead(provider.messages.single), isNull);
      expect((await db.doc('conductor_messages/a').get()).data()!['status'], 'replied');
    });

    test('a reply written elsewhere shows up live', () async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await db.doc('conductor_messages/a').set(msgDoc('a', '4B', 'hi'));
      await bind();
      expect(provider.messages.single.hasReply, isFalse);

      await ConductorRepository(db).replyToMessage('a',
          text: 'Yes', conductorId: 'CND_T', sentAt: DateTime.utc(2026, 9, 22, 10, 5));
      await pump();
      expect(provider.messages.single.replies.single.text, 'Yes');
    });
  });

  group('Message pop-up', () {
    Future<void> seedTrip(FakeFirebaseFirestore db) async {
      await db.doc('journey_instances/JRN_1').set(trip());
    }

    Finder seat() => find.byKey(const Key('message-seat'));
    Finder text() => find.byKey(const Key('message-text'));

    Future<void> sendFromPassenger(dynamic h, WidgetTester tester, String id, String seatNo, String body,
        {String status = 'sent'}) async {
      await tester.runAsync(() => h.db.doc('conductor_messages/$id').set(msgDoc(id, seatNo, body, status: status)));
      await settle(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('a message from a passenger pops up live, with seat and text large', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      expect(find.text('NEW MESSAGE'), findsNothing);

      await sendFromPassenger(h, tester, 'm1', '4B', 'The bus feels overcrowded right now');

      expect(find.text('NEW MESSAGE'), findsOneWidget);
      expect(tester.widget<Text>(seat()).data, 'Seat 4B');
      expect(tester.widget<Text>(text()).data, '"The bus feels overcrowded right now"');
      expect(tester.widget<Text>(text()).style!.fontSize, greaterThanOrEqualTo(20));
    });

    testWidgets('it pops up over any tab, not just Trip', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Cash')));
      await tester.pumpAndSettle();

      await sendFromPassenger(h, tester, 'm1', '9E', 'Thank you, all good');
      expect(find.text('NEW MESSAGE'), findsOneWidget);
    });

    testWidgets('messages already waiting when the app opens do not pop up', (tester) async {
      await open(tester, const HomeShell(), seed: (db) async {
        await seedTrip(db);
        await db.doc('conductor_messages/old').set(msgDoc('old', '3A', 'sent earlier'));
      });
      await tester.pumpAndSettle();
      expect(find.text('NEW MESSAGE'), findsNothing);
    });

    testWidgets('a quick reply fills the box and sends; the message stays on the Messages page with the reply',
        (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      await sendFromPassenger(h, tester, 'm1', '4B', 'Can I get a seat change?');

      await tester.tap(find.text('On my way'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('reply-field'))).controller!.text, 'On my way');

      await tester.tap(find.text('Send reply'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() async => (await h.db.doc('conductor_messages/m1').get()).data()!);
      expect(doc!['status'], 'replied');
      expect(((doc['replies'] as List).single as Map)['text'], 'On my way');
      expect(find.text('NEW MESSAGE'), findsNothing, reason: 'the pop-up closes after replying');

      // The message is still there, with the reply, on the Messages page.
      await tester.tap(find.byTooltip('Messages'));
      await tester.pumpAndSettle();
      expect(find.text('Seat 4B'), findsOneWidget);
      expect(find.text('Can I get a seat change?'), findsOneWidget);
      expect(find.text('On my way'), findsOneWidget);
      expect(find.text('Replied'), findsOneWidget);
      expect(find.text('Reply again'), findsOneWidget);
    });

    testWidgets('a typed reply is sent as written', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      await sendFromPassenger(h, tester, 'm1', '4B', 'How many stops to my destination?');

      await tester.enterText(find.byKey(const Key('reply-field')), 'Six more stops, about an hour.');
      await tester.tap(find.text('Send reply'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() async => (await h.db.doc('conductor_messages/m1').get()).data()!);
      expect(((doc!['replies'] as List).single as Map)['text'], 'Six more stops, about an hour.');
    });

    testWidgets('sending an empty reply says so and keeps the pop-up open', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      await sendFromPassenger(h, tester, 'm1', '4B', 'hi');

      await tester.tap(find.text('Send reply'));
      await tester.pumpAndSettle();

      expect(find.text('Type a reply first.'), findsOneWidget);
      expect(find.text('NEW MESSAGE'), findsOneWidget);
    });

    testWidgets('Later closes it but the message stays unread on the Messages page, and it does not return',
        (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      await sendFromPassenger(h, tester, 'm1', '4B', 'Can I get a seat change?');

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('NEW MESSAGE'), findsNothing);

      // Unrelated traffic must not bring it back.
      await sendFromPassenger(h, tester, 'm2', '5C', 'Thank you, all good', status: 'read');
      expect(find.text('NEW MESSAGE'), findsNothing);

      final doc = await tester.runAsync(() async => (await h.db.doc('conductor_messages/m1').get()).data()!);
      expect(doc!['status'], 'sent');

      await tester.tap(find.byTooltip('Messages'));
      await tester.pumpAndSettle();
      expect(find.text('Can I get a seat change?'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('tapping outside dismisses it like Later', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      await sendFromPassenger(h, tester, 'm1', '4B', 'hi');

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('NEW MESSAGE'), findsNothing);
    });

    testWidgets('an SOS is shown before a message, then the message follows', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      await tester.runAsync(() async {
        await h.db.doc('conductor_messages/m1').set(msgDoc('m1', '4B', 'hi'));
      });
      await settle(tester);
      // The message pop-up is up; an SOS arrives behind it.
      await tester.pumpAndSettle();
      expect(find.text('NEW MESSAGE'), findsOneWidget);
      await tester.runAsync(() => h.db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '9E')));
      await settle(tester);

      // Close the message pop-up: the SOS comes next, then nothing else.
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('SOS ALERT'), findsNothing);
      expect(find.text('NEW MESSAGE'), findsNothing);
    });

    testWidgets('when an SOS and a message are both waiting, the SOS comes first', (tester) async {
      final h = await open(tester, const HomeShell(), seed: seedTrip);
      // Both land in the same frame.
      await tester.runAsync(() async {
        await h.db.doc('incident_reports/SOS_1').set(sosDoc('SOS_1', '9E'));
        await h.db.doc('conductor_messages/m1').set(msgDoc('m1', '4B', 'hi'));
      });
      await settle(tester);
      await tester.pumpAndSettle();

      expect(find.text('SOS ALERT'), findsOneWidget);
      expect(find.text('NEW MESSAGE'), findsNothing);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('NEW MESSAGE'), findsOneWidget, reason: 'then the message');
    });
  });

  group('Messages page', () {
    Future<void> seedOne(FakeFirebaseFirestore db) async {
      await db.doc('journey_instances/JRN_1').set(trip());
      await db.doc('conductor_messages/m1').set(msgDoc('m1', '4B', 'Can I get a seat change?'));
    }

    testWidgets('Reply opens a sheet, sends, and shows the reply under the message', (tester) async {
      final h = await open(tester, const MessagesScreen(), seed: seedOne);
      expect(find.text('Reply'), findsOneWidget);

      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Reply to seat 4B'), findsOneWidget);

      await tester.tap(find.text('I will arrange a seat change'));
      await tester.pump();
      await tester.tap(find.text('Send reply'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() async => (await h.db.doc('conductor_messages/m1').get()).data()!);
      expect(doc!['status'], 'replied');
      expect(find.text('Reply to seat 4B'), findsNothing, reason: 'sheet closed');
      expect(find.text('I will arrange a seat change'), findsOneWidget, reason: 'now shown as the reply bubble');
      expect(find.text('Replied'), findsOneWidget);
      expect(find.text('New'), findsNothing);
      expect(find.text('Reply again'), findsOneWidget);
    });

    testWidgets('a second reply is added under the first', (tester) async {
      final h = await open(tester, const MessagesScreen(), seed: seedOne);
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reply-field')), 'first');
      await tester.tap(find.text('Send reply'));
      await settle(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reply again'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reply-field')), 'second');
      await tester.tap(find.text('Send reply'));
      await settle(tester);
      await tester.pumpAndSettle();

      final doc = await tester.runAsync(() async => (await h.db.doc('conductor_messages/m1').get()).data()!);
      expect((doc!['replies'] as List).map((r) => (r as Map)['text']), ['first', 'second']);
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('says which journey it is listening on, and explains an empty page', (tester) async {
      await open(tester, const MessagesScreen(), seed: (db) async {
        await db.doc('journey_instances/JRN_1').set(trip());
      });
      expect(find.text('Listening on journey JRN_1 · bus BUS_1'), findsOneWidget);
      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.textContaining('JRN_87_001'), findsOneWidget,
          reason: 'tells the conductor which journey passengers message');
    });

    testWidgets('a reply written by another device appears live', (tester) async {
      final h = await open(tester, const MessagesScreen(), seed: seedOne);
      expect(find.text('Replied'), findsNothing);

      await tester.runAsync(() => ConductorRepository(h.db).replyToMessage('m1',
          text: 'Seat 2C is free', conductorId: 'CND_T', sentAt: DateTime.utc(2026, 9, 22, 10, 5)));
      await settle(tester);

      expect(find.text('Seat 2C is free'), findsOneWidget);
      expect(find.text('Replied'), findsOneWidget);
    });
  });
}
