import '../data/field_compat.dart';

/// One reply the conductor sent to a passenger's message.
class ConductorReply {
  const ConductorReply({
    required this.text,
    required this.sentDatetime,
    required this.conductorId,
  });

  final String text;
  final DateTime? sentDatetime;
  final String conductorId;

  factory ConductorReply.fromMap(Map<String, dynamic> map) {
    return ConductorReply(
      text: asString(pick(map, 'text', 'reply_text')),
      sentDatetime: asDateTime(pick(map, 'sentDatetime', 'sent_datetime')),
      conductorId: asString(pick(map, 'conductorId', 'conductor_id')),
    );
  }
}

/// A passenger's "Text the conductor" message, from the `conductor_messages`
/// collection, with any replies the conductor has sent. Fields are snake_case
/// with ISO-string dates, like the rest of the passenger app's data.
class ConductorMessage {
  const ConductorMessage({
    required this.messageId,
    required this.journeyId,
    required this.busId,
    required this.passengerId,
    required this.seatNumber,
    required this.text,
    required this.sentDatetime,
    required this.status,
    this.replies = const [],
  });

  final String messageId;
  final String journeyId;
  final String busId;
  final String passengerId;
  final String seatNumber;
  final String text;
  final DateTime? sentDatetime;

  /// 'sent' when the passenger sends it, 'read' once the conductor has opened
  /// it, 'replied' once the conductor has answered.
  final String status;

  /// The conductor's replies, oldest first.
  final List<ConductorReply> replies;

  static const String statusSent = 'sent';
  static const String statusRead = 'read';
  static const String statusReplied = 'replied';

  /// Still waiting for the conductor's attention: neither read nor answered.
  bool get isUnread {
    final s = status.trim().toLowerCase();
    return s != statusRead && s != statusReplied;
  }

  bool get hasReply => replies.isNotEmpty;

  factory ConductorMessage.fromMap(Map<String, dynamic> map, String docId) {
    final rawReplies = map['replies'];
    return ConductorMessage(
      messageId: asString(pick(map, 'messageId', 'message_id'), docId),
      journeyId: asString(pick(map, 'journeyId', 'journey_id')),
      busId: asString(pick(map, 'busId', 'bus_id')),
      passengerId: asString(pick(map, 'passengerId', 'passenger_id')),
      seatNumber: asString(pick(map, 'seatNumber', 'seat_number')),
      text: asString(pick(map, 'messageText', 'message_text')),
      sentDatetime: asDateTime(pick(map, 'sentDatetime', 'sent_datetime')),
      status: asString(map['status'], statusSent),
      replies: [
        if (rawReplies is List)
          for (final r in rawReplies)
            if (r is Map) ConductorReply.fromMap(Map<String, dynamic>.from(r)),
      ],
    );
  }
}
