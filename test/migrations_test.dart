import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:winpilot/core/migrations/migrations.dart';

void main() {
  test('upgrade keeps settings, history and preferences', () async {
    SharedPreferences.setMockInitialValues({
      'settings.v1': 'user-settings',
      'sessions.v1': 'history',
      'auth.pkce.verifier': 'obsolete',
    });
    final prefs = await SharedPreferences.getInstance();
    final applied = await AppMigrations.run(prefs);

    expect(applied, [2]);
    expect(prefs.getString('settings.v1'), 'user-settings');
    expect(prefs.getString('sessions.v1'), 'history');
    expect(prefs.getString('auth.pkce.verifier'), isNull);
    expect(prefs.getInt(AppMigrations.schemaVersionKey), AppMigrations.currentSchema);
  });

  test('running twice is a no-op', () async {
    SharedPreferences.setMockInitialValues({'settings.v1': 'x'});
    final prefs = await SharedPreferences.getInstance();
    await AppMigrations.run(prefs);
    expect(await AppMigrations.run(prefs), isEmpty);
    expect(prefs.getString('settings.v1'), 'x');
  });

  test('a newer stored schema is left untouched', () async {
    SharedPreferences.setMockInitialValues({AppMigrations.schemaVersionKey: 99, 'k': 'v'});
    final prefs = await SharedPreferences.getInstance();
    expect(await AppMigrations.run(prefs), isEmpty);
    expect(prefs.getInt(AppMigrations.schemaVersionKey), 99);
    expect(prefs.getString('k'), 'v');
  });
}
