import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:safeboard_conductor/models/conductor.dart';
import 'package:safeboard_conductor/providers/conductor_provider.dart';
import 'package:safeboard_conductor/providers/notifications_provider.dart';
import 'package:safeboard_conductor/screens/notifications_screen.dart';

const _conductor = Conductor(
  conductorId: 'CND_1',
  name: 'Test Conductor',
  phoneNumber: '',
  rating: 5,
);

/// Runs [body] with the platform overridden, always restoring it (the test
/// framework fails a test that leaves the override set).
Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('ConductorProvider.pushSupported', () {
    test('is true only on Android and iOS', () async {
      for (final platform in TargetPlatform.values) {
        await _withPlatform(platform, () async {
          final expected = platform == TargetPlatform.android ||
              platform == TargetPlatform.iOS;
          expect(ConductorProvider.pushSupported, expected, reason: '$platform');
        });
      }
    });
  });

  group('ConductorProvider.login', () {
    test('skips FCM entirely on unsupported platforms', () async {
      await _withPlatform(TargetPlatform.windows, () async {
        final provider = ConductorProvider();
        await provider.login(_conductor);

        expect(provider.conductorId, 'CND_1');
        expect(provider.isLoggingIn, isFalse);
        expect(provider.subscribedTopic, isNull);
        // No FCM call was attempted, so nothing could have failed.
        expect(provider.topicError, isNull);
      });
    });

    test('still logs in when FCM throws on a supported platform', () async {
      // No Firebase app is initialised in unit tests, so the FCM call throws;
      // login must catch it and complete rather than crash.
      await _withPlatform(TargetPlatform.android, () async {
        final provider = ConductorProvider();
        await provider.login(_conductor);

        expect(provider.conductorId, 'CND_1');
        expect(provider.isLoggingIn, isFalse);
        expect(provider.subscribedTopic, isNull);
        expect(provider.topicError, isNotNull);
      });
    });
  });

  group('NotificationsScreen', () {
    Widget app() => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ConductorProvider()),
            ChangeNotifierProvider(create: (_) => NotificationsProvider()),
          ],
          child: const MaterialApp(home: Scaffold(body: NotificationsScreen())),
        );

    testWidgets('shows the requires-Android/iOS note where push is unsupported',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(app());
        expect(find.textContaining('Push notifications require the Android/iOS app'),
            findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('does not show the note on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(app());
        expect(find.textContaining('Push notifications require'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
