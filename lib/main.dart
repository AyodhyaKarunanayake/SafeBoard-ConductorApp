import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'providers/conductor_provider.dart';
import 'providers/journey_stream_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/reference_data_provider.dart';
import 'screens/home_shell.dart';
import 'screens/landing_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SafeBoardConductorApp());
}

class SafeBoardConductorApp extends StatelessWidget {
  const SafeBoardConductorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConductorProvider()),
        ChangeNotifierProvider(create: (_) => NotificationsProvider()),
        // Buses and the route: loaded once, after a conductor signs in.
        ChangeNotifierProxyProvider<ConductorProvider, ReferenceDataProvider>(
          create: (_) => ReferenceDataProvider(),
          update: (_, conductor, reference) {
            if (conductor.conductorId != null) reference!.ensureLoaded();
            return reference!;
          },
        ),
        // Follows the logged-in conductor: (re)subscribes to that conductor's
        // active trip whenever the id changes, and unsubscribes on sign-out.
        ChangeNotifierProxyProvider2<ConductorProvider, NotificationsProvider,
            JourneyStreamProvider>(
          create: (_) => JourneyStreamProvider(),
          update: (_, conductor, notifications, journeys) => journeys!
            ..bind(conductor.conductorId, notifications: notifications),
        ),
      ],
      child: MaterialApp(
        title: 'SafeBoard Conductor',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        initialRoute: '/',
        routes: {
          '/': (_) => const LandingScreen(),
          '/login': (_) => const LoginScreen(),
          '/home': (_) => const HomeShell(),
        },
      ),
    );
  }
}
