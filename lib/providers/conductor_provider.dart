import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/conductor.dart';

/// Holds the logged-in conductor and owns the FCM topic subscription for that
/// conductor.
///
/// Pilot/demo login: the conductor is picked from a list, with no password or
/// credential check.
class ConductorProvider extends ChangeNotifier {
  // subscribeToTopic can wait indefinitely while offline; don't block login.
  static const _subscribeTimeout = Duration(seconds: 10);

  Conductor? _conductor;
  bool _isLoggingIn = false;
  String? _subscribedTopic;
  String? _topicError;

  Conductor? get conductor => _conductor;
  String? get conductorId => _conductor?.conductorId;

  /// True while [login] is subscribing to the FCM topic.
  bool get isLoggingIn => _isLoggingIn;

  /// The FCM topic currently subscribed to, or null (always null where
  /// [pushSupported] is false).
  String? get subscribedTopic => _subscribedTopic;

  /// Why the topic subscription failed, or null. A failure does not block
  /// login (e.g. FCM topics are unavailable on some platforms); it only means
  /// no push notifications will arrive.
  String? get topicError => _topicError;

  static String topicFor(String conductorId) => 'conductor_$conductorId';

  /// FCM topic subscription only works on Android and iOS. Firebase's web SDK
  /// has no subscribeToTopic, and desktop has no FCM plugin, so on those
  /// platforms every FCM call is skipped rather than attempted and caught.
  static bool get pushSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Makes [conductor] the logged-in conductor and subscribes to their FCM
  /// topic (where supported). A messaging failure never fails the login.
  Future<void> login(Conductor conductor) async {
    if (_isLoggingIn) return;
    _isLoggingIn = true;
    _conductor = conductor;
    _topicError = null;
    notifyListeners();

    if (pushSupported) {
      final topic = topicFor(conductor.conductorId);
      try {
        await FirebaseMessaging.instance
            .subscribeToTopic(topic)
            .timeout(_subscribeTimeout);
        _subscribedTopic = topic;
      } catch (e) {
        _subscribedTopic = null;
        _topicError = e is TimeoutException
            ? 'Timed out subscribing to $topic'
            : e.toString();
      }

      // The permission prompt can sit open indefinitely, so don't await it.
      unawaited(_requestNotificationPermission());
    }

    _isLoggingIn = false;
    notifyListeners();
  }

  Future<void> logout() async {
    final topic = _subscribedTopic;
    _conductor = null;
    _subscribedTopic = null;
    _topicError = null;
    notifyListeners();

    // Otherwise a different conductor logging in on this device would keep
    // receiving the previous conductor's allocation alerts.
    if (topic != null) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      } catch (_) {
        // Best effort; nothing useful to tell the user.
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {
      // Unsupported platform or user dismissed it; not fatal.
    }
  }
}
