import 'package:intl/intl.dart';

final DateFormat _dateTimeFormat = DateFormat('d MMM, HH:mm');
final NumberFormat _lkrFormat = NumberFormat('#,##0');

String formatDateTime(DateTime? value) =>
    value == null ? '—' : _dateTimeFormat.format(value.toLocal());

String formatLkr(double amount) => 'LKR ${_lkrFormat.format(amount)}';

/// "unwanted_contact" -> "Unwanted contact". Empty input becomes an em dash.
String humanize(String raw) {
  final text = raw.replaceAll('_', ' ').trim();
  if (text.isEmpty) return '—';
  return text[0].toUpperCase() + text.substring(1);
}
