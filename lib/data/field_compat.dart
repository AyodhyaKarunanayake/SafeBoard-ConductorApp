import 'package:cloud_firestore/cloud_firestore.dart';

// Production data is snake_case with ISO-8601 string dates (that is what the
// passenger app writes). Reads still tolerate camelCase keys and Timestamps,
// which costs nothing and keeps hand-made documents working; camelCase wins
// when both are present. Queries and writes (data/conductor_repository.dart)
// use snake_case only.

/// Returns the value stored under [camel], falling back to [snake].
dynamic pick(Map<String, dynamic> data, String camel, String snake) =>
    data[camel] ?? data[snake];

String asString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

int asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

bool asBool(dynamic value) => value == true;

/// Accepts a Firestore [Timestamp] or an ISO-8601 string; null if neither.
DateTime? asDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Sorts [items] newest first by [dateOf]; items without a date go last.
/// Sorting happens client-side so the queries need no composite indexes and
/// work regardless of whether dates are stored as Timestamps or strings.
void sortNewestFirst<T>(List<T> items, DateTime? Function(T item) dateOf) {
  items.sort((a, b) {
    final da = dateOf(a);
    final db = dateOf(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
}
