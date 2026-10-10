String _two(int v) => v.toString().padLeft(2, '0');

/// Formats a duration as HH:MM:SS, or D d HH:MM:SS when it spans days.
String formatDuration(Duration input) {
  final d = input.isNegative ? Duration.zero : input;
  final core = '${_two(d.inHours % 24)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
  return d.inDays > 0 ? '${d.inDays}d $core' : core;
}

/// Formats a local date-time as YYYY-MM-DD HH:MM. Returns '—' when unknown.
String formatDateTime(DateTime? value) {
  if (value == null) return '—';
  final l = value.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
}

String formatTime(DateTime? value) {
  if (value == null) return '—';
  final l = value.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

String formatBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

/// Returns the fraction (0..1) of [elapsed] over [total]; null if unknown.
double? fractionOf(Duration elapsed, Duration? total) {
  if (total == null || total.inSeconds <= 0) return null;
  return (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0);
}
