import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/app_failure.dart';
import '../core/i18n/app_strings.dart';
import '../core/utils/validators.dart';
import '../models/session_models.dart';
import '../models/session_phase.dart';
import 'providers.dart';
import 'settings_state.dart';

enum RdpProbeState { idle, checking, reachable, unreachable }

class SessionState {
  const SessionState({
    this.records = const [],
    this.active,
    this.snapshot,
    this.failure,
    this.busy = false,
    this.refreshing = false,
    this.activity = const [],
    this.rdpProbe = RdpProbeState.idle,
    this.lastRefresh,
    this.runUnavailable = false,
  });

  final List<SessionRecord> records;
  final SessionRecord? active;
  final SessionSnapshot? snapshot;
  final AppFailure? failure;
  final bool busy;
  final bool refreshing;
  final List<ActivityEntry> activity;
  final RdpProbeState rdpProbe;
  final DateTime? lastRefresh;

  /// True when GitHub no longer returns this run (expired or deleted).
  final bool runUnavailable;

  SessionState copyWith({
    List<SessionRecord>? records,
    SessionRecord? active,
    bool clearActive = false,
    SessionSnapshot? snapshot,
    bool clearSnapshot = false,
    AppFailure? failure,
    bool clearFailure = false,
    bool? busy,
    bool? refreshing,
    List<ActivityEntry>? activity,
    RdpProbeState? rdpProbe,
    DateTime? lastRefresh,
    bool? runUnavailable,
  }) =>
      SessionState(
        records: records ?? this.records,
        active: clearActive ? null : (active ?? this.active),
        snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
        failure: clearFailure ? null : (failure ?? this.failure),
        busy: busy ?? this.busy,
        refreshing: refreshing ?? this.refreshing,
        activity: activity ?? this.activity,
        rdpProbe: rdpProbe ?? this.rdpProbe,
        lastRefresh: lastRefresh ?? this.lastRefresh,
        runUnavailable: runUnavailable ?? this.runUnavailable,
      );
}

