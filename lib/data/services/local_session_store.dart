import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/session_models.dart';

/// Stores non-sensitive session metadata so the app can resume tracking.
class LocalSessionStore {
  LocalSessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const _recordsKey = 'sessions.records.v1';
  static const _activeKey = 'sessions.active_run.v1';

  List<SessionRecord> loadRecords() {
    final raw = _prefs.getString(_recordsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => SessionRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // Corrupted local cache: start clean rather than crash.
      return const [];
    }
  }

  Future<void> saveRecords(List<SessionRecord> records) => _prefs.setString(
        _recordsKey,
        jsonEncode(records.map((r) => r.toJson()).toList()),
      );

  int? get activeRunId => _prefs.getInt(_activeKey);

  Future<void> setActiveRunId(int? runId) =>
      runId == null ? _prefs.remove(_activeKey) : _prefs.setInt(_activeKey, runId);

  Future<void> clear() async {
    await _prefs.remove(_recordsKey);
    await _prefs.remove(_activeKey);
  }
}
