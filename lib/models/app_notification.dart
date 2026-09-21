import 'package:firebase_messaging/firebase_messaging.dart';

/// A foreground FCM message kept in memory for the Notifications tab.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.receivedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime receivedAt;

  factory AppNotification.fromRemoteMessage(RemoteMessage message) {
    final now = DateTime.now();
    final notification = message.notification;

    var title = notification?.title ?? '';
    var body = notification?.body ?? '';

    // Data-only messages carry no notification block; show their payload
    // rather than an empty card.
    if (title.isEmpty && body.isEmpty && message.data.isNotEmpty) {
      body = message.data.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    if (title.isEmpty) title = 'Notification';

    return AppNotification(
      id: message.messageId ?? '${now.microsecondsSinceEpoch}',
      title: title,
      body: body,
      receivedAt: now,
    );
  }
}
