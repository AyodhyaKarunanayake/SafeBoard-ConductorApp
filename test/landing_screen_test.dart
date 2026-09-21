import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safeboard_conductor/screens/landing_screen.dart';

Widget _app() => MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (_) => const LandingScreen(),
        '/login': (_) => const Scaffold(body: Text('login stub')),
      },
    );

void main() {
  // Physical size / device pixel ratio for a small phone and a wide desktop.
  const sizes = {
    'small phone': Size(320, 568),
    'desktop': Size(1440, 900),
  };

  for (final entry in sizes.entries) {
    testWidgets('renders without overflow on ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Live occupancy'), findsOneWidget);
    });
  }

  testWidgets('Get started opens the login route', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('login stub'), findsOneWidget);
  });
}
