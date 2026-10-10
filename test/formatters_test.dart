import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/utils/formatters.dart';

void main() {
  test('formatDuration renders HH:MM:SS and clamps negatives', () {
    expect(formatDuration(const Duration(minutes: 5, seconds: 7)), '00:05:07');
    expect(formatDuration(const Duration(seconds: -4)), '00:00:00');
  });

  test('formatBytes uses binary units', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(null), '—');
  });

  test('nullable date formatters show a dash when unknown', () {
    expect(formatTime(null), '—');
    expect(formatDateTime(null), '—');
  });
}
