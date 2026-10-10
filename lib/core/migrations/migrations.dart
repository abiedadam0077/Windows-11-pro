import 'package:shared_preferences/shared_preferences.dart';

/// Versioned, forward-only data migrations.
///
/// Rules that keep updates safe:
/// * The stored schema version is the only thing migrations may read to decide
///   what to do; they never wipe data unless the schema truly changed.
/// * Migrations must be idempotent and must not delete settings or preferences.
/// * Add a new entry to [steps] with the next integer; never edit old steps.
abstract final class AppMigrations {
  static const schemaVersionKey = 'app.schema_version';

  /// Current schema. Version 1 is the layout shipped with 1.0.x. Version 2
  /// (1.1.0) only renames the obsolete OAuth web-flow keys; user settings,
  /// history and preferences are kept.
  static const currentSchema = 2;

  static final Map<int, Future<void> Function(SharedPreferences prefs)> steps = {
    2: _v2RemoveObsoleteOAuthKeys,
  };

  /// Runs every pending step in order and records the new schema version.
  /// Returns the list of schema versions that were applied (empty if none).
  static Future<List<int>> run(SharedPreferences prefs) async {
    final from = prefs.getInt(schemaVersionKey) ?? 1;
    final applied = <int>[];
    if (from > currentSchema) {
      // Downgrade (a newer build was installed before): keep data, do nothing.
      return applied;
    }
    for (var v = from + 1; v <= currentSchema; v++) {
      final step = steps[v];
      if (step != null) await step(prefs);
      applied.add(v);
    }
    if (from != currentSchema) await prefs.setInt(schemaVersionKey, currentSchema);
    return applied;
  }

  static Future<void> _v2RemoveObsoleteOAuthKeys(SharedPreferences prefs) async {
    // Web-flow PKCE state from 1.0.x is no longer used.
    for (final key in prefs.getKeys().where((k) => k.startsWith('auth.pkce.'))) {
      await prefs.remove(key);
    }
  }
}
