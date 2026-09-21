import 'dart:async';
import 'dart:collection';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';

/// Collects foreground FCM messages, newest first. Lives for the whole app
/// session (not the Notifications tab) so nothing is missed while another tab
/// is showing. Background/terminated messages are shown by the OS tray and are
/// not recorded here.
class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider() {
    try {
      _subscription = FirebaseMessaging.onMessage.listen(_onMessage);
    } catch (_) {
      // Messaging unavailable on this platform; the list just stays empty.
    }
  }

  StreamSubscription<RemoteMessage>? _subscription;
  final List<AppNotification> _items = [];

  UnmodifiableListView<AppNotification> get items =>
      UnmodifiableListView(_items);

  void _onMessage(RemoteMessage message) {
    _items.insert(0, AppNotification.fromRemoteMessage(message));
    notifyListeners();
  }

  /// Adds an in-app alert (new booking, incident, cash to collect) derived from
  /// live Firestore data. The passenger app's Cloud Function is never invoked,
  /// so no push arrives for these; this is what makes the tab useful.
  void addLocal({required String title, required String body}) {
    final now = DateTime.now();
    _items.insert(
      0,
      AppNotification(
        id: 'local_${now.microsecondsSinceEpoch}',
        title: title,
        body: body,
        receivedAt: now,
      ),
    );
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
