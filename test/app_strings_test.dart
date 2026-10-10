import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/i18n/app_strings.dart';

void main() {
  test('every supported locale resolves a known key', () {
    for (final locale in AppStrings.supportedLocales) {
      final s = AppStrings(locale);
      expect(s.t('cancel'), isNot('cancel'));
    }
  });

  test('placeholders are substituted', () {
    final s = AppStrings(const Locale('en'));
    expect(s.t('session_ends_at', {'time': '12:00'}), contains('12:00'));
  });

  test('Arabic is RTL and English is LTR', () {
    expect(AppStrings(const Locale('ar')).textDirection, TextDirection.rtl);
    expect(AppStrings(const Locale('en')).textDirection, TextDirection.ltr);
  });
}
