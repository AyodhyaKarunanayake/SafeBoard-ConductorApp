import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/conductor_provider.dart';
import '../providers/journey_stream_provider.dart';
import '../providers/notifications_provider.dart';
import '../utils/ui.dart';
import 'cash_screen.dart';
import 'incidents_screen.dart';
import 'message_alert_dialog.dart';
import 'messages_screen.dart';
import 'notifications_screen.dart';
import 'seat_map_screen.dart';
import 'sos_alert_dialog.dart';
import 'trip_screen.dart';

/// Bottom-navigation shell: Trip, Seats, Incidents, Cash, Alerts.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _titles = ['Trip', 'Seat map', 'Incidents', 'Cash', 'Alerts'];

  int _index = 0;
  bool _alertOpen = false;

  void _logout() {
    final conductor = context.read<ConductorProvider>();
    context.read<NotificationsProvider>().clear();
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    unawaited(conductor.logout());
  }

  /// Shows waiting alerts as pop-ups over whatever screen is open, one at a
  /// time, until none are left: an unacknowledged SOS first, then messages that
  /// arrived live. Each is shown once per session; messages also stay on the
  /// Messages page afterwards.
  ///
  /// A freed seat is NOT handled here: filling it is the conductor's call, made
  /// in person, not something the app suggests. See _announceSeatFreed for the
  /// instant "seat is empty" notice, and SeatMapScreen.offerEmptySeat for the
  /// on-demand way to record who the conductor put there.
  Future<void> _showNextAlert() async {
    if (_alertOpen || !mounted) return;
    final trip = context.read<JourneyStreamProvider>();

    final sos = trip.pendingSos;
    if (sos.isNotEmpty) {
      final incident = sos.first;
      _alertOpen = true;
      final response = await showSosAlert(
        context,
        incident: incident,
        allocation: trip.allocationForSeat(incident.seatLocation),
      );
      _alertOpen = false;
      if (!mounted) return;

      switch (response) {
        case SosResponse.acknowledge:
          await runAction(context, () => trip.acknowledgeSos(incident),
              success: 'SOS acknowledged.');
        case SosResponse.view:
          trip.markSosHandled(incident);
          setState(() => _index = 2);
        case SosResponse.later:
          trip.markSosHandled(incident);
      }
    } else if (trip.pendingMessagePopups.isNotEmpty) {
      final message = trip.pendingMessagePopups.first;
      _alertOpen = true;
      final result = await showMessageAlert(context, message: message);
      _alertOpen = false;
      if (!mounted) return;

      // A reply already marks the pop-up as handled; "Later" does it here.
      if (result == MessageAlertResult.later) {
        trip.markMessagePopupHandled(message);
      }
    } else {
      return;
    }
    if (mounted) unawaited(_showNextAlert());
  }

  /// The brief "passenger left" alert: it shows for three seconds and goes away
  /// by itself. The seat on the map has already returned to its empty colour.
  void _announceSeatFreed() {
    if (!mounted) return;
    final trip = context.read<JourneyStreamProvider>();
    final messenger = ScaffoldMessenger.of(context);
    for (final event in trip.unannouncedSeatFreed) {
      trip.markSeatFreedAnnounced(event);
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.event_seat_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.wasSeated
                        ? 'Seat ${event.seat} is empty'
                        : 'A standing passenger left',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const Text('The passenger ended their journey.',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = context.select<ConductorProvider, String?>((p) => p.conductor?.name);
    final alertCount =
        context.select<NotificationsProvider, int>((p) => p.items.length);
    final openIncidents = context.select<JourneyStreamProvider, int>(
        (p) => p.incidents.where((i) => !i.isResolved).length);
    final cashDue =
        context.select<JourneyStreamProvider, int>((p) => p.cashToCollect.length);
    final unreadMessages = context
        .select<JourneyStreamProvider, int>((p) => p.unreadMessageCount);
    final alertsWaiting = context.select<JourneyStreamProvider, int>(
        (p) => p.pendingSos.length + p.pendingMessagePopups.length);
    final leftToAnnounce = context.select<JourneyStreamProvider, int>(
        (p) => p.unannouncedSeatFreed.length);
    final theme = Theme.of(context);

    // An SOS, a new message or a freed seat pops up from any tab.
    if (alertsWaiting > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNextAlert());
    }
    if (leftToAnnounce > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _announceSeatFreed());
    }

    Widget badged(int count, Widget icon) => Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: icon,
        );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[_index]),
            if (name != null && name.isNotEmpty)
              Text(name,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Messages',
            icon: Badge(
              isLabelVisible: unreadMessages > 0,
              label: Text('$unreadMessages'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MessagesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          TripScreen(),
          SeatMapScreen(),
          IncidentsScreen(),
          CashScreen(),
          NotificationsScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kHairline)),
        ),
        child: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.directions_bus_outlined),
            selectedIcon: Icon(Icons.directions_bus),
            label: 'Trip',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_seat_outlined),
            selectedIcon: Icon(Icons.event_seat),
            label: 'Seats',
          ),
          NavigationDestination(
            icon: badged(openIncidents, const Icon(Icons.report_problem_outlined)),
            selectedIcon: badged(openIncidents, const Icon(Icons.report_problem)),
            label: 'Incidents',
          ),
          NavigationDestination(
            icon: badged(cashDue, const Icon(Icons.payments_outlined)),
            selectedIcon: badged(cashDue, const Icon(Icons.payments)),
            label: 'Cash',
          ),
          NavigationDestination(
            icon: badged(alertCount, const Icon(Icons.notifications_outlined)),
            selectedIcon: badged(alertCount, const Icon(Icons.notifications)),
            label: 'Alerts',
          ),
        ],
      ),
      ),
    );
  }
}