/// Owns the active workflow run: dispatching, polling, notifications, RDP probe.
class SessionController extends Notifier<SessionState> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  bool _refreshing = false;
  final Set<String> _announced = {};

  @override
  SessionState build() {
    final store = ref.read(localSessionStoreProvider);
    final records = store.loadRecords();
    final activeId = store.activeRunId;
    SessionRecord? active;
    for (final r in records) {
      if (r.runId == activeId) active = r;
    }

    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        _ensureTimer();
        unawaited(refresh(silent: true));
      },
      onHide: () => _foreground = false,
      onPause: () => _foreground = false,
    );
    ref.onDispose(() {
      _timer?.cancel();
      _lifecycle?.dispose();
    });

    if (active != null && !active.phase.isTerminal) {
      Future<void>.microtask(() {
        _ensureTimer();
        unawaited(refresh(silent: true));
      });
    }
    return SessionState(records: records, active: active);
  }

  // ------------------------------------------------------------ commands

  Future<bool> startSession({
    required String repoFullName,
    required String branch,
    required SessionRequest request,
  }) async {
    final parts = repoFullName.split('/');
    if (parts.length != 2) {
      state = state.copyWith(failure: const AppFailure(FailureKind.validation));
      return false;
    }
    state = state.copyWith(busy: true, clearFailure: true);
    try {
      final record = await ref.read(githubRepositoryProvider).dispatchAndFindRun(
            owner: parts[0],
            repo: parts[1],
            branch: branch,
            request: request,
          );
      await _adopt(record);
      _log('activity_dispatched', ActivityKind.info, {'id': '${record.runId}'});
      unawaited(refresh(silent: true));
      return true;
    } on AppFailure catch (e) {
      state = state.copyWith(failure: e);
      return false;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> rerunActive() async {
    final active = state.active;
    if (active == null) return;
    await startSession(
      repoFullName: active.repoFullName,
      branch: active.branch,
      request: active.request,
    );
  }

  Future<void> cancelActive() async {
    final active = state.active;
    if (active == null || active.phase.isTerminal) return;
    state = state.copyWith(busy: true);
    try {
      await ref.read(githubRepositoryProvider).cancel(
            owner: active.owner,
            repo: active.repoName,
            runId: active.runId,
          );
      _log('activity_cancel_requested', ActivityKind.warning);
      await refresh(silent: true);
    } on AppFailure catch (e) {
      state = state.copyWith(failure: e);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  void selectRecord(SessionRecord record) {
    if (state.active?.runId == record.runId) return;
    unawaited(ref.read(localSessionStoreProvider).setActiveRunId(record.runId));
    state = state.copyWith(
      active: record,
      clearSnapshot: true,
      clearFailure: true,
      rdpProbe: RdpProbeState.idle,
      runUnavailable: false,
    );
    _ensureTimer();
    unawaited(refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    final active = state.active;
    if (active == null || _refreshing) return;
    _refreshing = true;
    if (!silent) state = state.copyWith(refreshing: true);
    try {
      final snap = await ref.read(githubRepositoryProvider).snapshot(
            owner: active.owner,
            repo: active.repoName,
            runId: active.runId,
          );
      if (state.active?.runId == active.runId) _applySnapshot(active, snap);
    } on AppFailure catch (e) {
      if (state.active?.runId != active.runId) return;
      if (e.kind == FailureKind.notFound) {
        state = state.copyWith(runUnavailable: true, failure: e);
      } else {
        state = state.copyWith(failure: e);
      }
    } finally {
      _refreshing = false;
      state = state.copyWith(refreshing: false, lastRefresh: DateTime.now());
    }
  }

  Future<void> probeRdp() async {
    final ip = state.snapshot?.diagnostics.tailscaleIp;
    if (ip == null || !Validators.isValidIpv4(ip)) {
      state = state.copyWith(rdpProbe: RdpProbeState.unreachable);
      return;
    }
    state = state.copyWith(rdpProbe: RdpProbeState.checking);
    final ok = await ref.read(rdpServiceProvider).probe(ip);
    state = state.copyWith(
      rdpProbe: ok ? RdpProbeState.reachable : RdpProbeState.unreachable,
    );
    _log(ok ? 'activity_rdp_reachable' : 'activity_rdp_unreachable',
        ok ? ActivityKind.success : ActivityKind.warning);
  }

  void clearHistory() {
    final keep = state.active != null && !state.active!.phase.isTerminal ? [state.active!] : <SessionRecord>[];
    state = SessionState(records: keep, active: keep.isEmpty ? null : keep.first);
    unawaited(ref.read(localSessionStoreProvider).saveRecords(keep));
  }

  void resetLocal() {
    _timer?.cancel();
    _announced.clear();
    state = const SessionState();
  }

  // ------------------------------------------------------------ internals

  Future<void> _adopt(SessionRecord record) async {
    final others = state.records.where((r) => r.runId != record.runId);
    final list = [record, ...others].take(AppConfig.maxStoredSessions).toList();
    state = state.copyWith(
      records: list,
      active: record,
      clearSnapshot: true,
      clearFailure: true,
      rdpProbe: RdpProbeState.idle,
      runUnavailable: false,
    );
    await ref.read(localSessionStoreProvider).saveRecords(list);
    await ref.read(localSessionStoreProvider).setActiveRunId(record.runId);
    _announced.clear();
    _ensureTimer();
  }

  void _applySnapshot(SessionRecord before, SessionSnapshot snap) {
    final run = snap.run;
    final phase = run.phase;
    final d = snap.diagnostics;
    final now = DateTime.now();

    final updated = before.copyWith(
      phase: phase,
      runStartedAt: run.runStartedAt ?? before.runStartedAt,
      endedAt: phase.isTerminal ? (run.updatedAt ?? now) : null,
      runNumber: run.runNumber,
      htmlUrl: run.htmlUrl,
      displayTitle: run.displayTitle.isEmpty ? before.displayTitle : run.displayTitle,
    );

    if (before.phase != phase) {
      final kind = switch (phase) {
        SessionPhase.succeeded => ActivityKind.success,
        SessionPhase.failed || SessionPhase.timedOut => ActivityKind.error,
        SessionPhase.cancelled => ActivityKind.warning,
        _ => ActivityKind.info,
      };
      _log('activity_phase', kind, {'phase': phase.labelKey});
      if (phase == SessionPhase.running) {
        _announce('running', 'notif_started_title', 'notif_started_body');
      }
    }

    if (d.rdpReady == true) {
      _announce('rdp', 'notif_ready_title', 'notif_ready_body');
    }
    if (d.error != null) {
      _log('activity_runner_error', ActivityKind.error, {'code': d.error!});
    }
    if (d.tailscaleState != null && d.tailscaleState != 'Running' && d.tailscaleState != 'disabled') {
      _announce('ts-${d.tailscaleState}', 'notif_ts_title', 'notif_ts_body');
    }

    if (phase.isTerminal) {
      final key = switch (phase) {
        SessionPhase.succeeded => 'done',
        SessionPhase.cancelled => 'cancelled',
        _ => 'failed',
      };
      _announce('end-$key', key == 'done' ? 'notif_done_title' : key == 'cancelled' ? 'notif_cancelled_title' : 'notif_failed_title',
          key == 'done' ? 'notif_done_body' : key == 'cancelled' ? 'notif_cancelled_body' : 'notif_failed_body');
    }

    final ends = d.sessionEndsAt;
    if (phase == SessionPhase.running &&
        ends != null &&
        ends.isAfter(now) &&
        ends.difference(now) <= AppConfig.expiryWarning) {
      _announce('expiring', 'notif_expiring_title', 'notif_expiring_body');
    }

    final shouldProbe = d.rdpReady == true &&
        d.tailscaleIp != null &&
        Validators.isValidIpv4(d.tailscaleIp!) &&
        state.rdpProbe == RdpProbeState.idle;

    state = state.copyWith(
      active: updated,
      snapshot: snap,
      records: [for (final r in state.records) r.runId == updated.runId ? updated : r],
      clearFailure: true,
      runUnavailable: false,
      lastRefresh: now,
    );
    unawaited(ref.read(localSessionStoreProvider).saveRecords(state.records));
    _ensureTimer();
    if (shouldProbe) unawaited(probeRdp());
  }

  /// Sends a local notification once per run and event key.
  void _announce(String event, String titleKey, String bodyKey) {
    final active = state.active;
    if (active == null) return;
    final id = '${active.runId}:$event';
    if (_announced.contains(id)) return;
    _announced.add(id);

    final settings = ref.read(settingsProvider);
    if (!settings.notificationsEnabled) return;
    final lang = settings.resolveLanguageCode(
      WidgetsBinding.instance.platformDispatcher.locale.languageCode,
    );
    final s = AppStrings(Locale(lang));
    unawaited(ref.read(notificationServiceProvider).show(
          id: _notificationId(active.runId, event),
          title: s.t(titleKey, {'run': '${active.runNumber ?? active.runId}'}),
          body: s.t(bodyKey, {'run': '${active.runNumber ?? active.runId}'}),
          channelName: s.t('notif_channel_name'),
          channelDescription: s.t('notif_channel_desc'),
        ));
  }

  /// Stable notification id per (run, event). Dart's hashCode is not guaranteed
  /// to be the same across launches, so a small deterministic hash is used.
  static int _notificationId(int runId, String event) {
    var h = 0;
    for (final unit in event.codeUnits) {
      h = (h * 31 + unit) & 0xffff;
    }
    return ((runId & 0xffffff) << 8 | h) & 0x7fffffff;
  }

  void _log(String key, ActivityKind kind, [Map<String, String> args = const {}]) {
    final entry = ActivityEntry(at: DateTime.now(), key: key, args: args, kind: kind);
    state = state.copyWith(activity: [entry, ...state.activity].take(40).toList());
  }

  void _ensureTimer() {
    final active = state.active;
    final shouldPoll = active != null && !active.phase.isTerminal && _foreground;
    if (shouldPoll && _timer == null) {
      _timer = Timer.periodic(AppConfig.pollInterval, (_) => unawaited(refresh(silent: true)));
    } else if (!shouldPoll && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
