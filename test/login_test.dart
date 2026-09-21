import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safeboard_conductor/data/conductor_repository.dart';
import 'package:safeboard_conductor/models/conductor.dart';
import 'package:safeboard_conductor/providers/conductor_provider.dart';
import 'package:safeboard_conductor/screens/login_screen.dart';

/// Lets fake-Firestore streams deliver, then rebuilds.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
  await tester.pump();
}

const emptyMessage =
    'No conductors found — check that the passenger app has been used to seed data.';

void main() {
  test('Conductor.fromMap reads the passenger app\'s snake_case document', () {
    final conductor = Conductor.fromMap({
      'conductor_id': 'CND_NB_8710',
      'name': 'K. Perera',
      'phone_number': '',
      'rating': 4.9,
    }, 'CND_NB_8710');
    expect(conductor.conductorId, 'CND_NB_8710');
    expect(conductor.name, 'K. Perera');
    expect(conductor.rating, 4.9);
  });

  test('Conductor.fromMap falls back to the document id and safe defaults', () {
    final conductor = Conductor.fromMap({}, 'CND_X');
    expect(conductor.conductorId, 'CND_X');
    expect(conductor.name, '');
    expect(conductor.rating, 0);
  });

  group('LoginScreen', () {
    late FakeFirebaseFirestore db;
    late ConductorProvider provider;

    setUp(() {
      db = FakeFirebaseFirestore();
      provider = ConductorProvider();
    });

    Widget app() => ChangeNotifierProvider<ConductorProvider>.value(
          value: provider,
          child: MaterialApp(
            home: LoginScreen(repository: ConductorRepository(db)),
            routes: {'/home': (_) => const Scaffold(body: Text('home stub'))},
          ),
        );

    Future<void> seed(
        Map<String, Map<String, dynamic>> conductors, WidgetTester tester) async {
      await tester.runAsync(() async {
        for (final entry in conductors.entries) {
          await db.doc('conductors/${entry.key}').set(entry.value);
        }
      });
    }

    testWidgets('lists each conductor with name and conductorId, sorted by name',
        (tester) async {
      await seed({
        'CND_NB_8720': {'conductor_id': 'CND_NB_8720', 'name': 'S. Fernando'},
        'CND_NB_8701': {'conductor_id': 'CND_NB_8701', 'name': 'A. Silva'},
        'CND_NB_8710': {'conductor_id': 'CND_NB_8710', 'name': 'K. Perera'},
      }, tester);
      await tester.pumpWidget(app());
      await settle(tester);

      for (final text in [
        'A. Silva', 'CND_NB_8701',
        'K. Perera', 'CND_NB_8710',
        'S. Fernando', 'CND_NB_8720',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      final silva = tester.getTopLeft(find.text('A. Silva')).dy;
      final perera = tester.getTopLeft(find.text('K. Perera')).dy;
      final fernando = tester.getTopLeft(find.text('S. Fernando')).dy;
      expect(silva, lessThan(perera));
      expect(perera, lessThan(fernando));
    });

    testWidgets('has no email or password fields', (tester) async {
      await seed({'CND_1': {'name': 'A. Silva'}}, tester);
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('assword'), findsNothing);
    });

    testWidgets('tapping a conductor stores their id and opens the dashboard',
        (tester) async {
      await seed({
        'CND_NB_8701': {'conductor_id': 'CND_NB_8701', 'name': 'A. Silva'},
        'CND_NB_8710': {'conductor_id': 'CND_NB_8710', 'name': 'K. Perera'},
      }, tester);
      await tester.pumpWidget(app());
      await settle(tester);
      expect(provider.conductorId, isNull);

      await tester.tap(find.text('K. Perera'));
      await settle(tester);
      await tester.pumpAndSettle();

      expect(provider.conductorId, 'CND_NB_8710');
      expect(provider.conductor?.name, 'K. Perera');
      expect(find.text('home stub'), findsOneWidget);
    });

    testWidgets('a document without a conductor_id field uses its document id',
        (tester) async {
      await seed({'CND_ONLY_ID': {'name': 'No Field'}}, tester);
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text('CND_ONLY_ID'), findsOneWidget);
      await tester.tap(find.text('No Field'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(provider.conductorId, 'CND_ONLY_ID');
    });

    testWidgets('an empty conductors collection shows the seed-data message',
        (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);

      expect(find.text(emptyMessage), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('shows a spinner until the first snapshot arrives', (tester) async {
      await tester.pumpWidget(app());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(emptyMessage), findsNothing);
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a conductor added later appears without reloading', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.text(emptyMessage), findsOneWidget);

      await seed({'CND_1': {'conductor_id': 'CND_1', 'name': 'A. Silva'}}, tester);
      await settle(tester);

      expect(find.text(emptyMessage), findsNothing);
      expect(find.text('A. Silva'), findsOneWidget);
    });
  });
}
