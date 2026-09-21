import 'package:intl/intl.dart';

final DateFormat _dateTimeFormat = DateFormat('d MMM, HH:mm');

String formatDateTime(DateTime? value) =>
    value == null ? '—' : _dateTimeFormat.format(value.toLocal());

/// "unwanted_contact" -> "Unwanted contact". Empty input becomes an em dash.
String humanize(String raw) {
  final text = raw.replaceAll('_', ' ').trim();
  if (text.isEmpty) return '—';
  return text[0].toUpperCase() + text.substring(1);
}
